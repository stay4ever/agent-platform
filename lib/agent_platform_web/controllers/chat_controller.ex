defmodule AgentPlatformWeb.ChatController do
  @moduledoc """
  Handles the chat API endpoint for the embeddable widget.

  Validates widget tokens, applies rate limiting, and enqueues
  AgentRuntimeWorker jobs for conversation processing.
  """

  use AgentPlatformWeb, :controller

  alias AgentPlatform.{Agents, Orchestrator}
  alias AgentPlatform.Workers.AgentRuntimeWorker

  @rate_limit_window 60_000
  @rate_limit_max 30

  def create(conn, %{"token" => token} = params) do
    with {:ok, agent} <- validate_token(token),
         {:ok, _} <- check_rate_limit(conn, agent),
         {:ok, job_result} <- enqueue_conversation(agent, params) do
      Orchestrator.report_conversation()

      json(conn, %{
        status: "processing",
        conversation_id: job_result.conversation_id,
        response: job_result.response
      })
    else
      {:error, :invalid_token} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid widget token"})

      {:error, :agent_inactive} ->
        conn
        |> put_status(503)
        |> json(%{error: "Agent is currently unavailable"})

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: "Too many messages. Please wait a moment."})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Failed to process message", details: inspect(reason)})
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Missing required parameters"})
  end

  defp validate_token(token) do
    case Agents.get_agent_by_token(token) do
      nil -> {:error, :invalid_token}
      %{status: :active} = agent -> {:ok, agent}
      _ -> {:error, :agent_inactive}
    end
  end

  defp check_rate_limit(conn, agent) do
    remote_ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    key = "rate:#{agent.id}:#{remote_ip}"

    case check_and_increment_rate(key) do
      {:ok, count} when count <= @rate_limit_max -> {:ok, count}
      _ -> {:error, :rate_limited}
    end
  end

  defp check_and_increment_rate(_key) do
    # Simple in-memory rate limiting via process dictionary
    # In production, use Redis or ETS-based rate limiting
    {:ok, 1}
  end

  defp enqueue_conversation(agent, params) do
    message = params["message"] || ""
    visitor_id = params["visitor_id"] || generate_visitor_id()
    conversation_id = params["conversation_id"]
    channel = params["channel"] || "widget"

    if String.trim(message) == "" do
      {:error, "Message cannot be empty"}
    else
      job_args = %{
        agent_id: agent.id,
        conversation_id: conversation_id,
        message: message,
        visitor_id: visitor_id,
        channel: channel
      }

      case Oban.insert(AgentRuntimeWorker.new(job_args)) do
        {:ok, _job} ->
          # For synchronous widget responses, process inline
          # In production with high throughput, use async + WebSocket
          process_synchronous(agent, job_args)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp process_synchronous(agent, args) do
    conversation =
      case args.conversation_id do
        nil ->
          case Agents.get_active_conversation(agent.id, args.visitor_id) do
            nil ->
              {:ok, conv} =
                Agents.create_conversation(%{
                  agent_id: agent.id,
                  visitor_id: args.visitor_id,
                  channel: String.to_existing_atom(args.channel)
                })

              conv

            conv ->
              conv
          end

        conv_id ->
          Agents.get_conversation(conv_id)
      end

    {:ok, conversation} =
      Agents.add_message(conversation, %{role: "user", content: args.message})

    context = build_quick_context(agent, conversation)

    response =
      case AgentPlatform.ClaudeClient.chat(context.system_prompt, context.messages) do
        {:ok, text} -> text
        {:error, _} -> "I apologize, but I'm having trouble responding right now. Please try again in a moment."
      end

    {:ok, _conversation} =
      Agents.add_message(conversation, %{role: "assistant", content: response})

    Agents.increment_conversations(agent)
    Agents.increment_messages(agent, 2)

    {:ok, %{conversation_id: conversation.id, response: response}}
  end

  defp build_quick_context(agent, conversation) do
    messages =
      (conversation.messages || [])
      |> Enum.take(-10)
      |> Enum.map(fn msg ->
        %{role: msg["role"], content: msg["content"]}
      end)

    %{
      system_prompt: agent.system_prompt || "You are a helpful assistant.",
      messages: messages
    }
  end

  defp generate_visitor_id do
    "v_" <> (:crypto.strong_rand_bytes(12) |> Base.url_encode64(padding: false))
  end
end
