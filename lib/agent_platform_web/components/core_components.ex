defmodule AgentPlatformWeb.CoreComponents do
  @moduledoc """
  Provides core UI components for the AgentPlatform application.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :id, :string, default: "flash-group"
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id={@id}>
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], required: true
  attr :title, :string, default: nil
  attr :rest, :global

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      class={"phx-flash phx-flash-#{@kind}"}
      role="alert"
      {@rest}
    >
      <p :if={@title}><strong><%= @title %></strong></p>
      <p><%= msg %></p>
      <button type="button" class="phx-flash-close" aria-label="close" phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "##{@id}")}>
        x
      </button>
    </div>
    """
  end
end
