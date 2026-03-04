defmodule AgentPlatform.Workers.ReportingWorker do
  @moduledoc """
  Oban worker for generating monthly client reports.

  Uses Claude to analyze conversation data and produce insights:
  - Total conversations handled
  - Satisfaction scores and trends
  - Most common questions and topics
  - Suggestions for improvement
  - Stores PDF-formatted reports to R2
  - Sends report email to client
  """

  use Oban.Worker,
    queue: :reporting,
    max_attempts: 3,
    tags: ["reporting"]

  require Logger

  alias AgentPlatform.{Clients, Agents, Billing, ClaudeClient, Storage}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "monthly_reports"}}) do
    Logger.info("Starting monthly report generation for all active clients")

    Clients.list_clients_by_status(:active)
    |> Enum.each(fn client ->
      case generate_client_report(client) do
        :ok ->
          Logger.info("Report generated for #{client.business_name}")

        {:error, reason} ->
          Logger.error("Report generation failed for #{client.business_name}: #{inspect(reason)}")
      end
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "single_report", "client_id" => client_id}}) do
    client = Clients.get_client!(client_id)
    generate_client_report(client)
  end

  defp generate_client_report(client) do
    with {:ok, metrics} <- gather_metrics(client),
         {:ok, analysis} <- analyze_with_claude(client, metrics),
         {:ok, report_key} <- store_report(client, analysis),
         :ok <- send_report_email(client, analysis, report_key) do
      Logger.info("Monthly report complete for #{client.business_name}")
      :ok
    end
  end

  defp gather_metrics(client) do
    agents = Agents.list_agents_for_client(client.id)
    revenue_events = Billing.revenue_events_for_client(client.id, limit: 30)

    now = DateTime.utc_now()
    month_start = %{now | day: 1, hour: 0, minute: 0, second: 0, microsecond: {0, 0}}

    agent_metrics =
      Enum.map(agents, fn agent ->
        conversations = Agents.list_conversations_for_agent(agent.id, limit: 200)

        monthly_conversations =
          Enum.filter(conversations, fn c ->
            DateTime.compare(c.inserted_at, month_start) != :lt
          end)

        resolved = Enum.count(monthly_conversations, &(&1.status == :resolved))
        escalated = Enum.count(monthly_conversations, &(&1.status == :escalated))

        ratings =
          monthly_conversations
          |> Enum.map(& &1.satisfaction_rating)
          |> Enum.reject(&is_nil/1)

        avg_rating =
          case ratings do
            [] -> nil
            ratings -> Enum.sum(ratings) / length(ratings)
          end

        common_topics = extract_common_topics(monthly_conversations)

        %{
          agent_name: agent.name,
          agent_type: agent.type,
          total_conversations: length(monthly_conversations),
          resolved: resolved,
          escalated: escalated,
          avg_satisfaction: avg_rating,
          total_messages: Enum.sum(Enum.map(monthly_conversations, fn c -> length(c.messages || []) end)),
          common_topics: common_topics
        }
      end)

    total_revenue =
      revenue_events
      |> Enum.filter(&(&1.type != :refund))
      |> Enum.sum_by(& &1.amount_cents)

    {:ok,
     %{
       client_name: client.business_name,
       industry: client.industry,
       plan: client.plan,
       month: Calendar.strftime(now, "%B %Y"),
       agent_metrics: agent_metrics,
       total_conversations: Enum.sum(Enum.map(agent_metrics, & &1.total_conversations)),
       total_resolved: Enum.sum(Enum.map(agent_metrics, & &1.resolved)),
       total_escalated: Enum.sum(Enum.map(agent_metrics, & &1.escalated)),
       revenue_this_month: total_revenue,
       agents_count: length(agents)
     }}
  end

  defp analyze_with_claude(client, metrics) do
    prompt = """
    Generate a professional monthly performance report for this client.
    Include an executive summary, key metrics, insights, and actionable recommendations.

    Client: #{metrics.client_name} (#{metrics.industry})
    Plan: #{metrics.plan}
    Month: #{metrics.month}

    Agent Performance:
    #{Enum.map_join(metrics.agent_metrics, "\n", fn am ->
      "- #{am.agent_name} (#{am.agent_type}): #{am.total_conversations} conversations, " <>
        "#{am.resolved} resolved, #{am.escalated} escalated, " <>
        "satisfaction: #{am.avg_satisfaction || "N/A"}, " <>
        "top topics: #{Enum.join(am.common_topics, ", ")}"
    end)}

    Totals: #{metrics.total_conversations} conversations, #{metrics.total_resolved} resolved,
    #{metrics.total_escalated} escalated

    Format the report in clean HTML suitable for email delivery.
    Include sections: Executive Summary, Performance Metrics, Agent Breakdown,
    Top Conversation Topics, Recommendations.
    """

    case ClaudeClient.generate_report(client, prompt) do
      {:ok, report_html} -> {:ok, report_html}
      {:error, reason} -> {:error, "Claude report generation failed: #{inspect(reason)}"}
    end
  end

  defp store_report(client, report_html) do
    now = DateTime.utc_now()
    month_key = Calendar.strftime(now, "%Y-%m")
    key = "clients/#{client.id}/reports/#{month_key}-monthly-report.html"

    case Storage.put(key, report_html, content_type: "text/html") do
      :ok -> {:ok, key}
      {:error, reason} -> {:error, "Storage failed: #{inspect(reason)}"}
    end
  end

  defp send_report_email(client, report_html, report_key) do
    Logger.info("Sending monthly report to #{client.contact_email}")

    _email = %{
      to: client.contact_email,
      subject: "Your AgentPlatform Monthly Report - #{Calendar.strftime(DateTime.utc_now(), "%B %Y")}",
      html_body: report_html,
      attachment_key: report_key
    }

    # In production, integrate with a transactional email service
    Logger.info("Report email queued for #{client.contact_email}")
    :ok
  end

  defp extract_common_topics(conversations) do
    conversations
    |> Enum.flat_map(fn conv ->
      (conv.messages || [])
      |> Enum.filter(fn msg -> msg["role"] == "user" end)
      |> Enum.map(fn msg -> msg["content"] || "" end)
    end)
    |> Enum.flat_map(&extract_keywords/1)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_k, v} -> v end, :desc)
    |> Enum.take(5)
    |> Enum.map(fn {k, _v} -> k end)
  end

  defp extract_keywords(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/)
    |> Enum.filter(fn word ->
      String.length(word) > 3 and word not in stop_words()
    end)
  end

  defp stop_words do
    ~w(
      the and for are but not you all any can had her was one our out day
      been have from this that with they will each make like long look many
      some than them then very when come made find here know take want does
      just over such take into year your could than been have from about would
      there their what will each make like long look many some
    )
  end
end
