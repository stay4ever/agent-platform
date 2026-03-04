import Config

config :agent_platform, AgentPlatform.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "agent_platform_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :agent_platform, AgentPlatformWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_that_is_at_least_64_bytes_long_for_testing_only_do_not_use_in_prod_env",
  server: false

config :agent_platform, Oban, testing: :inline

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true
