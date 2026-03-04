import Config

config :agent_platform, AgentPlatform.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agent_platform_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :agent_platform, AgentPlatformWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_that_is_at_least_64_bytes_long_for_development_only_do_not_use_in_prod",
  watchers: []

config :agent_platform, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :agent_platform, Oban, testing: :manual
