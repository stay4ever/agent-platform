defmodule AgentPlatform.Billing.RevenueEvent do
  @moduledoc """
  Schema tracking all revenue events on the platform.

  Records subscription payments, setup fees, conversation overages,
  and refunds for accurate MRR and revenue reporting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @event_types [:subscription, :setup_fee, :overage, :refund]

  schema "platform_revenue_events" do
    belongs_to :client, AgentPlatform.Clients.Client

    field :type, Ecto.Enum, values: @event_types
    field :amount_cents, :integer
    field :stripe_event_id, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  @required_fields ~w(client_id type amount_cents)a
  @optional_fields ~w(stripe_event_id metadata)a

  def changeset(event, attrs) do
    event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @event_types)
    |> validate_number(:amount_cents, not_equal_to: 0)
    |> foreign_key_constraint(:client_id)
    |> unique_constraint(:stripe_event_id)
  end
end
