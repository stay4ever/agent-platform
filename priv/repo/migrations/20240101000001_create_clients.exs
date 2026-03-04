defmodule AgentPlatform.Repo.Migrations.CreateClients do
  use Ecto.Migration

  def change do
    create table(:clients) do
      add :business_name, :string, null: false
      add :industry, :string, null: false
      add :contact_name, :string, null: false
      add :contact_email, :string, null: false
      add :phone, :string
      add :website, :string
      add :status, :string, null: false, default: "onboarding"
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :plan, :string, null: false, default: "starter"
      add :monthly_price_cents, :integer, null: false
      add :total_paid_cents, :integer, null: false, default: 0
      add :onboarded_at, :utc_datetime
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:clients, [:contact_email])
    create unique_index(:clients, [:stripe_customer_id])
    create index(:clients, [:status])
    create index(:clients, [:industry])
    create index(:clients, [:plan])
  end
end
