defmodule AgentPlatform.Clients.Client do
  @moduledoc """
  Schema representing an SMB client on the platform.

  Each client has a business profile, Stripe billing integration,
  a subscription plan, and one or more deployed agents.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @industries [:real_estate, :medical, :legal, :restaurant, :retail, :fitness, :salon, :other]
  @statuses [:onboarding, :active, :paused, :churned]
  @plans [:starter, :professional, :enterprise]

  schema "clients" do
    field :business_name, :string
    field :industry, Ecto.Enum, values: @industries
    field :contact_name, :string
    field :contact_email, :string
    field :phone, :string
    field :website, :string
    field :status, Ecto.Enum, values: @statuses, default: :onboarding
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :plan, Ecto.Enum, values: @plans, default: :starter
    field :monthly_price_cents, :integer
    field :total_paid_cents, :integer, default: 0
    field :onboarded_at, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :agents, AgentPlatform.Agents.Agent
    has_many :revenue_events, AgentPlatform.Billing.RevenueEvent

    timestamps()
  end

  @required_fields ~w(business_name industry contact_name contact_email plan monthly_price_cents)a
  @optional_fields ~w(phone website status stripe_customer_id stripe_subscription_id total_paid_cents onboarded_at metadata)a

  def changeset(client, attrs) do
    client
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:contact_email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/, message: "must be a valid email")
    |> validate_number(:monthly_price_cents, greater_than: 0)
    |> validate_inclusion(:industry, @industries)
    |> validate_inclusion(:plan, @plans)
    |> unique_constraint(:contact_email)
    |> unique_constraint(:stripe_customer_id)
  end

  def activate_changeset(client, attrs) do
    client
    |> cast(attrs, [:status, :onboarded_at, :stripe_customer_id, :stripe_subscription_id])
    |> put_change(:status, :active)
    |> put_change(:onboarded_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def plan_prices do
    %{
      starter: 29_900,
      professional: 59_900,
      enterprise: 149_900
    }
  end

  def plan_display_name(:starter), do: "Starter ($299/mo)"
  def plan_display_name(:professional), do: "Professional ($599/mo)"
  def plan_display_name(:enterprise), do: "Enterprise ($1,499/mo)"
end
