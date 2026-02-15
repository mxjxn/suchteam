defmodule SuchteamWeb.OrchestratorChannel do
  use Phoenix.Channel

  def join("orchestrator", _params, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "openclaw")
    {:ok, socket}
  end

  def handle_in("get_stats", _params, socket) do
    stats = Suchteam.Orchestrator.get_stats()
    {:reply, {:ok, stats}, socket}
  end

  def handle_in("list_all_agents", _params, socket) do
    agents = Suchteam.Orchestrator.list_agents()
    {:reply, {:ok, agents}, socket}
  end

  intercept([:connected, :disconnected, {:event, :any}])

  def handle_out(:connected, _data, socket) do
    push(socket, "openclaw:connected", %{})
    {:noreply, socket}
  end

  def handle_out(:disconnected, reason, socket) do
    push(socket, "openclaw:disconnected", %{reason: inspect(reason)})
    {:noreply, socket}
  end

  def handle_out({:event, payload}, _data, socket) do
    push(socket, "openclaw:event", payload)
    {:noreply, socket}
  end

  def handle_out(_event, _data, socket) do
    {:noreply, socket}
  end
end
