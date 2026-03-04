defmodule AgentPlatform.Orchestrator do
  @moduledoc """
  GenServer managing all client agents platform-wide.

  Responsibilities:
  - Monitor platform capacity (conversations/minute)
  - Handle auto-scaling decisions
  - Detect churn risk (declining usage, low satisfaction)
  - Trigger proactive outreach for at-risk clients
  - Plan capacity for growth
  - Coordinate agent lifecycle across the platform
  """

  use GenServer

  require Logger

  alias AgentPlatform.{Clients, Agents, Billing}

  @tick_interval :timer.minutes(1)
  @churn_check_interval :timer.hours(6)
  @capacity_check_interval :timer.minutes(5)

  defstruct [
    :started_at,
    conversations_per_minute: 0,
    peak_conversations_per_minute: 0,
    active_clients: 0,
    active_agents: 0,
    total_conversations_today: 0,
    mrr_cents: 0,
    at_risk_clients: [],
    capacity_utilization: 0.0,
    last_churn_check: nil,
    last_capacity_check: nil,
    health_status: :healthy
  ]

  # --- Client API ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def get_metrics do
    GenServer.call(__MODULE__, :get_metrics)
  end

  def get_capacity do
    GenServer.call(__MODULE__, :get_capacity)
  end

  def report_conversation do
    GenServer.cast(__MODULE__, :report_conversation)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Orchestrator starting up")

    state = %__MODULE__{
      started_at: DateTime.utc_now()
    }

    schedule_tick()
    schedule_churn_check()
    schedule_capacity_check()

    send(self(), :refresh_metrics)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      active_clients: state.active_clients,
      active_agents: state.active_agents,
      total_conversations_today: state.total_conversations_today,
      conversations_per_minute: state.conversations_per_minute,
      peak_cpm: state.peak_conversations_per_minute,
      mrr_cents: state.mrr_cents,
      mrr_display: format_currency(state.mrr_cents),
      at_risk_count: length(state.at_risk_clients),
      capacity_utilization: state.capacity_utilization,
      health_status: state.health_status,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second)
    }

    {:reply, metrics, state}
  end

  def handle_call(:get_capacity, _from, state) do
    capacity = %{
      current_cpm: state.conversations_per_minute,
      peak_cpm: state.peak_conversations_per_minute,
      utilization: state.capacity_utilization,
      max_capacity: max_platform_capacity(),
      recommendation: capacity_recommendation(state)
    }

    {:reply, capacity, state}
  end

  @impl true
  def handle_cast(:report_conversation, state) do
    new_cpm = state.conversations_per_minute + 1
    new_peak = max(new_cpm, state.peak_conversations_per_minute)
    new_total = state.total_conversations_today + 1

    {:noreply, %{state | conversations_per_minute: new_cpm, peak_conversations_per_minute: new_peak, total_conversations_today: new_total}}
  end

  def handle_cast(:refresh, state) do
    {:noreply, refresh_metrics(state)}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = %{state | conversations_per_minute: 0}
    schedule_tick()
    {:noreply, new_state}
  end

  def handle_info(:refresh_metrics, state) do
    {:noreply, refresh_metrics(state)}
  end

  def handle_info(:churn_check, state) do
    new_state = run_churn_check(state)
    schedule_churn_check()
    {:noreply, new_state}
  end

  def handle_info(:capacity_check, state) do
    new_state = run_capacity_check(state)
    schedule_capacity_check()
    {:noreply, new_state}
  end

  # --- Internal Logic ---

  defp refresh_metrics(state) do
    active_clients = Clients.count_active_clients()
    active_agents = Agents.count_active_agents()
    total_today = Agents.total_conversations_today()
    mrr = Billing.mrr()

    health =
      cond do
        active_agents == 0 -> :idle
        state.capacity_utilization > 0.9 -> :stressed
        length(state.at_risk_clients) > active_clients * 0.3 -> :warning
        true -> :healthy
      end

    broadcast_metrics_update(%{
      active_clients: active_clients,
      active_agents: active_agents,
      conversations_today: total_today,
      mrr_cents: mrr,
      health: health
    })

    %{
      state
      | active_clients: active_clients,
        active_agents: active_agents,
        total_conversations_today: total_today,
        mrr_cents: mrr,
        health_status: health
    }
  end

  defp run_churn_check(state) do
    Logger.info("Running churn risk analysis")

    at_risk = Clients.clients_at_risk()

    Enum.each(at_risk, fn client ->
      Logger.warn("Churn risk detected: #{client.business_name} (#{client.id})")

      Phoenix.PubSub.broadcast(
        AgentPlatform.PubSub,
        "platform:events",
        {:churn_risk, client.id, client.business_name}
      )
    end)

    if length(at_risk) > length(state.at_risk_clients) do
      Logger.warn(
        "At-risk clients increased from #{length(state.at_risk_clients)} to #{length(at_risk)}"
      )
    end

    %{state | at_risk_clients: Enum.map(at_risk, & &1.id), last_churn_check: DateTime.utc_now()}
  end

  defp run_capacity_check(state) do
    max_cap = max_platform_capacity()

    utilization =
      if max_cap > 0 do
        state.peak_conversations_per_minute / max_cap
      else
        0.0
      end

    if utilization > 0.8 do
      Logger.warn("Platform capacity at #{Float.round(utilization * 100, 1)}%")

      Phoenix.PubSub.broadcast(
        AgentPlatform.PubSub,
        "platform:events",
        {:capacity_warning, utilization}
      )
    end

    %{state | capacity_utilization: utilization, last_capacity_check: DateTime.utc_now()}
  end

  defp capacity_recommendation(state) do
    cond do
      state.capacity_utilization > 0.9 -> "CRITICAL: Scale up immediately. Add more agent_runtime workers."
      state.capacity_utilization > 0.7 -> "WARNING: Consider scaling. Utilization trending high."
      state.capacity_utilization > 0.5 -> "MONITOR: Healthy utilization. Plan for growth."
      true -> "OK: Plenty of capacity available."
    end
  end

  defp max_platform_capacity do
    # Based on agent_runtime queue limit of 5, each handling ~10 conversations/minute
    oban_config = Application.get_env(:agent_platform, Oban)
    agent_runtime_limit = get_in(oban_config, [:queues, :agent_runtime]) || 5
    agent_runtime_limit * 10
  end

  defp broadcast_metrics_update(metrics) do
    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:metrics",
      {:metrics_update, metrics}
    )
  end

  defp format_currency(cents) when is_integer(cents) do
    dollars = div(cents, 100)

    cond do
      dollars >= 1000 -> "$#{Float.round(dollars / 1000, 1)}k"
      true -> "$#{dollars}"
    end
  end

  defp format_currency(_), do: "$0"

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_interval)
  defp schedule_churn_check, do: Process.send_after(self(), :churn_check, @churn_check_interval)
  defp schedule_capacity_check, do: Process.send_after(self(), :capacity_check, @capacity_check_interval)
end
