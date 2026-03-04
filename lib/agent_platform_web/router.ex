defmodule AgentPlatformWeb.Router do
  use AgentPlatformWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AgentPlatformWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :widget do
    plug :accepts, ["javascript", "json"]
  end

  # --- Browser Routes ---

  scope "/", AgentPlatformWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/clients", DashboardLive, :clients
    live "/agents", DashboardLive, :agents
    live "/conversations", DashboardLive, :conversations
  end

  # --- API Routes ---

  scope "/api", AgentPlatformWeb do
    pipe_through :api

    get "/clients", ApiController, :clients
    get "/metrics", ApiController, :metrics
    get "/agents", ApiController, :agents
    get "/revenue", ApiController, :revenue
    get "/health", ApiController, :health
  end

  # --- Widget Routes ---

  scope "/api", AgentPlatformWeb do
    pipe_through :widget

    get "/agents/:id/widget.js", WidgetController, :show
  end

  # --- Chat Endpoint ---

  scope "/api", AgentPlatformWeb do
    pipe_through :api

    post "/chat/:token", ChatController, :create
  end

  # --- Stripe Webhooks ---

  scope "/api/webhooks", AgentPlatformWeb do
    pipe_through :api

    post "/stripe", WebhookController, :stripe
  end

  # --- Dev Routes ---

  if Application.compile_env(:agent_platform, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: AgentPlatformWeb.Telemetry
    end
  end
end
