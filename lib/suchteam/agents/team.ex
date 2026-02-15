defmodule Suchteam.Agents.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "teams" do
    field(:name, :string)
    field(:slug, :string)
    field(:settings, :map, default: %{})

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :slug, :settings])
    |> validate_required([:name, :slug])
    |> unique_constraint(:slug)
  end
end
