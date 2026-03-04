defmodule AgentPlatform.Workers.MonitoringWorker do
  @moduledoc """
  Oban worker for platform health monitoring.

  Performs continuous monitoring:
  - Health checks on all active agents
  - Response latency tracking
  - Error rate monitoring
  - Satisfaction trend analysis
  - Alerts on performance degradation
  - Auto-tunes system prompts based on conversation patterns
  """

  use Oban.Worker,
    queue: :monitoring,
    max_attempts: 5,
    tags: ["monitoring"]

  require Logger

  alias AgentPlatform.{Agents, Clients, ClaudeClient}
  alias AgentPlatform.Agents.Agent

  @satisfaction_warning_threshold 3.0
  @satisfaction_critical_threshold 2.0
  @error_rate_threshold 0.1
  @min_conversations_for_tuning 50

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "health_check"}}) do
    Logger.info("Running platform health check")

    active_agents = Agents.list_active_agents()

    results =
      Enum.map(active_agents, fn agent ->
        health = check_agent_health(agent)
        {agent, health}
      end)

    {healthy, degraded} = Enum.split_with(results, fn {_agent, health} -> health.status == :healthy end)

    Enum.each(degraded, fn {agent, health} ->
      handle_degraded_agent(agent, health)
    end)

    broadcast_health_status(length(healthy), length(degraded))

    Logger.info(
      "Health check complete: #{length(healthy)} healthy, #{length(degraded)} degraded"
    )

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "auto_tune", "agent_id" => agent_id}}) do
    Logger.info("Auto-tuning agent #{agent_id}")

    agent = Agents.get_agent!(agent_id)
    auto_tune_agent(agent)
  end

  def perform(%Oban.Job{args: %{"type" => "satisfaction_analysis"}}) do
    Logger.info("Running satisfaction trend analysis")

    Agents.list_active_agents()
    |> Enum.each(fn agent ->
      analyze_satisfaction_trend(agent)
    end)

    :ok
  end

  defp check_agent_health(%Agent{} = agent) do
    conversations = Agents.list_conversations_for_agent(agent.id, limit: 100)

    recent =
      conversations
      |> Enum.filter(fn c ->
        DateTime.diff(DateTime.utc_now(), c.inserted_at, :hour) < 24
      end)

    total_recent = length(recent)
    escalated = Enum.count(recent, &(&1.status == :escalated))
    abandoned = Enum.count(recent, &(&1.status == :abandoned))

    error_rate =
      if total_recent > 0 do
        (escalated + abandoned) / total_recent
      else
        0.0
      end

    ratings =
      recent
      |> Enum.map(& &1.satisfaction_rating)
      |> Enum.reject(&is_nil/1)

    avg_satisfaction =
      case ratings do
        [] -> agent.satisfaction_score
        r -> Enum.sum(r) / length(r)
      end

    avg_message_count =
      case recent do
        [] ->
          0

        convos ->
          Enum.sum(Enum.map(convos, fn c -> length(c.messages || []) end)) / length(convos)
      end

    status =
      cond do
        avg_satisfaction < @satisfaction_critical_threshold -> :critical
        avg_satisfaction < @satisfaction_warning_threshold -> :warning
        error_rate > @error_rate_threshold -> :warning
        true -> :healthy
      end

    %{
      status: status,
      conversations_24h: total_recent,
      escalation_rate: if(total_recent > 0, do: escalated / total_recent, else: 0.0),
      abandonment_rate: if(total_recent > 0, do: abandoned / total_recent, else: 0.0),
      error_rate: error_rate,
      avg_satisfaction: avg_satisfaction,
      avg_messages_per_conversation: avg_message_count,
      ratings_count: length(ratings)
    }
  end

  defp handle_degraded_agent(%Agent{} = agent, health) do
    Logger.warn(
      "Agent #{agent.name} (#{agent.id}) degraded: " <>
        "status=#{health.status}, satisfaction=#{health.avg_satisfaction}, " <>
        "error_rate=#{health.error_rate}"
    )

    Agents.update_agent_metrics(agent, %{
      satisfaction_score: health.avg_satisfaction
    })

    if health.status == :critical do
      alert_critical(agent, health)
    end

    if agent.total_conversations >= @min_conversations_for_tuning do
      schedule_auto_tune(agent)
    end

    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:agent_health_alert, agent.id, health.status, health}
    )
  end

  defp alert_critical(%Agent{} = agent, health) do
    Logger.error(
      "CRITICAL: Agent #{agent.name} (#{agent.id}) - " <>
        "satisfaction: #{health.avg_satisfaction}, " <>
        "error_rate: #{health.error_rate}"
    )

    agent_with_client = Agents.get_agent_with_client(agent.id)

    if agent_with_client && agent_with_client.client do
      Phoenix.PubSub.broadcast(
        AgentPlatform.PubSub,
        "platform:events",
        {:critical_alert, agent.id, agent_with_client.client.id, health}
      )
    end
  end

  defp schedule_auto_tune(%Agent{} = agent) do
    %{type: "auto_tune", agent_id: agent.id}
    |> __MODULE__.new(schedule_in: 60)
    |> Oban.insert()
  end

  defp auto_tune_agent(%Agent{} = agent) do
    conversations = Agents.list_conversations_for_agent(agent.id, limit: 50)

    low_satisfaction =
      conversations
      |> Enum.filter(fn c ->
        c.satisfaction_rating != nil and c.satisfaction_rating < 3
      end)

    if length(low_satisfaction) > 0 do
      analysis_prompt = """
      Analyze these conversation patterns from a #{agent.type} agent named "#{agent.name}"
      and suggest improvements to the system prompt.

      Current system prompt:
      #{agent.system_prompt}

      Low-satisfaction conversation summaries:
      #{Enum.map_join(Enum.take(low_satisfaction, 5), "\n---\n", fn c ->
        messages = c.messages || []
        Enum.map_join(Enum.take(messages, 6), "\n", fn m -> "#{m["role"]}: #{m["content"]}" end)
      end)}

      Provide an improved system prompt that addresses the patterns causing low satisfaction.
      Return ONLY the new system prompt text, nothing else.
      """

      case ClaudeClient.analyze_conversation(analysis_prompt) do
        {:ok, improved_prompt} ->
          Agents.update_agent(agent, %{
            system_prompt: improved_prompt,
            config:
              Map.put(agent.config || %{}, "last_tuned", DateTime.utc_now() |> DateTime.to_iso8601())
          })

          Logger.info("Auto-tuned system prompt for agent #{agent.name} (#{agent.id})")

        {:error, reason} ->
          Logger.error("Auto-tune failed for agent #{agent.id}: #{inspect(reason)}")
      end
    else
      Logger.info("Agent #{agent.name} has no low-satisfaction conversations to tune from")
    end

    :ok
  end

  defp analyze_satisfaction_trend(%Agent{} = agent) do
    conversations = Agents.list_conversations_for_agent(agent.id, limit: 100)

    ratings =
      conversations
      |> Enum.map(& &1.satisfaction_rating)
      |> Enum.reject(&is_nil/1)

    if length(ratings) >= 10 do
      recent = Enum.take(ratings, 10)
      older = Enum.slice(ratings, 10, 10)

      recent_avg = Enum.sum(recent) / length(recent)

      older_avg =
        case older do
          [] -> recent_avg
          o -> Enum.sum(o) / length(o)
        end

      trend = recent_avg - older_avg

      if trend < -0.5 do
        Logger.warn(
          "Declining satisfaction for agent #{agent.name}: " <>
            "recent=#{Float.round(recent_avg, 2)}, older=#{Float.round(older_avg, 2)}, " <>
            "trend=#{Float.round(trend, 2)}"
        )

        Phoenix.PubSub.broadcast(
          AgentPlatform.PubSub,
          "platform:events",
          {:satisfaction_declining, agent.id, recent_avg, trend}
        )
      end
    end
  end

  defp broadcast_health_status(healthy_count, degraded_count) do
    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:health_check_complete, healthy_count, degraded_count}
    )
  end
end
