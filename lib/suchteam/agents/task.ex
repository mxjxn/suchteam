defmodule Suchteam.Agents.Task do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasks" do
    field(:team_id, :binary_id)
    field(:status, :string, default: "pending")
    field(:priority, :integer, default: 5)
    field(:payload, :map)
    field(:result, :map)
    field(:error, :string)
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)

    belongs_to(:agent, Suchteam.Agents.Agent)

    timestamps(type: :utc_datetime)
  end

  @statuses ~w(pending running completed failed cancelled)
  @priorities 1..10

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :agent_id,
      :team_id,
      :status,
      :priority,
      :payload,
      :result,
      :error,
      :started_at,
      :completed_at
    ])
    |> validate_required([:agent_id, :team_id, :payload])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
    |> foreign_key_constraint(:agent_id)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end
end
