defmodule Suchteam.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:team_id, :binary_id, null: false)
      add(:type, :string, null: false, default: "sub")
      add(:status, :string, null: false, default: "idle")
      add(:session_key, :string, null: false)
      add(:parent_agent_id, references(:agents, type: :binary_id, on_delete: :nilify_all))
      add(:last_ping_at, :utc_datetime)
      add(:metadata, :map, default: %{})

      timestamps(type: :utc_datetime)
    end

    create(index(:agents, [:team_id]))
    create(index(:agents, [:status]))
    create(index(:agents, [:parent_agent_id]))
    create(unique_index(:agents, [:session_key]))
  end
end
