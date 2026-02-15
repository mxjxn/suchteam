defmodule SuchteamWeb.UserSocket do
  use Phoenix.Socket

  channel("agents:*", SuchteamWeb.AgentChannel)
  channel("orchestrator", SuchteamWeb.OrchestratorChannel)

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
