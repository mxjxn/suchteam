defmodule SuchteamWeb.AgentChannel do
  use Phoenix.Channel

  def join("agents:" <> team_id, _params, socket) do
    Phoenix.PubSub.subscribe(Suchteam.PubSub, "agents")
    {:ok, assign(socket, :team_id, team_id)}
  end

  def handle_in("create_agent", params, socket) do
    team_id = socket.assigns.team_id
    attrs = Map.merge(params, %{"team_id" => team_id})

    case Suchteam.Orchestrator.create_agent(attrs) do
      {:ok, agent} ->
        {:reply, {:ok, agent}, socket}

      {:error, changeset} ->
        {:reply, {:error, format_errors(changeset)}, socket}
    end
  end

  def handle_in("delegate_task", %{"agent_id" => agent_id, "payload" => payload} = params, socket) do
    opts = [priority: params["priority"]]

    case Suchteam.Orchestrator.delegate_task(agent_id, payload, opts) do
      {:ok, task} ->
        {:reply, {:ok, task}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("terminate_agent", %{"agent_id" => agent_id}, socket) do
    case Suchteam.Orchestrator.terminate_agent(agent_id) do
      {:ok, agent} ->
        {:reply, {:ok, agent}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in("list_agents", _params, socket) do
    team_id = socket.assigns.team_id
    agents = Suchteam.Orchestrator.list_agents(team_id)
    {:reply, {:ok, agents}, socket}
  end

  intercept([
    :created,
    :terminated,
    :status_changed,
    :task_queued,
    :task_completed,
    :heartbeat_timeout
  ])

  def handle_out(
        event,
        %{team_id: team_id} = data,
        %{assigns: %{team_id: socket_team_id}} = socket
      )
      when team_id == socket_team_id do
    push(socket, to_string(event), data)
    {:noreply, socket}
  end

  def handle_out(
        event,
        %{agent: %{team_id: team_id}} = data,
        %{assigns: %{team_id: socket_team_id}} = socket
      )
      when team_id == socket_team_id do
    push(socket, to_string(event), data)
    {:noreply, socket}
  end

  def handle_out(_event, _data, socket) do
    {:noreply, socket}
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key)
      end)
    end)
  end
end
