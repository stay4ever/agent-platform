defmodule AgentPlatform.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :agent_id, references(:agents, on_delete: :delete_all), null: false
      add :visitor_id, :string, null: false
      add :channel, :string, null: false, default: "widget"
      add :status, :string, null: false, default: "active"
      add :messages, {:array, :map}, default: []
      add :satisfaction_rating, :integer
      add :outcome, :string
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:conversations, [:agent_id])
    create index(:conversations, [:visitor_id])
    create index(:conversations, [:status])
    create index(:conversations, [:channel])
    create index(:conversations, [:inserted_at])
    create index(:conversations, [:agent_id, :visitor_id, :status])
  end
end
