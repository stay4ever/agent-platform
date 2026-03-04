defmodule AgentPlatform.Clients do
  @moduledoc """
  Context module for client management.

  Handles CRUD operations, status transitions, and querying
  for the SMB clients on the platform.
  """

  import Ecto.Query, warn: false
  alias AgentPlatform.Repo
  alias AgentPlatform.Clients.Client

  def list_clients do
    Client
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def list_clients_by_status(status) do
    Client
    |> where([c], c.status == ^status)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def get_client!(id), do: Repo.get!(Client, id)

  def get_client(id), do: Repo.get(Client, id)

  def get_client_by_email(email) do
    Repo.get_by(Client, contact_email: email)
  end

  def get_client_by_stripe_id(stripe_customer_id) do
    Repo.get_by(Client, stripe_customer_id: stripe_customer_id)
  end

  def get_client_with_agents(id) do
    Client
    |> Repo.get(id)
    |> Repo.preload(:agents)
  end

  def create_client(attrs \\ %{}) do
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert()
  end

  def update_client(%Client{} = client, attrs) do
    client
    |> Client.changeset(attrs)
    |> Repo.update()
  end

  def activate_client(%Client{} = client, stripe_attrs) do
    client
    |> Client.activate_changeset(stripe_attrs)
    |> Repo.update()
  end

  def pause_client(%Client{} = client) do
    update_client(client, %{status: :paused})
  end

  def churn_client(%Client{} = client) do
    update_client(client, %{status: :churned})
  end

  def record_payment(%Client{} = client, amount_cents) do
    update_client(client, %{total_paid_cents: (client.total_paid_cents || 0) + amount_cents})
  end

  def count_active_clients do
    Client
    |> where([c], c.status == :active)
    |> Repo.aggregate(:count, :id)
  end

  def total_mrr do
    Client
    |> where([c], c.status == :active)
    |> Repo.aggregate(:sum, :monthly_price_cents) || 0
  end

  def total_revenue do
    Client
    |> Repo.aggregate(:sum, :total_paid_cents) || 0
  end

  def clients_at_risk do
    Client
    |> where([c], c.status == :active)
    |> preload(:agents)
    |> Repo.all()
    |> Enum.filter(fn client ->
      agents = client.agents || []

      avg_satisfaction =
        case agents do
          [] -> 0.0
          agents -> Enum.sum(Enum.map(agents, & &1.satisfaction_score)) / length(agents)
        end

      total_convos_today = Enum.sum(Enum.map(agents, & &1.conversations_today))

      avg_satisfaction < 3.0 or total_convos_today == 0
    end)
  end
end
