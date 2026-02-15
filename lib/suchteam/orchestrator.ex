defmodule Suchteam.Orchestrator do
  use GenServer
  require Logger

  alias Suchteam.Agents
  alias Suchteam.Agents.Agent

  @heartbeat_interval 30_000
  @heartbeat_timeout 90_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def create_agent(attrs) do
    GenServer.call(__MODULE__, {:create_agent, attrs})
  end

  def get_agent(id) do
    GenServer.call(__MODULE__, {:get_agent, id})
  end

  def list_agents(team_id \\ nil) do
    GenServer.call(__MODULE__, {:list_agents, team_id})
  end

  def delegate_task(agent_id, payload, opts \\ []) do
    GenServer.call(__MODULE__, {:delegate_task, agent_id, payload, opts})
  end

  def terminate_agent(agent_id) do
    GenServer.call(__MODULE__, {:terminate_agent, agent_id})
  end

  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @impl true
  def init(_opts) do
    Logger.info("[Orchestrator] Starting...")

    Phoenix.PubSub.subscribe(Suchteam.PubSub, "openclaw")

    schedule_heartbeat_check()

    state = %{
      agents: %{},
      tasks: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_agent, attrs}, _from, state) do
    case Agents.create_agent(attrs) do
      {:ok, agent} ->
        broadcast_agent_event(:created, agent)
        agents = Map.put(state.agents, agent.id, agent)
        {:reply, {:ok, agent}, %{state | agents: agents}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get_agent, id}, _from, state) do
    case Map.get(state.agents, id) || Agents.get_agent(id) do
      nil -> {:reply, {:error, :not_found}, state}
      agent -> {:reply, {:ok, agent}, state}
    end
  end

  def handle_call({:list_agents, team_id}, _from, state) do
    agents =
      if team_id do
        state.agents
        |> Map.values()
        |> Enum.filter(&(&1.team_id == team_id))
      else
        Map.values(state.agents)
      end

    {:reply, agents, state}
  end

  def handle_call({:delegate_task, agent_id, payload, opts}, _from, state) do
    with {:ok, agent} <- get_or_fetch_agent(agent_id, state),
         :ok <- validate_agent_available(agent) do
      task_attrs = %{
        agent_id: agent.id,
        team_id: agent.team_id,
        payload: payload,
        priority: opts[:priority] || 5
      }

      case Agents.create_task(task_attrs) do
        {:ok, task} ->
          Suchteam.Workers.TaskWorker.new(%{task_id: task.id})
          |> Oban.insert()

          broadcast_agent_event(:task_queued, %{agent: agent, task: task})
          tasks = Map.put(state.tasks, task.id, task)
          {:reply, {:ok, task}, %{state | tasks: tasks}}

        {:error, _} = error ->
          {:reply, error, state}
      end
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:terminate_agent, agent_id}, _from, state) do
    case get_or_fetch_agent(agent_id, state) do
      {:ok, agent} ->
        {:ok, updated} = Agents.update_agent_status(agent, "terminated")
        broadcast_agent_event(:terminated, updated)
        agents = Map.put(state.agents, agent_id, updated)
        {:reply, {:ok, updated}, %{state | agents: agents}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    stats = %{
      total_agents: map_size(state.agents),
      active_agents: count_by_status(state.agents, "active"),
      idle_agents: count_by_status(state.agents, "idle"),
      terminated_agents: count_by_status(state.agents, "terminated"),
      total_tasks: map_size(state.tasks)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info(:check_heartbeats, state) do
    now = DateTime.utc_now()

    timed_out =
      state.agents
      |> Enum.filter(fn {_id, agent} ->
        agent.status == "active" and
          agent.last_ping_at and
          DateTime.diff(now, agent.last_ping_at, :millisecond) > @heartbeat_timeout
      end)

    new_agents =
      Enum.reduce(timed_out, state.agents, fn {_id, agent}, acc ->
        {:ok, updated} = Agents.update_agent_status(agent, "terminated")
        broadcast_agent_event(:heartbeat_timeout, updated)
        Map.put(acc, agent.id, updated)
      end)

    schedule_heartbeat_check()
    {:noreply, %{state | agents: new_agents}}
  end

  def handle_info({:event, %{event: "agent_status", data: data}}, state) do
    case Agents.get_agent_by_session_key(data["sessionKey"]) do
      nil ->
        {:noreply, state}

      agent ->
        {:ok, updated} =
          Agents.update_agent(agent, %{
            status: data["status"],
            last_ping_at: DateTime.utc_now()
          })

        agents = Map.put(state.agents, agent.id, updated)
        broadcast_agent_event(:status_changed, updated)
        {:noreply, %{state | agents: agents}}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp get_or_fetch_agent(id, state) do
    case Map.get(state.agents, id) do
      nil ->
        case Agents.get_agent(id) do
          nil -> {:error, :not_found}
          agent -> {:ok, agent}
        end

      agent ->
        {:ok, agent}
    end
  end

  defp validate_agent_available(%Agent{status: "terminated"}), do: {:error, :agent_terminated}
  defp validate_agent_available(%Agent{}), do: :ok

  defp count_by_status(agents, status) do
    agents
    |> Map.values()
    |> Enum.count(&(&1.status == status))
  end

  defp schedule_heartbeat_check do
    Process.send_after(self(), :check_heartbeats, @heartbeat_interval)
  end

  defp broadcast_agent_event(event, data) do
    Phoenix.PubSub.broadcast(Suchteam.PubSub, "agents", {event, data})
  end
end
