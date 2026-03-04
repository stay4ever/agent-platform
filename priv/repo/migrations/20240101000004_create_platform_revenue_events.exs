defmodule AgentPlatform.Repo.Migrations.CreatePlatformRevenueEvents do
  use Ecto.Migration

  def change do
    create table(:platform_revenue_events) do
      add :client_id, references(:clients, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :amount_cents, :integer, null: false
      add :stripe_event_id, :string
      add :metadata, :map, default: %{}

      timestamps()
    end

    create index(:platform_revenue_events, [:client_id])
    create index(:platform_revenue_events, [:type])
    create index(:platform_revenue_events, [:inserted_at])
    create unique_index(:platform_revenue_events, [:stripe_event_id])
  end
end
