defmodule SuchteamWeb.DashboardLive do
  use SuchteamWeb, :live_view

  alias Suchteam.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "agents")
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "openclaw")

    {:ok, assign(socket, stats: Orchestrator.get_stats(), openclaw_status: :disconnected)}
  end

  @impl true
  def handle_info({:created, _agent}, socket) do
    {:noreply, update(socket, :stats, fn _ -> Orchestrator.get_stats() end)}
  end

  def handle_info({:terminated, _agent}, socket) do
    {:noreply, update(socket, :stats, fn _ -> Orchestrator.get_stats() end)}
  end

  def handle_info(:connected, socket) do
    {:noreply, assign(socket, :openclaw_status, :connected)}
  end

  def handle_info({:disconnected, _}, socket) do
    {:noreply, assign(socket, :openclaw_status, :disconnected)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-8">
      <div class="max-w-7xl mx-auto">
        <h1 class="text-3xl font-bold mb-8">Swarm Orchestrator Dashboard</h1>
        
        <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
          <.stat_card title="Total Agents" value={@stats.total_agents} />
          <.stat_card title="Active" value={@stats.active_agents} color="green" />
          <.stat_card title="Idle" value={@stats.idle_agents} color="yellow" />
          <.stat_card title="Terminated" value={@stats.terminated_agents} color="red" />
        </div>

        <div class="bg-gray-800 rounded-lg p-6 mb-8">
          <div class="flex items-center justify-between">
            <h2 class="text-xl font-semibold">OpenClaw Status</h2>
            <span class={[
              "px-3 py-1 rounded-full text-sm font-medium",
              @openclaw_status == :connected && "bg-green-500/20 text-green-400",
              @openclaw_status == :disconnected && "bg-red-500/20 text-red-400"
            ]}>
              <%= if @openclaw_status == :connected, do: "Connected", else: "Disconnected" %>
            </span>
          </div>
        </div>

        <div class="flex gap-4">
          <.link navigate={~p"/chat"} class="bg-green-600 hover:bg-green-700 px-6 py-3 rounded-lg font-medium">
            Open Chat
          </.link>
          <.link navigate={~p"/agents"} class="bg-blue-600 hover:bg-blue-700 px-6 py-3 rounded-lg font-medium">
            Manage Agents
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr(:title, :string, required: true)
  attr(:value, :integer, required: true)
  attr(:color, :string, default: nil)

  defp stat_card(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-6">
      <p class="text-gray-400 text-sm mb-1"><%= @title %></p>
      <p class={"text-3xl font-bold #{color_class(@color)}"}>
        <%= @value %>
      </p>
    </div>
    """
  end

  defp color_class("green"), do: "text-green-400"
  defp color_class("yellow"), do: "text-yellow-400"
  defp color_class("red"), do: "text-red-400"
  defp color_class(_), do: "text-white"
end
