defmodule Suchteam.Billing do
  @moduledoc """
  The Billing context for managing subscriptions and usage tracking.
  """

  import Ecto.Query, warn: false
  alias Suchteam.Repo
  alias Suchteam.Billing.{Subscription, UsageRecord}

  ## Subscription functions

  @doc """
  Gets the subscription for an organization.
  """
  def get_subscription(organization_id) do
    Repo.get_by(Subscription, organization_id: organization_id)
  end

  @doc """
  Updates a subscription.
  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Checks if an organization can perform an action based on their subscription limits.
  """
  def can_perform_action?(organization_id, action, current_count \\ nil) do
    subscription = get_subscription(organization_id)
    limits = Subscription.plan_limits(subscription.plan)

    case action do
      :create_agent ->
        case limits.max_agents do
          :unlimited -> true
          max -> current_count < max
        end

      :create_task ->
        case limits.max_tasks_per_day do
          :unlimited -> true
          max -> get_today_task_count(organization_id) < max
        end

      :api_call ->
        case limits.max_api_calls_per_hour do
          :unlimited -> true
          max -> get_hourly_api_calls(organization_id) < max
        end

      _ ->
        false
    end
  end

  ## Usage tracking functions

  @doc """
  Records a usage event for an organization.
  """
  def record_usage(organization_id, metric_type, quantity \\ 1, metadata \\ %{}) do
    %UsageRecord{}
    |> UsageRecord.changeset(%{
      organization_id: organization_id,
      metric_type: metric_type,
      quantity: quantity,
      recorded_at: DateTime.utc_now(),
      metadata: metadata
    })
    |> Repo.insert()
  end

  @doc """
  Gets the task count for today for an organization.
  """
  def get_today_task_count(organization_id) do
    today = DateTime.utc_now() |> DateTime.to_date()

    from(u in UsageRecord,
      where: u.organization_id == ^organization_id,
      where: u.metric_type == "task_count",
      where: fragment("DATE(?)", u.recorded_at) == ^today,
      select: sum(u.quantity)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Gets the API call count for the current hour for an organization.
  """
  def get_hourly_api_calls(organization_id) do
    one_hour_ago = DateTime.utc_now() |> DateTime.add(-3600, :second)

    from(u in UsageRecord,
      where: u.organization_id == ^organization_id,
      where: u.metric_type == "api_calls",
      where: u.recorded_at >= ^one_hour_ago,
      select: sum(u.quantity)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc """
  Gets usage summary for an organization for a date range.
  """
  def get_usage_summary(organization_id, start_date, end_date) do
    from(u in UsageRecord,
      where: u.organization_id == ^organization_id,
      where: u.recorded_at >= ^start_date and u.recorded_at <= ^end_date,
      group_by: u.metric_type,
      select: {u.metric_type, sum(u.quantity)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
