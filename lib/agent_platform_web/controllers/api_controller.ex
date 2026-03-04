defmodule AgentPlatformWeb.ApiController do
  @moduledoc """
  JSON API controller for the unified platform dashboard.

  Returns clients, agents, conversations, revenue, and satisfaction metrics.
  """

  use AgentPlatformWeb, :controller

  alias AgentPlatform.{Clients, Agents, Billing, Orchestrator}

  def clients(conn, _params) do
    clients =
      Clients.list_clients()
      |> Enum.map(fn client ->
        %{
          id: client.id,
          business_name: client.business_name,
          industry: client.industry,
          contact_name: client.contact_name,
          contact_email: client.contact_email,
          status: client.status,
          plan: client.plan,
          monthly_price_cents: client.monthly_price_cents,
          total_paid_cents: client.total_paid_cents,
          onboarded_at: client.onboarded_at,
          inserted_at: client.inserted_at
        }
      end)

    json(conn, %{clients: clients, count: length(clients)})
  end

  def metrics(conn, _params) do
    orchestrator_metrics = Orchestrator.get_metrics()

    platform_satisfaction = Agents.platform_satisfaction()
    total_conversations = Agents.total_conversations_all_time()

    metrics = %{
      active_clients: orchestrator_metrics.active_clients,
      active_agents: orchestrator_metrics.active_agents,
      conversations_today: orchestrator_metrics.total_conversations_today,
      conversations_all_time: total_conversations,
      conversations_per_minute: orchestrator_metrics.conversations_per_minute,
      mrr_cents: orchestrator_metrics.mrr_cents,
      mrr_display: orchestrator_metrics.mrr_display,
      platform_satisfaction: Float.round(platform_satisfaction * 1.0, 2),
      at_risk_clients: orchestrator_metrics.at_risk_count,
      capacity_utilization: orchestrator_metrics.capacity_utilization,
      health_status: orchestrator_metrics.health_status,
      uptime_seconds: orchestrator_metrics.uptime_seconds
    }

    json(conn, %{metrics: metrics})
  end

  def agents(conn, _params) do
    agents =
      Agents.list_agents()
      |> Enum.map(fn agent ->
        %{
          id: agent.id,
          client_id: agent.client_id,
          name: agent.name,
          type: agent.type,
          status: agent.status,
          total_conversations: agent.total_conversations,
          total_messages: agent.total_messages,
          satisfaction_score: agent.satisfaction_score,
          conversations_today: agent.conversations_today,
          inserted_at: agent.inserted_at
        }
      end)

    json(conn, %{agents: agents, count: length(agents)})
  end

  def revenue(conn, _params) do
    events = Billing.list_revenue_events(limit: 50)

    revenue_events =
      Enum.map(events, fn event ->
        %{
          id: event.id,
          client_id: event.client_id,
          type: event.type,
          amount_cents: event.amount_cents,
          inserted_at: event.inserted_at
        }
      end)

    json(conn, %{
      events: revenue_events,
      monthly_revenue_cents: Billing.monthly_revenue(),
      total_revenue_cents: Billing.total_revenue(),
      mrr_cents: Billing.mrr()
    })
  end

  def health(conn, _params) do
    capacity = Orchestrator.get_capacity()

    json(conn, %{
      status: "ok",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      capacity: capacity
    })
  end
end
