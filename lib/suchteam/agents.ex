defmodule Suchteam.Agents do
  import Ecto.Query, warn: false
  alias Suchteam.Repo
  alias Suchteam.Agents.{Agent, Task, Team}

  def list_agents(opts \\ []) do
    Agent
    |> maybe_filter_by_team(opts[:team_id])
    |> maybe_filter_by_status(opts[:status])
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(Agent, id)
  def get_agent(id), do: Repo.get(Agent, id)

  def get_agent_by_session_key(session_key) do
    Repo.get_by(Agent, session_key: session_key)
  end

  def create_agent(attrs \\ %{}) do
    Agent.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  def update_agent_status(%Agent{} = agent, status) do
    attrs = %{status: status}

    attrs =
      if status == "active", do: Map.put(attrs, :last_ping_at, DateTime.utc_now()), else: attrs

    update_agent(agent, attrs)
  end

  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  def change_agent(%Agent{} = agent, attrs \\ %{}) do
    Agent.changeset(agent, attrs)
  end

  defp maybe_filter_by_team(query, nil), do: query
  defp maybe_filter_by_team(query, team_id), do: where(query, [a], a.team_id == ^team_id)

  defp maybe_filter_by_status(query, nil), do: query
  defp maybe_filter_by_status(query, status), do: where(query, [a], a.status == ^status)

  defp maybe_filter_tasks_by_agent(query, nil), do: query

  defp maybe_filter_tasks_by_agent(query, agent_id),
    do: where(query, [t], t.agent_id == ^agent_id)

  defp maybe_filter_tasks_by_status(query, nil), do: query
  defp maybe_filter_tasks_by_status(query, status), do: where(query, [t], t.status == ^status)

  def list_tasks(opts \\ []) do
    Task
    |> maybe_filter_tasks_by_agent(opts[:agent_id])
    |> maybe_filter_tasks_by_status(opts[:status])
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(Task, id)
  def get_task(id), do: Repo.get(Task, id)

  def create_task(attrs \\ %{}) do
    Task.create_changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  def start_task(%Task{} = task) do
    update_task(task, %{status: "running", started_at: DateTime.utc_now()})
  end

  def complete_task(%Task{} = task, result) do
    update_task(task, %{
      status: "completed",
      result: result,
      completed_at: DateTime.utc_now()
    })
  end

  def fail_task(%Task{} = task, error) do
    update_task(task, %{
      status: "failed",
      error: error,
      completed_at: DateTime.utc_now()
    })
  end

  def list_teams do
    Repo.all(Team)
  end

  def get_team!(id), do: Repo.get!(Team, id)
  def get_team(id), do: Repo.get(Team, id)

  def create_team(attrs \\ %{}) do
    %Team{}
    |> Team.changeset(attrs)
    |> Repo.insert()
  end
end
