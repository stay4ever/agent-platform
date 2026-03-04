defmodule AgentPlatformWeb.CacheBodyReader do
  @moduledoc """
  Caches raw request body for Stripe webhook signature verification.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    conn = Plug.Conn.put_private(conn, :raw_body, body)
    {:ok, body, conn}
  end
end
