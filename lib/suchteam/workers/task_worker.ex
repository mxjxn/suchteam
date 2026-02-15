defmodule Suchteam.Workers.TaskWorker do
  use Oban.Worker, queue: :tasks, max_attempts: 3

  require Logger

  alias Suchteam.Agents
  alias Suchteam.Agents.Task
  alias Suchteam.OpenClaw.Client

  @impl true
  def perform(%Oban.Job{args: %{"task_id" => task_id}}) do
    with {:ok, task} <- fetch_task(task_id),
         {:ok, agent} <- fetch_agent(task.agent_id),
         {:ok, _} <- start_task(task),
         {:ok, result} <- execute_task(agent, task) do
      complete_task(task, result)
      broadcast_completion(agent, task, result)
      :ok
    else
      {:error, :not_found} = error ->
        Logger.error("[TaskWorker] Task or agent not found: #{task_id}")
        error

      {:error, reason} = error ->
        Logger.error("[TaskWorker] Task failed: #{inspect(reason)}")
        maybe_fail_task(task_id, reason)
        error
    end
  end

  defp fetch_task(id) do
    case Agents.get_task(id) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  defp fetch_agent(id) do
    case Agents.get_agent(id) do
      nil -> {:error, :not_found}
      agent -> {:ok, agent}
    end
  end

  defp start_task(%Task{} = task) do
    Agents.start_task(task)
  end

  defp execute_task(agent, %Task{payload: payload}) do
    text = Map.get(payload, "text") || Map.get(payload, :text, "")

    if Client.connected?() do
      Client.send_agent_message(text, agent.session_key)
    else
      {:error, :openclaw_not_connected}
    end
  end

  defp complete_task(%Task{} = task, result) do
    Agents.complete_task(task, result)
  end

  defp maybe_fail_task(task_id, reason) do
    case Agents.get_task(task_id) do
      nil -> :ok
      task -> Agents.fail_task(task, inspect(reason))
    end
  end

  defp broadcast_completion(agent, task, result) do
    Phoenix.PubSub.broadcast(
      Suchteam.PubSub,
      "agents",
      {:task_completed,
       %{
         agent: agent,
         task: task,
         result: result
       }}
    )
  end
end
