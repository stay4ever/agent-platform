defmodule AgentPlatformWeb.ErrorHTML do
  @moduledoc """
  Error HTML pages for AgentPlatform.
  """

  use AgentPlatformWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
