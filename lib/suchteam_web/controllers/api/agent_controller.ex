defmodule SuchteamWeb.Api.AgentController do
  use SuchteamWeb, :controller

  alias Suchteam.Agents
  alias Suchteam.Orchestrator
  alias Suchteam.Billing

  # Filter agents to only those belonging to the authenticated organization
  def index(conn, params) do
    organization = conn.assigns[:current_organization]
    
    # Get teams belonging to this organization
    teams = Agents.list_teams()
    |> Enum.filter(fn team -> team.organization_id == organization.id end)
    team_ids = Enum.map(teams, & &1.id)
    
    # Build filters
    opts = []
    opts = if params["team_id"] && params["team_id"] in team_ids do
      Keyword.put(opts, :team_id, params["team_id"])
    else
      opts
    end
    opts = if params["status"], do: Keyword.put(opts, :status, params["status"]), else: opts

    agents = Agents.list_agents(opts)
    # Further filter by organization's teams
    |> Enum.filter(fn agent -> agent.team_id in team_ids end)
    
    json(conn, %{success: true, agents: agents, count: length(agents)})
  end

  def show(conn, %{"id" => id}) do
    organization = conn.assigns[:current_organization]
    
    case Agents.get_agent(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})

      agent ->
        # Verify agent belongs to organization
        team = Agents.get_team(agent.team_id)
        if team && team.organization_id == organization.id do
          json(conn, %{success: true, agent: agent})
        else
          conn
          |> put_status(:forbidden)
          |> json(%{success: false, error: "Access denied"})
        end
    end
  end

  def create(conn, params) do
    organization = conn.assigns[:current_organization]
    
    # Check subscription limits
    current_agent_count = get_organization_agent_count(organization.id)
    
    cond do
      !Billing.can_perform_action?(organization.id, :create_agent, current_agent_count) ->
        limits = Billing.Subscription.plan_limits(organization.subscription.plan)
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error: "Agent limit exceeded",
          plan: organization.subscription.plan,
          limits: limits
        })
      
      # Ensure team_id belongs to organization
      true ->
        team_id = params["team_id"]
        team = team_id && Agents.get_team(team_id)
        
        if team && team.organization_id == organization.id do
          attrs = %{
            team_id: team_id,
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
        else
          conn
          |> put_status(:bad_request)
          |> json(%{success: false, error: "Invalid team_id or team does not belong to your organization"})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    organization = conn.assigns[:current_organization]
    
    # Verify agent belongs to organization
    case Agents.get_agent(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})
        
      agent ->
        team = Agents.get_team(agent.team_id)
        
        if team && team.organization_id == organization.id do
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
        else
          conn
          |> put_status(:forbidden)
          |> json(%{success: false, error: "Access denied"})
        end
    end
  end

  def delegate_task(conn, %{"id" => agent_id, "task" => task_text} = params) do
    organization = conn.assigns[:current_organization]
    
    # Verify agent belongs to organization
    case Agents.get_agent(agent_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})
        
      agent ->
        team = Agents.get_team(agent.team_id)
        
        cond do
          !team || team.organization_id != organization.id ->
            conn
            |> put_status(:forbidden)
            |> json(%{success: false, error: "Access denied"})
          
          # Check task creation limits
          !Billing.can_perform_action?(organization.id, :create_task) ->
            limits = Billing.Subscription.plan_limits(organization.subscription.plan)
            conn
            |> put_status(:forbidden)
            |> json(%{
              success: false,
              error: "Daily task limit exceeded",
              plan: organization.subscription.plan,
              limits: limits
            })
          
          true ->
            payload = %{"text" => task_text}
            opts = [priority: params["priority"]]

            case Orchestrator.delegate_task(agent_id, payload, opts) do
              {:ok, task} ->
                # Record usage
                Billing.record_usage(organization.id, "task_count", 1, %{
                  agent_id: agent_id,
                  team_id: agent.team_id
                })
                
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
    end
  end

  def tasks(conn, %{"id" => agent_id}) do
    organization = conn.assigns[:current_organization]
    
    # Verify agent belongs to organization
    case Agents.get_agent(agent_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Agent not found"})
        
      agent ->
        team = Agents.get_team(agent.team_id)
        
        if team && team.organization_id == organization.id do
          tasks = Agents.list_tasks(agent_id: agent_id)
          json(conn, %{success: true, tasks: tasks, count: length(tasks)})
        else
          conn
          |> put_status(:forbidden)
          |> json(%{success: false, error: "Access denied"})
        end
    end
  end

  defp get_organization_agent_count(organization_id) do
    teams = Agents.list_teams()
    |> Enum.filter(fn team -> team.organization_id == organization_id end)
    team_ids = Enum.map(teams, & &1.id)
    
    Agents.list_agents()
    |> Enum.filter(fn agent -> agent.team_id in team_ids end)
    |> length()
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key)
      end)
    end)
  end
end
