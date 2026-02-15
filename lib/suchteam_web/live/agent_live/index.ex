defmodule SuchteamWeb.AgentLive.Index do
  use SuchteamWeb, :live_view

  alias Suchteam.Agents
  alias Suchteam.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "agents")

    {:ok, assign(socket, agents: load_agents(), creating: false)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params), do: socket
  defp apply_action(socket, :new, _params), do: assign(socket, :creating, true)

  @impl true
  def handle_event("create_agent", %{"type" => type}, socket) do
    team_id = generate_team_id()

    case Orchestrator.create_agent(%{team_id: team_id, type: type}) do
      {:ok, _agent} ->
        {:noreply, assign(socket, agents: load_agents(), creating: false)}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, format_errors(changeset))}
    end
  end

  def handle_event("terminate_agent", %{"id" => agent_id}, socket) do
    case Orchestrator.terminate_agent(agent_id) do
      {:ok, _} ->
        {:noreply, assign(socket, agents: load_agents())}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to terminate: #{inspect(reason)}")}
    end
  end

  def handle_event("cancel_create", _, socket) do
    {:noreply, assign(socket, :creating, false)}
  end

  @impl true
  def handle_info({:created, _agent}, socket) do
    {:noreply, assign(socket, agents: load_agents())}
  end

  def handle_info({:terminated, _agent}, socket) do
    {:noreply, assign(socket, agents: load_agents())}
  end

  def handle_info({:status_changed, _agent}, socket) do
    {:noreply, assign(socket, agents: load_agents())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-8">
      <div class="max-w-7xl mx-auto">
        <div class="flex items-center justify-between mb-8">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/"} class="text-gray-400 hover:text-white">
              <.icon name="hero-arrow-left" class="w-5 h-5" />
            </.link>
            <h1 class="text-3xl font-bold">Agents</h1>
          </div>

          <button
            phx-click="show_create"
            class="bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded-lg font-medium"
          >
            Create Agent
          </button>
        </div>

        <div :if={@creating} class="bg-gray-800 rounded-lg p-6 mb-8">
          <h2 class="text-xl font-semibold mb-4">Create New Agent</h2>
          <div class="flex gap-4">
            <button
              phx-click="create_agent"
              phx-value-type="master"
              class="bg-purple-600 hover:bg-purple-700 px-4 py-2 rounded-lg"
            >
              Master Agent
            </button>
            <button
              phx-click="create_agent"
              phx-value-type="sub"
              class="bg-indigo-600 hover:bg-indigo-700 px-4 py-2 rounded-lg"
            >
              Sub Agent
            </button>
            <button
              phx-click="cancel_create"
              class="bg-gray-600 hover:bg-gray-700 px-4 py-2 rounded-lg"
            >
              Cancel
            </button>
          </div>
        </div>

        <div class="bg-gray-800 rounded-lg overflow-hidden">
          <table class="w-full">
            <thead>
              <tr class="border-b border-gray-700">
                <th class="text-left p-4 text-gray-400 font-medium">ID</th>
                <th class="text-left p-4 text-gray-400 font-medium">Type</th>
                <th class="text-left p-4 text-gray-400 font-medium">Status</th>
                <th class="text-left p-4 text-gray-400 font-medium">Session Key</th>
                <th class="text-left p-4 text-gray-400 font-medium">Last Ping</th>
                <th class="text-left p-4 text-gray-400 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={agent <- @agents} class="border-b border-gray-700/50 hover:bg-gray-700/30">
                <td class="p-4 font-mono text-sm"><%= short_id(agent.id) %></td>
                <td class="p-4">
                  <span class={[
                    "px-2 py-1 rounded text-xs font-medium uppercase",
                    agent.type == "master" && "bg-purple-500/20 text-purple-400",
                    agent.type == "sub" && "bg-indigo-500/20 text-indigo-400"
                  ]}>
                    <%= agent.type %>
                  </span>
                </td>
                <td class="p-4">
                  <span class={[
                    "px-2 py-1 rounded text-xs font-medium uppercase",
                    agent.status == "active" && "bg-green-500/20 text-green-400",
                    agent.status == "idle" && "bg-yellow-500/20 text-yellow-400",
                    agent.status == "terminated" && "bg-red-500/20 text-red-400"
                  ]}>
                    <%= agent.status %>
                  </span>
                </td>
                <td class="p-4 font-mono text-sm text-gray-400"><%= agent.session_key %></td>
                <td class="p-4 text-sm text-gray-400">
                  <%= format_datetime(agent.last_ping_at) %>
                </td>
                <td class="p-4">
                  <div class="flex gap-2">
                    <.link
                      navigate={~p"/agents/#{agent.id}"}
                      class="text-blue-400 hover:text-blue-300 text-sm"
                    >
                      View
                    </.link>
                    <button
                      :if={agent.status != "terminated"}
                      phx-click="terminate_agent"
                      phx-value-id={agent.id}
                      class="text-red-400 hover:text-red-300 text-sm"
                    >
                      Terminate
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>

          <div :if={Enum.empty?(@agents)} class="p-8 text-center text-gray-400">
            No agents yet. Create one to get started.
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp load_agents, do: Agents.list_agents()

  defp short_id(id) when is_binary(id), do: String.slice(id, 0..7)
  defp short_id(_), do: "-"

  defp format_datetime(nil), do: "Never"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")

  defp generate_team_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key)
      end)
    end)
    |> inspect()
  end
end
