defmodule AgentPlatform.Billing do
  @moduledoc """
  Context module for billing and revenue tracking.

  Handles Stripe integration, revenue event recording,
  usage-based overage billing, and MRR calculations.
  """

  import Ecto.Query, warn: false
  alias AgentPlatform.Repo
  alias AgentPlatform.Billing.RevenueEvent
  alias AgentPlatform.Clients
  alias AgentPlatform.Clients.Client

  # --- Revenue Events ---

  def record_revenue_event(attrs) do
    %RevenueEvent{}
    |> RevenueEvent.changeset(attrs)
    |> Repo.insert()
  end

  def list_revenue_events(opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    RevenueEvent
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:client)
    |> Repo.all()
  end

  def revenue_events_for_client(client_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    RevenueEvent
    |> where([r], r.client_id == ^client_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def monthly_revenue do
    start_of_month =
      Date.utc_today()
      |> Date.beginning_of_month()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    RevenueEvent
    |> where([r], r.inserted_at >= ^start_of_month and r.type != :refund)
    |> Repo.aggregate(:sum, :amount_cents) || 0
  end

  def total_revenue do
    positive =
      RevenueEvent
      |> where([r], r.type != :refund)
      |> Repo.aggregate(:sum, :amount_cents) || 0

    refunds =
      RevenueEvent
      |> where([r], r.type == :refund)
      |> Repo.aggregate(:sum, :amount_cents) || 0

    positive - abs(refunds)
  end

  def mrr do
    Clients.total_mrr()
  end

  # --- Stripe Operations ---

  def create_stripe_customer(%Client{} = client) do
    case Stripe.Customer.create(%{
           email: client.contact_email,
           name: client.business_name,
           metadata: %{
             client_id: to_string(client.id),
             industry: to_string(client.industry),
             plan: to_string(client.plan)
           }
         }) do
      {:ok, customer} ->
        Clients.update_client(client, %{stripe_customer_id: customer.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_subscription(%Client{} = client) do
    price_id = price_id_for_plan(client.plan)

    case Stripe.Subscription.create(%{
           customer: client.stripe_customer_id,
           items: [%{price: price_id}],
           metadata: %{client_id: to_string(client.id)}
         }) do
      {:ok, subscription} ->
        Clients.update_client(client, %{stripe_subscription_id: subscription.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def cancel_subscription(%Client{} = client) do
    case Stripe.Subscription.cancel(client.stripe_subscription_id, %{}) do
      {:ok, _subscription} ->
        Clients.churn_client(client)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def process_overage(%Client{} = client, conversation_count) do
    plan_limit = conversation_limit(client.plan)

    if plan_limit != :unlimited and conversation_count > plan_limit do
      overage = conversation_count - plan_limit
      overage_rate = Application.get_env(:agent_platform, :platform)[:overage_rate_cents]
      amount = overage * overage_rate

      record_revenue_event(%{
        client_id: client.id,
        type: :overage,
        amount_cents: amount,
        metadata: %{
          conversations: conversation_count,
          plan_limit: plan_limit,
          overage_count: overage
        }
      })
    else
      {:ok, :within_limit}
    end
  end

  # --- Helpers ---

  defp conversation_limit(:starter), do: 1000
  defp conversation_limit(:professional), do: 5000
  defp conversation_limit(:enterprise), do: :unlimited

  defp price_id_for_plan(:starter), do: System.get_env("STRIPE_STARTER_PRICE_ID") || "price_starter"
  defp price_id_for_plan(:professional), do: System.get_env("STRIPE_PROFESSIONAL_PRICE_ID") || "price_professional"
  defp price_id_for_plan(:enterprise), do: System.get_env("STRIPE_ENTERPRISE_PRICE_ID") || "price_enterprise"
end
