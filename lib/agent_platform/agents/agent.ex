defmodule AgentPlatform.Agents.Agent do
  @moduledoc """
  Schema representing a deployed Claude agent for a client.

  Each agent has a type (receptionist, appointment booker, etc.),
  a system prompt tailored to the client's business, and tracks
  conversation metrics for performance monitoring.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @agent_types [:receptionist, :appointment_booker, :lead_qualifier, :faq_responder, :follow_up, :review_manager]
  @statuses [:configuring, :active, :paused, :retired]

  schema "agents" do
    belongs_to :client, AgentPlatform.Clients.Client

    field :name, :string
    field :type, Ecto.Enum, values: @agent_types
    field :status, Ecto.Enum, values: @statuses, default: :configuring
    field :system_prompt, :string
    field :knowledge_base_key, :string
    field :total_conversations, :integer, default: 0
    field :total_messages, :integer, default: 0
    field :satisfaction_score, :float, default: 0.0
    field :conversations_today, :integer, default: 0
    field :config, :map, default: %{}
    field :webhook_url, :string
    field :widget_token, :string

    has_many :conversations, AgentPlatform.Agents.Conversation

    timestamps()
  end

  @required_fields ~w(client_id name type)a
  @optional_fields ~w(status system_prompt knowledge_base_key total_conversations total_messages satisfaction_score conversations_today config webhook_url widget_token)a

  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @agent_types)
    |> validate_length(:name, min: 2, max: 100)
    |> foreign_key_constraint(:client_id)
    |> unique_constraint(:widget_token)
    |> maybe_generate_widget_token()
  end

  def metrics_changeset(agent, attrs) do
    agent
    |> cast(attrs, [:total_conversations, :total_messages, :satisfaction_score, :conversations_today])
    |> validate_number(:satisfaction_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 5.0)
  end

  defp maybe_generate_widget_token(changeset) do
    case get_field(changeset, :widget_token) do
      nil -> put_change(changeset, :widget_token, generate_token())
      _ -> changeset
    end
  end

  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end

  def type_display_name(:receptionist), do: "Virtual Receptionist"
  def type_display_name(:appointment_booker), do: "Appointment Booker"
  def type_display_name(:lead_qualifier), do: "Lead Qualifier"
  def type_display_name(:faq_responder), do: "FAQ Responder"
  def type_display_name(:follow_up), do: "Follow-Up Agent"
  def type_display_name(:review_manager), do: "Review Manager"
end
