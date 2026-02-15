defmodule Suchteam.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      add(:slug, :string, null: false)
      add(:settings, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:teams, [:slug]))
  end
end
