import Config

config :agent_platform,
  ecto_repos: [AgentPlatform.Repo],
  generators: [timestamp_type: :utc_datetime]

config :agent_platform, AgentPlatformWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: AgentPlatformWeb.ErrorHTML, json: AgentPlatformWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: AgentPlatform.PubSub,
  live_view: [signing_salt: "aG3ntPl4t"]

config :agent_platform, Oban,
  repo: AgentPlatform.Repo,
  queues: [
    onboarding: 2,
    agent_runtime: 5,
    billing: 1,
    reporting: 1,
    monitoring: 2
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       {"0 9 1 * *", AgentPlatform.Workers.ReportingWorker, args: %{type: "monthly_reports"}},
       {"*/5 * * * *", AgentPlatform.Workers.MonitoringWorker, args: %{type: "health_check"}},
       {"0 0 * * *", AgentPlatform.Workers.BillingWorker, args: %{type: "daily_usage_sync"}}
     ]}
  ]

config :stripity_stripe,
  api_key: System.get_env("STRIPE_SECRET_KEY"),
  signing_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

config :ex_aws,
  access_key_id: [{:system, "R2_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "R2_SECRET_ACCESS_KEY"}, :instance_role],
  region: "auto"

config :ex_aws, :s3,
  scheme: "https://",
  host: {:system, "R2_ENDPOINT"},
  region: "auto"

config :agent_platform, :claude,
  api_key: System.get_env("CLAUDE_API_KEY"),
  model: "claude-sonnet-4-20250514",
  max_tokens: 4096

config :agent_platform, :platform,
  name: "AgentPlatform",
  admin_email: "admin@agentplatform.io",
  max_conversations_starter: 1000,
  max_conversations_professional: 5000,
  max_conversations_enterprise: :unlimited,
  overage_rate_cents: 5

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :client_id, :agent_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
