defmodule AgentPlatformWeb.DashboardLive do
  @moduledoc """
  LiveView dashboard for the Agent-as-a-Service platform.

  Displays:
  - Platform overview: active clients, total agents, conversations today
  - Revenue metrics, churn indicators
  - Client health cards (green/yellow/red status)
  - Live conversation feed
  - Agent performance rankings
  """

  use AgentPlatformWeb, :live_view

  alias AgentPlatform.{Clients, Agents, Billing, Orchestrator}

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentPlatform.PubSub, "platform:events")
      Phoenix.PubSub.subscribe(AgentPlatform.PubSub, "platform:metrics")
      :timer.send_interval(@refresh_interval, self(), :refresh)
    end

    socket =
      socket
      |> assign(:page_title, "AgentPlatform Dashboard")
      |> assign_metrics()
      |> assign_clients()
      |> assign_agents()
      |> assign_conversations()
      |> assign_revenue()

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info(:refresh, socket) do
    socket =
      socket
      |> assign_metrics()
      |> assign_clients()
      |> assign_agents()
      |> assign_conversations()

    {:noreply, socket}
  end

  def handle_info({:metrics_update, _metrics}, socket) do
    {:noreply, assign_metrics(socket)}
  end

  def handle_info({:conversation_update, _agent_id, _conv_id}, socket) do
    {:noreply, assign_conversations(socket)}
  end

  def handle_info({:client_onboarded, _client}, socket) do
    socket =
      socket
      |> assign_clients()
      |> assign_metrics()

    {:noreply, socket}
  end

  def handle_info({:revenue_event, _client_id, _amount}, socket) do
    {:noreply, assign_revenue(socket)}
  end

  def handle_info({:agent_health_alert, _agent_id, _status, _health}, socket) do
    {:noreply, assign_agents(socket)}
  end

  def handle_info({:escalation, _agent_id, _conv_id, _reason}, socket) do
    {:noreply, assign_conversations(socket)}
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Data Loading ---

  defp assign_metrics(socket) do
    metrics = Orchestrator.get_metrics()

    assign(socket,
      active_clients: metrics.active_clients,
      active_agents: metrics.active_agents,
      conversations_today: metrics.total_conversations_today,
      cpm: metrics.conversations_per_minute,
      mrr_cents: metrics.mrr_cents,
      mrr_display: metrics.mrr_display,
      at_risk_count: metrics.at_risk_count,
      capacity_util: Float.round(metrics.capacity_utilization * 100, 1),
      health_status: metrics.health_status,
      uptime: format_uptime(metrics.uptime_seconds),
      satisfaction: Float.round(Agents.platform_satisfaction() * 1.0, 1)
    )
  end

  defp assign_clients(socket) do
    clients =
      Clients.list_clients()
      |> Enum.map(fn client ->
        agents = Agents.list_agents_for_client(client.id)

        avg_satisfaction =
          case agents do
            [] -> 0.0
            agents ->
              total = Enum.sum(Enum.map(agents, & &1.satisfaction_score))
              Float.round(total / length(agents), 1)
          end

        convos_today = Enum.sum(Enum.map(agents, & &1.conversations_today))

        health =
          cond do
            client.status != :active -> :inactive
            avg_satisfaction < 2.0 -> :critical
            avg_satisfaction < 3.0 or convos_today == 0 -> :warning
            true -> :healthy
          end

        %{
          id: client.id,
          business_name: client.business_name,
          industry: client.industry,
          status: client.status,
          plan: client.plan,
          monthly_price: format_price(client.monthly_price_cents),
          agents_count: length(agents),
          satisfaction: avg_satisfaction,
          conversations_today: convos_today,
          health: health
        }
      end)

    assign(socket, :clients, clients)
  end

  defp assign_agents(socket) do
    agents =
      Agents.list_agents()
      |> Enum.sort_by(& &1.total_conversations, :desc)
      |> Enum.map(fn agent ->
        %{
          id: agent.id,
          name: agent.name,
          type: agent.type,
          status: agent.status,
          total_conversations: agent.total_conversations,
          conversations_today: agent.conversations_today,
          satisfaction: Float.round(agent.satisfaction_score * 1.0, 1),
          total_messages: agent.total_messages
        }
      end)

    assign(socket, :agents_ranked, agents)
  end

  defp assign_conversations(socket) do
    recent =
      Agents.list_recent_conversations(limit: 15)
      |> Enum.map(fn conv ->
        agent_name =
          case conv.agent do
            nil -> "Unknown"
            agent -> agent.name
          end

        message_count = length(conv.messages || [])
        last_message = List.last(conv.messages || [])

        %{
          id: conv.id,
          agent_name: agent_name,
          channel: conv.channel,
          status: conv.status,
          visitor_id: String.slice(conv.visitor_id || "", 0, 12),
          message_count: message_count,
          last_message: truncate(last_message["content"] || "", 80),
          time_ago: time_ago(conv.inserted_at)
        }
      end)

    assign(socket, :recent_conversations, recent)
  end

  defp assign_revenue(socket) do
    monthly = Billing.monthly_revenue()
    total = Billing.total_revenue()

    assign(socket,
      monthly_revenue: format_price(monthly),
      total_revenue: format_price(total)
    )
  end

  # --- Helpers ---

  defp format_price(nil), do: "$0"
  defp format_price(cents) when is_integer(cents) do
    dollars = cents / 100

    cond do
      dollars >= 10_000 -> "$#{Float.round(dollars / 1000, 1)}k"
      dollars >= 1_000 -> "$#{:erlang.float_to_binary(dollars, decimals: 0)}"
      true -> "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
    end
  end
  defp format_price(_), do: "$0"

  defp format_uptime(seconds) when is_integer(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    mins = div(rem(seconds, 3600), 60)

    cond do
      days > 0 -> "#{days}d #{hours}h"
      hours > 0 -> "#{hours}h #{mins}m"
      true -> "#{mins}m"
    end
  end
  defp format_uptime(_), do: "0m"

  defp time_ago(nil), do: "just now"
  defp time_ago(datetime) do
    diff = DateTime.diff(DateTime.utc_now(), datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  defp truncate(str, max) when byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end
  defp truncate(str, _max), do: str
end
