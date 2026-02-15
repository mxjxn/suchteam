defmodule SuchteamWeb.AgentLive.Show do
  use SuchteamWeb, :live_view

  alias Suchteam.Agents
  alias Suchteam.Orchestrator

  @impl true
  def mount(_params, _session, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "agents")
    {:ok, assign(socket, task_input: "")}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    case Agents.get_agent(id) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/agents")}

      agent ->
        tasks = Agents.list_tasks(agent_id: agent.id)
        {:noreply, assign(socket, agent: agent, tasks: tasks)}
    end
  end

  @impl true
  def handle_event("delegate_task", %{"task" => %{"text" => text}}, socket) when text != "" do
    %{agent: agent} = socket.assigns

    case Orchestrator.delegate_task(agent.id, %{"text" => text}) do
      {:ok, _task} ->
        {:noreply, assign(socket, task_input: "", tasks: Agents.list_tasks(agent_id: agent.id))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to delegate: #{inspect(reason)}")}
    end
  end

  def handle_event("delegate_task", _params, socket) do
    {:noreply, put_flash(socket, :error, "Task text cannot be empty")}
  end

  def handle_event("update_task_input", %{"task" => %{"text" => text}}, socket) do
    {:noreply, assign(socket, :task_input, text)}
  end

  def handle_event("terminate", _params, socket) do
    %{agent: agent} = socket.assigns

    case Orchestrator.terminate_agent(agent.id) do
      {:ok, _} ->
        {:noreply, push_navigate(socket, to: ~p"/agents")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to terminate: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info(
        {:task_completed, %{agent: %{id: id}}},
        %{assigns: %{agent: %{id: current_id}}} = socket
      )
      when id == current_id do
    {:noreply, assign(socket, tasks: Agents.list_tasks(agent_id: id))}
  end

  def handle_info({:status_changed, %{id: id}}, %{assigns: %{agent: %{id: current_id}}} = socket)
      when id == current_id do
    {:noreply, assign(socket, agent: Agents.get_agent!(id))}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white p-8">
      <div class="max-w-7xl mx-auto">
        <div class="flex items-center gap-4 mb-8">
          <.link navigate={~p"/agents"} class="text-gray-400 hover:text-white">
            <.icon name="hero-arrow-left" class="w-5 h-5" />
          </.link>
          <h1 class="text-3xl font-bold">Agent <%= short_id(@agent.id) %></h1>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
          <div class="lg:col-span-1 space-y-6">
            <div class="bg-gray-800 rounded-lg p-6">
              <h2 class="text-lg font-semibold mb-4">Details</h2>
              <div class="space-y-3 text-sm">
                <div>
                  <span class="text-gray-400">Type:</span>
                  <span class={[
                    "ml-2 px-2 py-1 rounded text-xs font-medium uppercase",
                    @agent.type == "master" && "bg-purple-500/20 text-purple-400",
                    @agent.type == "sub" && "bg-indigo-500/20 text-indigo-400"
                  ]}>
                    <%= @agent.type %>
                  </span>
                </div>
                <div>
                  <span class="text-gray-400">Status:</span>
                  <span class={[
                    "ml-2 px-2 py-1 rounded text-xs font-medium uppercase",
                    @agent.status == "active" && "bg-green-500/20 text-green-400",
                    @agent.status == "idle" && "bg-yellow-500/20 text-yellow-400",
                    @agent.status == "terminated" && "bg-red-500/20 text-red-400"
                  ]}>
                    <%= @agent.status %>
                  </span>
                </div>
                <div>
                  <span class="text-gray-400">Session Key:</span>
                  <span class="ml-2 font-mono text-xs"><%= @agent.session_key %></span>
                </div>
                <div>
                  <span class="text-gray-400">Created:</span>
                  <span class="ml-2"><%= format_datetime(@agent.inserted_at) %></span>
                </div>
                <div>
                  <span class="text-gray-400">Last Ping:</span>
                  <span class="ml-2"><%= format_datetime(@agent.last_ping_at) %></span>
                </div>
              </div>

              <div :if={@agent.status != "terminated"} class="mt-6">
                <button
                  phx-click="terminate"
                  class="w-full bg-red-600 hover:bg-red-700 px-4 py-2 rounded-lg font-medium"
                >
                  Terminate Agent
                </button>
              </div>
            </div>

            <div :if={@agent.status != "terminated"} class="bg-gray-800 rounded-lg p-6">
              <h2 class="text-lg font-semibold mb-4">Delegate Task</h2>
              <form phx-submit="delegate_task" class="space-y-4">
                <div>
                  <textarea
                    name="task[text]"
                    rows="3"
                    class="w-full bg-gray-700 rounded-lg p-3 text-white border border-gray-600 focus:border-blue-500 focus:outline-none"
                    placeholder="Enter task description..."
                  ><%= @task_input %></textarea>
                </div>
                <button
                  type="submit"
                  class="w-full bg-blue-600 hover:bg-blue-700 px-4 py-2 rounded-lg font-medium"
                >
                  Send Task
                </button>
              </form>
            </div>
          </div>

          <div class="lg:col-span-2">
            <div class="bg-gray-800 rounded-lg p-6">
              <h2 class="text-lg font-semibold mb-4">Task History</h2>
              <div :if={Enum.empty?(@tasks)} class="text-center text-gray-400 py-8">
                No tasks yet
              </div>
              <div :if={@tasks != []} class="space-y-4">
                <div :for={task <- @tasks} class="bg-gray-700/50 rounded-lg p-4">
                  <div class="flex items-center justify-between mb-2">
                    <span class={[
                      "px-2 py-1 rounded text-xs font-medium uppercase",
                      task.status == "completed" && "bg-green-500/20 text-green-400",
                      task.status == "running" && "bg-blue-500/20 text-blue-400",
                      task.status == "pending" && "bg-yellow-500/20 text-yellow-400",
                      task.status == "failed" && "bg-red-500/20 text-red-400"
                    ]}>
                      <%= task.status %>
                    </span>
                    <span class="text-xs text-gray-400">
                      <%= format_datetime(task.inserted_at) %>
                    </span>
                  </div>
                  <p class="text-sm font-mono bg-gray-900/50 p-2 rounded mb-2">
                    <%= task.payload["text"] %>
                  </p>
                  <div :if={task.result} class="text-sm text-gray-300">
                    <span class="text-gray-400">Result:</span>
                    <pre class="mt-1 bg-gray-900/50 p-2 rounded overflow-auto max-h-40"><%= Jason.encode!(task.result, pretty: true) %></pre>
                  </div>
                  <div :if={task.error} class="text-sm text-red-400">
                    <span class="text-gray-400">Error:</span> <%= task.error %>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0..7)
  defp short_id(_), do: "-"

  defp format_datetime(nil), do: "Never"
  defp format_datetime(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
end
