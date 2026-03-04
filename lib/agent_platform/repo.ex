defmodule AgentPlatform.Repo do
  use Ecto.Repo,
    otp_app: :agent_platform,
    adapter: Ecto.Adapters.Postgres
end
