defmodule AgentPlatform.Application do
  @moduledoc """
  OTP Application for AgentPlatform.

  Supervision tree includes:
  - Ecto Repo for database access
  - PubSub for real-time broadcasting
  - Finch HTTP client pool
  - Oban job processing
  - DynamicSupervisor for per-client agent processes
  - Registry for tracking live agent processes
  - Orchestrator GenServer for platform-wide coordination
  - Phoenix Endpoint
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AgentPlatformWeb.Telemetry,
      AgentPlatform.Repo,
      {DNSCluster, query: Application.get_env(:agent_platform, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: AgentPlatform.PubSub},
      {Finch, name: AgentPlatform.Finch},
      {Oban, Application.fetch_env!(:agent_platform, Oban)},
      {Registry, keys: :unique, name: AgentPlatform.AgentRegistry},
      {DynamicSupervisor, name: AgentPlatform.AgentSupervisor, strategy: :one_for_one},
      AgentPlatform.Orchestrator,
      AgentPlatformWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: AgentPlatform.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AgentPlatformWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
