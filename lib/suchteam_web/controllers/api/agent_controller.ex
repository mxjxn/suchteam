defmodule SuchteamWeb.Api.AgentController do
  use SuchteamWeb, :controller

  alias Suchteam.Agents
  alias Suchteam.Orchestrator

  def index(conn, params) do
    opts = []
    opts = if params["team_id"], do: Keyword.put(opts, :team_id, params["team_id"]), else: opts
    opts = if params["status"], do: Keyword.put(opts, :status, params["status"]), else: opts

    agents = Agents.list_agents(opts)
    json(conn, %{success: true, agents: agents})
  end

  def show(conn, %{"id" => id}) do
    case Agents.get_agent(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})

      agent ->
        json(conn, %{success: true, agent: agent})
    end
  end

  def create(conn, params) do
    attrs = %{
      team_id: params["team_id"],
      type: params["type"] || "sub",
      parent_agent_id: params["parent_agent_id"],
      metadata: params["metadata"]
    }

    case Orchestrator.create_agent(attrs) do
      {:ok, agent} ->
        conn
        |> put_status(:created)
        |> json(%{success: true, agent: agent})

      {:error, changeset} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, errors: format_errors(changeset)})
    end
  end

  def delete(conn, %{"id" => id}) do
    case Orchestrator.terminate_agent(id) do
      {:ok, agent} ->
        json(conn, %{success: true, agent: agent})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  def delegate_task(conn, %{"id" => agent_id, "task" => task_text} = params) do
    payload = %{"text" => task_text}
    opts = [priority: params["priority"]]

    case Orchestrator.delegate_task(agent_id, payload, opts) do
      {:ok, task} ->
        json(conn, %{success: true, task: task})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})

      {:error, :agent_terminated} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: "Agent is terminated"})

      {:error, reason} ->
        conn
        |> put_status(:bad_request)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  def tasks(conn, %{"id" => agent_id}) do
    tasks = Agents.list_tasks(agent_id: agent_id)
    json(conn, %{success: true, tasks: tasks})
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key)
      end)
    end)
  end
end
