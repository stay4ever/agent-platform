import Config

if System.get_env("PHX_SERVER") do
  config :agent_platform, AgentPlatformWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :agent_platform, AgentPlatform.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "agent-platform.fly.dev"
  port = String.to_integer(System.get_env("PORT") || "4003")

  config :agent_platform, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :agent_platform, AgentPlatformWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  config :stripity_stripe,
    api_key: System.get_env("STRIPE_SECRET_KEY"),
    signing_secret: System.get_env("STRIPE_WEBHOOK_SECRET")

  config :ex_aws,
    access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
    secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY"),
    region: "auto"

  config :ex_aws, :s3,
    scheme: "https://",
    host: System.get_env("R2_ENDPOINT"),
    region: "auto"

  config :agent_platform, :claude,
    api_key: System.get_env("CLAUDE_API_KEY"),
    model: System.get_env("CLAUDE_MODEL") || "claude-sonnet-4-20250514",
    max_tokens: String.to_integer(System.get_env("CLAUDE_MAX_TOKENS") || "4096")

  config :agent_platform, :platform,
    admin_email: System.get_env("ADMIN_EMAIL") || "admin@agentplatform.io"
end
