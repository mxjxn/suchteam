defmodule Suchteam.OpenClaw.Supervisor do
  use Supervisor
  require Logger

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:suchteam, :open_claw, [])
    enabled = Keyword.get(config, :enabled, true)

    if enabled == false do
      Logger.info("[OpenClaw] Disabled via config, skipping supervisor")
      :ignore
    else
      children = [
        {Suchteam.OpenClaw.Client, []},
        {Suchteam.OpenClaw.HTTP, []}
      ]

      Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 60)
    end
  end
end
