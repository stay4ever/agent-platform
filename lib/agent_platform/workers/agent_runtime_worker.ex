defmodule AgentPlatform.Workers.AgentRuntimeWorker do
  @moduledoc """
  Oban worker for processing incoming conversations.

  Handles the full conversation lifecycle:
  1. Route to correct agent based on token
  2. Apply system prompt and knowledge base context
  3. Call Claude API for response generation
  4. Manage conversation state and context window
  5. Detect escalation triggers
  6. Record conversation metrics
  7. Broadcast updates for real-time dashboard
  """

  use Oban.Worker,
    queue: :agent_runtime,
    max_attempts: 5,
    tags: ["agent_runtime"]

  require Logger

  alias AgentPlatform.{Agents, ClaudeClient, KnowledgeBase}
  alias AgentPlatform.Agents.{Agent, Conversation}

  @max_context_messages 20
  @escalation_confidence_threshold 0.7

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "agent_id" => agent_id,
          "conversation_id" => conversation_id,
          "message" => message,
          "visitor_id" => visitor_id,
          "channel" => channel
        }
      }) do
    Logger.metadata(agent_id: agent_id)
    Logger.info("Processing message for agent #{agent_id}, conversation #{conversation_id}")

    with {:ok, agent} <- fetch_agent(agent_id),
         {:ok, conversation} <- fetch_or_create_conversation(agent, conversation_id, visitor_id, channel),
         {:ok, conversation} <- append_user_message(conversation, message),
         {:ok, context} <- build_context(agent, conversation),
         {:ok, response} <- generate_response(agent, context),
         {:ok, conversation} <- append_assistant_message(conversation, response),
         :ok <- check_escalation(agent, conversation, response),
         :ok <- update_metrics(agent, conversation) do
      broadcast_message(agent, conversation, response)
      {:ok, %{conversation_id: conversation.id, response: response}}
    else
      {:escalate, conversation, reason} ->
        handle_escalation(agent_id, conversation, reason)
        {:ok, %{conversation_id: conversation.id, escalated: true, reason: reason}}

      {:error, reason} ->
        Logger.error("Agent runtime error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"type" => "reset_daily_counters"}}) do
    Agents.reset_daily_counters()
    Logger.info("Daily conversation counters reset")
    :ok
  end

  defp fetch_agent(agent_id) do
    case Agents.get_agent(agent_id) do
      nil -> {:error, "Agent not found: #{agent_id}"}
      %Agent{status: :active} = agent -> {:ok, agent}
      %Agent{status: status} -> {:error, "Agent not active (#{status})"}
    end
  end

  defp fetch_or_create_conversation(agent, nil, visitor_id, channel) do
    case Agents.get_active_conversation(agent.id, visitor_id) do
      nil ->
        Agents.create_conversation(%{
          agent_id: agent.id,
          visitor_id: visitor_id,
          channel: String.to_existing_atom(channel)
        })

      conversation ->
        {:ok, conversation}
    end
  end

  defp fetch_or_create_conversation(_agent, conversation_id, _visitor_id, _channel) do
    case Agents.get_conversation(conversation_id) do
      nil -> {:error, "Conversation not found: #{conversation_id}"}
      conversation -> {:ok, conversation}
    end
  end

  defp append_user_message(%Conversation{} = conversation, message) do
    Agents.add_message(conversation, %{role: "user", content: message})
  end

  defp append_assistant_message(%Conversation{} = conversation, response) do
    Agents.add_message(conversation, %{role: "assistant", content: response})
  end

  defp build_context(%Agent{} = agent, %Conversation{} = conversation) do
    messages = conversation.messages || []

    trimmed_messages =
      messages
      |> Enum.take(-@max_context_messages)
      |> Enum.map(fn msg ->
        %{role: msg["role"], content: msg["content"]}
      end)

    knowledge_context =
      case agent.knowledge_base_key do
        nil -> ""
        key ->
          case KnowledgeBase.retrieve(key, List.last(messages)["content"] || "") do
            {:ok, context} -> context
            _ -> ""
          end
      end

    {:ok,
     %{
       system_prompt: agent.system_prompt,
       knowledge_context: knowledge_context,
       messages: trimmed_messages,
       agent_config: agent.config
     }}
  end

  defp generate_response(%Agent{} = agent, context) do
    full_system_prompt = build_system_prompt(agent, context)

    case ClaudeClient.chat(full_system_prompt, context.messages, agent.config) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, "Claude API error: #{inspect(reason)}"}
    end
  end

  defp build_system_prompt(%Agent{} = agent, context) do
    base = context.system_prompt || ""
    knowledge = context.knowledge_context || ""

    config = agent.config || %{}
    greeting = config["greeting"] || ""
    hours = config["business_hours"] || %{}

    """
    #{base}

    KNOWLEDGE BASE CONTEXT:
    #{knowledge}

    AGENT CONFIGURATION:
    - Default greeting: #{greeting}
    - Business hours: #{hours["start"] || "N/A"} - #{hours["end"] || "N/A"} (#{hours["timezone"] || "UTC"})
    - Language: #{config["language"] || "en"}

    CONVERSATION GUIDELINES:
    - Be helpful, professional, and concise
    - If the visitor asks something outside your knowledge, acknowledge it and offer to connect them with a human
    - Never make up information about the business
    - Track the visitor's intent and guide them toward resolution
    - If the conversation has been going on for more than 10 exchanges without resolution, suggest connecting with a human
    """
  end

  defp check_escalation(%Agent{} = agent, %Conversation{} = conversation, response) do
    config = agent.config || %{}
    triggers = config["escalation_triggers"] || []
    last_user_message = get_last_user_message(conversation)

    should_escalate =
      Enum.any?(triggers, fn trigger ->
        trigger_lower = String.downcase(trigger)

        String.contains?(String.downcase(last_user_message), trigger_lower) or
          String.contains?(String.downcase(response), "connect you with") or
          String.contains?(String.downcase(response), "transfer you to")
      end)

    message_count = length(conversation.messages || [])
    long_conversation = message_count > 20

    if should_escalate or long_conversation do
      reason =
        cond do
          long_conversation -> "Extended conversation without resolution (#{message_count} messages)"
          true -> "Escalation trigger detected in conversation"
        end

      {:escalate, conversation, reason}
    else
      :ok
    end
  end

  defp handle_escalation(agent_id, conversation, reason) do
    Logger.info("Escalating conversation #{conversation.id}: #{reason}")

    Agents.escalate_conversation(conversation, %{
      outcome: "escalated",
      metadata: Map.put(conversation.metadata || %{}, "escalation_reason", reason)
    })

    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "agent:#{agent_id}",
      {:conversation_escalated, conversation.id, reason}
    )

    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:escalation, agent_id, conversation.id, reason}
    )
  end

  defp update_metrics(%Agent{} = agent, %Conversation{} = conversation) do
    Agents.increment_messages(agent, 2)

    if length(conversation.messages || []) <= 2 do
      Agents.increment_conversations(agent)
    end

    :ok
  end

  defp broadcast_message(%Agent{} = agent, %Conversation{} = conversation, response) do
    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "conversation:#{conversation.id}",
      {:new_message, %{role: "assistant", content: response}}
    )

    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:conversation_update, agent.id, conversation.id}
    )
  end

  defp get_last_user_message(%Conversation{messages: messages}) do
    messages
    |> Enum.reverse()
    |> Enum.find(fn msg -> msg["role"] == "user" end)
    |> case do
      nil -> ""
      msg -> msg["content"] || ""
    end
  end
end
