defmodule AgentPlatform.Repo.Migrations.CreateAgents do
  use Ecto.Migration

  def change do
    create table(:agents) do
      add :client_id, references(:clients, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :type, :string, null: false
      add :status, :string, null: false, default: "configuring"
      add :system_prompt, :text
      add :knowledge_base_key, :string
      add :total_conversations, :integer, null: false, default: 0
      add :total_messages, :integer, null: false, default: 0
      add :satisfaction_score, :float, null: false, default: 0.0
      add :conversations_today, :integer, null: false, default: 0
      add :config, :map, default: %{}
      add :webhook_url, :string
      add :widget_token, :string

      timestamps()
    end

    create index(:agents, [:client_id])
    create index(:agents, [:status])
    create index(:agents, [:type])
    create unique_index(:agents, [:widget_token])
  end
end
