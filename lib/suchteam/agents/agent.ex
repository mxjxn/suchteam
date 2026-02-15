defmodule Suchteam.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agents" do
    field(:team_id, :binary_id)
    field(:type, :string, default: "sub")
    field(:status, :string, default: "idle")
    field(:session_key, :string)
    field(:last_ping_at, :utc_datetime)
    field(:metadata, :map, default: %{})

    belongs_to(:parent_agent, __MODULE__)

    timestamps(type: :utc_datetime)
  end

  @types ~w(master sub)
  @statuses ~w(idle active terminated)

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [
      :team_id,
      :type,
      :status,
      :session_key,
      :parent_agent_id,
      :last_ping_at,
      :metadata
    ])
    |> validate_required([:team_id, :session_key])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:session_key)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> Map.put(:session_key, generate_session_key())
    |> changeset(attrs)
  end

  defp generate_session_key do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
