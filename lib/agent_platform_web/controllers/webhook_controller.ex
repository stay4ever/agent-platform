defmodule AgentPlatformWeb.WebhookController do
  @moduledoc """
  Handles incoming Stripe webhook events.

  Verifies webhook signatures and enqueues billing worker jobs.
  """

  use AgentPlatformWeb, :controller

  alias AgentPlatform.Workers.BillingWorker

  def stripe(conn, _params) do
    raw_body = conn.private[:raw_body] || ""
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case verify_stripe_signature(raw_body, signature) do
      {:ok, event} ->
        enqueue_webhook_processing(event)

        conn
        |> put_status(200)
        |> json(%{received: true})

      {:error, reason} ->
        conn
        |> put_status(400)
        |> json(%{error: "Webhook verification failed", reason: inspect(reason)})
    end
  end

  defp verify_stripe_signature(raw_body, signature) do
    signing_secret = Application.get_env(:stripity_stripe, :signing_secret)

    if signing_secret do
      case Stripe.Webhook.construct_event(raw_body, signature, signing_secret) do
        {:ok, event} -> {:ok, event}
        {:error, reason} -> {:error, reason}
      end
    else
      # In development without signing secret, parse directly
      case Jason.decode(raw_body) do
        {:ok, event} -> {:ok, event}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp enqueue_webhook_processing(event) do
    event_type =
      case event do
        %Stripe.Event{type: type} -> type
        %{"type" => type} -> type
        _ -> "unknown"
      end

    event_id =
      case event do
        %Stripe.Event{id: id} -> id
        %{"id" => id} -> id
        _ -> nil
      end

    event_data =
      case event do
        %Stripe.Event{data: %{object: object}} -> serialize_stripe_object(object)
        %{"data" => %{"object" => object}} -> object
        _ -> %{}
      end

    %{
      type: "stripe_webhook",
      event_type: event_type,
      stripe_event_id: event_id,
      data: event_data
    }
    |> BillingWorker.new()
    |> Oban.insert()
  end

  defp serialize_stripe_object(object) when is_struct(object) do
    object
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Enum.into(%{}, fn
      {k, v} when is_struct(v) -> {to_string(k), serialize_stripe_object(v)}
      {k, v} -> {to_string(k), v}
    end)
  end

  defp serialize_stripe_object(object) when is_map(object), do: object
  defp serialize_stripe_object(object), do: object
end
