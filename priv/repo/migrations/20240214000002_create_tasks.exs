defmodule Suchteam.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:agent_id, references(:agents, type: :binary_id, on_delete: :delete_all), null: false)
      add(:team_id, :binary_id, null: false)
      add(:status, :string, null: false, default: "pending")
      add(:priority, :integer, null: false, default: 5)
      add(:payload, :map, null: false)
      add(:result, :map)
      add(:error, :text)
      add(:started_at, :utc_datetime)
      add(:completed_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:tasks, [:agent_id]))
    create(index(:tasks, [:team_id]))
    create(index(:tasks, [:status]))
    create(index(:tasks, [:priority]))
  end
end
