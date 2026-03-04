defmodule AgentPlatform.Workers.BillingWorker do
  @moduledoc """
  Oban worker for billing operations.

  Processes Stripe webhooks, handles subscription lifecycle events,
  calculates usage-based overages, and tracks revenue per client.
  """

  use Oban.Worker,
    queue: :billing,
    max_attempts: 3,
    tags: ["billing"]

  require Logger

  alias AgentPlatform.{Clients, Agents, Billing}
  alias AgentPlatform.Clients.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "stripe_webhook", "event_type" => event_type} = args}) do
    Logger.info("Processing Stripe webhook: #{event_type}")

    case event_type do
      "invoice.payment_succeeded" ->
        handle_payment_succeeded(args)

      "invoice.payment_failed" ->
        handle_payment_failed(args)

      "customer.subscription.updated" ->
        handle_subscription_updated(args)

      "customer.subscription.deleted" ->
        handle_subscription_deleted(args)

      "charge.refunded" ->
        handle_refund(args)

      _ ->
        Logger.info("Unhandled Stripe event type: #{event_type}")
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"type" => "daily_usage_sync"}}) do
    Logger.info("Running daily usage sync across all active clients")

    Clients.list_clients_by_status(:active)
    |> Enum.each(fn client ->
      conversation_count = Agents.conversations_this_month(client.id)
      Billing.process_overage(client, conversation_count)
    end)

    :ok
  end

  def perform(%Oban.Job{args: %{"type" => "process_overage", "client_id" => client_id}}) do
    client = Clients.get_client!(client_id)
    conversation_count = Agents.conversations_this_month(client_id)

    case Billing.process_overage(client, conversation_count) do
      {:ok, :within_limit} ->
        Logger.info("Client #{client_id} within conversation limit")
        :ok

      {:ok, _event} ->
        Logger.info("Overage recorded for client #{client_id}: #{conversation_count} conversations")
        :ok

      {:error, reason} ->
        Logger.error("Overage processing failed for client #{client_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- Stripe Event Handlers ---

  defp handle_payment_succeeded(args) do
    stripe_customer_id = get_in(args, ["data", "customer"])
    amount_cents = get_in(args, ["data", "amount_paid"]) || 0
    stripe_event_id = args["stripe_event_id"]

    case Clients.get_client_by_stripe_id(stripe_customer_id) do
      nil ->
        Logger.warn("Payment received for unknown Stripe customer: #{stripe_customer_id}")
        :ok

      %Client{} = client ->
        Billing.record_revenue_event(%{
          client_id: client.id,
          type: :subscription,
          amount_cents: amount_cents,
          stripe_event_id: stripe_event_id,
          metadata: %{
            stripe_customer_id: stripe_customer_id,
            invoice_id: get_in(args, ["data", "id"])
          }
        })

        Clients.record_payment(client, amount_cents)

        broadcast_revenue_event(client, amount_cents)

        Logger.info("Payment of #{format_cents(amount_cents)} recorded for #{client.business_name}")
        :ok
    end
  end

  defp handle_payment_failed(args) do
    stripe_customer_id = get_in(args, ["data", "customer"])

    case Clients.get_client_by_stripe_id(stripe_customer_id) do
      nil ->
        Logger.warn("Payment failure for unknown customer: #{stripe_customer_id}")
        :ok

      %Client{} = client ->
        attempt = get_in(args, ["data", "attempt_count"]) || 1

        Logger.warn(
          "Payment failed for #{client.business_name} (attempt #{attempt})"
        )

        if attempt >= 3 do
          Logger.warn("Pausing client #{client.business_name} after 3 failed payments")
          Clients.pause_client(client)

          Phoenix.PubSub.broadcast(
            AgentPlatform.PubSub,
            "platform:events",
            {:client_payment_failed, client.id, attempt}
          )
        end

        :ok
    end
  end

  defp handle_subscription_updated(args) do
    stripe_customer_id = get_in(args, ["data", "customer"])
    new_status = get_in(args, ["data", "status"])

    case Clients.get_client_by_stripe_id(stripe_customer_id) do
      nil ->
        :ok

      %Client{} = client ->
        case new_status do
          "active" -> Clients.update_client(client, %{status: :active})
          "past_due" -> Clients.update_client(client, %{status: :paused})
          "canceled" -> Clients.churn_client(client)
          _ -> :ok
        end

        Logger.info("Subscription updated for #{client.business_name}: #{new_status}")
        :ok
    end
  end

  defp handle_subscription_deleted(args) do
    stripe_customer_id = get_in(args, ["data", "customer"])

    case Clients.get_client_by_stripe_id(stripe_customer_id) do
      nil ->
        :ok

      %Client{} = client ->
        Clients.churn_client(client)

        Agents.list_agents_for_client(client.id)
        |> Enum.each(&Agents.retire_agent/1)

        Logger.info("Client #{client.business_name} churned - all agents retired")

        Phoenix.PubSub.broadcast(
          AgentPlatform.PubSub,
          "platform:events",
          {:client_churned, client.id}
        )

        :ok
    end
  end

  defp handle_refund(args) do
    stripe_customer_id = get_in(args, ["data", "customer"])
    amount_cents = get_in(args, ["data", "amount_refunded"]) || 0
    stripe_event_id = args["stripe_event_id"]

    case Clients.get_client_by_stripe_id(stripe_customer_id) do
      nil ->
        :ok

      %Client{} = client ->
        Billing.record_revenue_event(%{
          client_id: client.id,
          type: :refund,
          amount_cents: -amount_cents,
          stripe_event_id: stripe_event_id,
          metadata: %{reason: get_in(args, ["data", "reason"])}
        })

        Logger.info("Refund of #{format_cents(amount_cents)} for #{client.business_name}")
        :ok
    end
  end

  # --- Helpers ---

  defp broadcast_revenue_event(client, amount_cents) do
    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:revenue_event, client.id, amount_cents}
    )
  end

  defp format_cents(cents) when is_integer(cents) do
    dollars = cents / 100
    "$#{:erlang.float_to_binary(dollars, decimals: 2)}"
  end

  defp format_cents(_), do: "$0.00"
end
