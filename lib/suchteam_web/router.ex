defmodule SuchteamWeb.Router do
  use SuchteamWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {SuchteamWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", SuchteamWeb do
    pipe_through(:browser)

    live("/", DashboardLive, :index)
    live("/chat", ChatLive, :index)
  end

  scope "/agents", SuchteamWeb do
    pipe_through(:browser)

    live("/", AgentLive.Index, :index)
    live("/new", AgentLive.Index, :new)
    live("/:id", AgentLive.Show, :show)
  end

  scope "/api", SuchteamWeb.Api do
    pipe_through(:api)

    get("/health", HealthController, :index)
    resources("/agents", AgentController, only: [:index, :show, :create, :delete])
    post("/agents/:id/tasks", AgentController, :delegate_task)
    get("/agents/:id/tasks", AgentController, :tasks)
  end

  if Application.compile_env(:suchteam, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through(:browser)

      live_dashboard("/dashboard", metrics: SuchteamWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
