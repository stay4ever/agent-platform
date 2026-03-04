defmodule AgentPlatformWeb.WidgetController do
  @moduledoc """
  Serves the embeddable widget JavaScript for client websites.
  """

  use AgentPlatformWeb, :controller

  alias AgentPlatform.{Agents, Widget}

  def show(conn, %{"id" => id}) do
    case Agents.get_agent(id) do
      nil ->
        conn
        |> put_status(404)
        |> text("// Agent not found")

      agent ->
        widget_js = Widget.generate_widget_js(agent)

        conn
        |> put_resp_content_type("application/javascript")
        |> put_resp_header("cache-control", "public, max-age=300")
        |> put_resp_header("access-control-allow-origin", "*")
        |> text(widget_js)
    end
  end
end
