defmodule AgentPlatformWeb.ErrorJSON do
  @moduledoc """
  Error JSON responses for AgentPlatform API.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
