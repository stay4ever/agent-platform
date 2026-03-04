defmodule AgentPlatform.Agents.Conversation do
  @moduledoc """
  Schema representing a conversation between a visitor and a deployed agent.

  Stores the full message history, channel metadata, satisfaction rating,
  and outcome for analytics and reporting purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @channels [:widget, :sms, :email, :whatsapp]
  @statuses [:active, :resolved, :escalated, :abandoned]

  schema "conversations" do
    belongs_to :agent, AgentPlatform.Agents.Agent

    field :visitor_id, :string
    field :channel, Ecto.Enum, values: @channels, default: :widget
    field :status, Ecto.Enum, values: @statuses, default: :active
    field :messages, {:array, :map}, default: []
    field :satisfaction_rating, :integer
    field :outcome, :string
    field :metadata, :map, default: %{}

    timestamps()
  end

  @required_fields ~w(agent_id visitor_id channel)a
  @optional_fields ~w(status messages satisfaction_rating outcome metadata)a

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:satisfaction_rating, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> foreign_key_constraint(:agent_id)
  end

  def add_message_changeset(conversation, message) do
    validated_message = %{
      "role" => message["role"] || message[:role],
      "content" => message["content"] || message[:content],
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    current_messages = conversation.messages || []

    conversation
    |> change(messages: current_messages ++ [validated_message])
  end

  def resolve_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:status, :satisfaction_rating, :outcome])
    |> put_change(:status, :resolved)
  end

  def escalate_changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:status, :outcome, :metadata])
    |> put_change(:status, :escalated)
  end
end
