defmodule AgentPlatform.ClaudeClient do
  @moduledoc """
  Claude API wrapper for the Agent-as-a-Service platform.

  Provides:
  - chat/3: Conversation handling with system prompt and message history
  - generate_system_prompt/2: Creates industry-tailored agent prompts
  - analyze_conversation/1: Analyzes conversation patterns for tuning
  - generate_report/2: Generates monthly performance reports

  Manages conversation context windows efficiently to stay within token limits.
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"

  def chat(system_prompt, messages, config \\ %{}) do
    claude_config = Application.get_env(:agent_platform, :claude)
    api_key = claude_config[:api_key]
    model = config["model"] || claude_config[:model] || "claude-sonnet-4-20250514"
    max_tokens = config["max_tokens"] || claude_config[:max_tokens] || 4096

    formatted_messages =
      Enum.map(messages, fn msg ->
        %{
          "role" => to_string(msg[:role] || msg["role"]),
          "content" => to_string(msg[:content] || msg["content"])
        }
      end)

    body =
      Jason.encode!(%{
        model: model,
        max_tokens: max_tokens,
        system: system_prompt,
        messages: formatted_messages
      })

    headers = [
      {"content-type", "application/json"},
      {"x-api-key", api_key},
      {"anthropic-version", @api_version}
    ]

    case Req.post(@api_url, body: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        content =
          response_body
          |> Map.get("content", [])
          |> Enum.find(fn block -> block["type"] == "text" end)
          |> case do
            nil -> {:error, "No text content in response"}
            block -> {:ok, block["text"]}
          end

        content

      {:ok, %{status: status, body: body}} ->
        Logger.error("Claude API error #{status}: #{inspect(body)}")
        {:error, "Claude API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        Logger.error("Claude API request failed: #{inspect(reason)}")
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  def generate_system_prompt(client, agent_config) do
    prompt = """
    You are a professional #{agent_config.type} agent for #{client.business_name},
    a #{client.industry} business.

    Your name is #{agent_config.name}.

    Core responsibilities:
    #{type_responsibilities(agent_config.type)}

    Communication style:
    - Professional yet warm and approachable
    - Concise responses (2-3 sentences when possible)
    - Always address the visitor's specific question
    - Use the business's terminology naturally
    - Never fabricate information about the business

    Business context:
    - Business: #{client.business_name}
    - Industry: #{client.industry}
    - Website: #{client.website || "N/A"}

    Greeting: #{agent_config.greeting}

    When you cannot help or detect these escalation triggers, politely offer to
    connect the visitor with a human team member:
    #{Enum.join(agent_config.escalation_triggers, ", ")}

    Business hours: #{agent_config.business_hours[:start]} - #{agent_config.business_hours[:end]}
    (#{agent_config.business_hours[:timezone]})

    Outside business hours, let visitors know when the team will be available
    and offer to take a message.
    """

    prompt
  end

  def analyze_conversation(prompt) do
    system = """
    You are an AI conversation analyst for a multi-tenant agent platform.
    Analyze the provided conversation data and return actionable insights.
    Be specific and data-driven in your recommendations.
    """

    messages = [%{role: "user", content: prompt}]
    chat(system, messages)
  end

  def generate_report(client, prompt) do
    system = """
    You are a professional business analyst generating monthly performance reports
    for #{client.business_name} (#{client.industry}).

    Generate clean, well-structured HTML reports with:
    - Executive summary (2-3 key takeaways)
    - Performance metrics with context
    - Agent-by-agent breakdown
    - Actionable recommendations
    - Professional formatting suitable for email delivery

    Use a clean, modern style. No inline JavaScript.
    """

    messages = [%{role: "user", content: prompt}]
    chat(system, messages)
  end

  defp type_responsibilities(:receptionist) do
    """
    - Greet visitors warmly and professionally
    - Understand their needs and direct them appropriately
    - Answer general business questions
    - Capture contact information when relevant
    - Handle basic scheduling requests
    """
  end

  defp type_responsibilities(:appointment_booker) do
    """
    - Help visitors schedule, reschedule, or cancel appointments
    - Check availability and suggest alternatives
    - Collect necessary appointment information
    - Send confirmation details
    - Handle scheduling conflicts gracefully
    """
  end

  defp type_responsibilities(:lead_qualifier) do
    """
    - Engage potential customers in qualifying conversations
    - Understand their needs, budget, timeline, and decision process
    - Score leads based on qualification criteria
    - Route qualified leads to the appropriate team member
    - Capture detailed notes for follow-up
    """
  end

  defp type_responsibilities(:faq_responder) do
    """
    - Answer frequently asked questions accurately
    - Reference the knowledge base for specific information
    - Provide clear, concise answers
    - Offer links or next steps when available
    - Flag questions that aren't covered in the knowledge base
    """
  end

  defp type_responsibilities(:follow_up) do
    """
    - Reach out to previous visitors and customers
    - Check on their experience and satisfaction
    - Address any unresolved concerns
    - Identify upsell or cross-sell opportunities
    - Maintain the relationship and build loyalty
    """
  end

  defp type_responsibilities(:review_manager) do
    """
    - Engage customers about their experience
    - Collect satisfaction ratings and feedback
    - Address negative feedback professionally
    - Encourage satisfied customers to leave reviews
    - Route serious complaints to management
    """
  end
end
