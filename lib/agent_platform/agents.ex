defmodule AgentPlatform.Agents do
  @moduledoc """
  Context module for agent and conversation management.

  Handles agent CRUD, conversation lifecycle, metrics tracking,
  and querying across all deployed agents.
  """

  import Ecto.Query, warn: false
  alias AgentPlatform.Repo
  alias AgentPlatform.Agents.{Agent, Conversation}

  # --- Agent operations ---

  def list_agents do
    Agent
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def list_agents_for_client(client_id) do
    Agent
    |> where([a], a.client_id == ^client_id)
    |> order_by(desc: :inserted_at)
    |> Repo.all()
  end

  def list_active_agents do
    Agent
    |> where([a], a.status == :active)
    |> Repo.all()
  end

  def get_agent!(id), do: Repo.get!(Agent, id)

  def get_agent(id), do: Repo.get(Agent, id)

  def get_agent_by_token(token) do
    Repo.get_by(Agent, widget_token: token)
  end

  def get_agent_with_client(id) do
    Agent
    |> Repo.get(id)
    |> Repo.preload(:client)
  end

  def create_agent(attrs \\ %{}) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  def activate_agent(%Agent{} = agent) do
    update_agent(agent, %{status: :active})
  end

  def pause_agent(%Agent{} = agent) do
    update_agent(agent, %{status: :paused})
  end

  def retire_agent(%Agent{} = agent) do
    update_agent(agent, %{status: :retired})
  end

  def update_agent_metrics(%Agent{} = agent, attrs) do
    agent
    |> Agent.metrics_changeset(attrs)
    |> Repo.update()
  end

  def increment_conversations(%Agent{} = agent) do
    from(a in Agent, where: a.id == ^agent.id)
    |> Repo.update_all(
      inc: [total_conversations: 1, conversations_today: 1]
    )
  end

  def increment_messages(%Agent{} = agent, count \\ 1) do
    from(a in Agent, where: a.id == ^agent.id)
    |> Repo.update_all(inc: [total_messages: count])
  end

  def reset_daily_counters do
    from(a in Agent, where: a.status == :active)
    |> Repo.update_all(set: [conversations_today: 0])
  end

  def count_active_agents do
    Agent
    |> where([a], a.status == :active)
    |> Repo.aggregate(:count, :id)
  end

  def total_conversations_today do
    Agent
    |> where([a], a.status == :active)
    |> Repo.aggregate(:sum, :conversations_today) || 0
  end

  def platform_satisfaction do
    result =
      Agent
      |> where([a], a.status == :active and a.total_conversations > 0)
      |> Repo.aggregate(:avg, :satisfaction_score)

    result || 0.0
  end

  # --- Conversation operations ---

  def list_conversations_for_agent(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Conversation
    |> where([c], c.agent_id == ^agent_id)
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  def list_recent_conversations(opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    Conversation
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> preload(:agent)
    |> Repo.all()
  end

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def get_conversation(id), do: Repo.get(Conversation, id)

  def get_active_conversation(agent_id, visitor_id) do
    Conversation
    |> where([c], c.agent_id == ^agent_id and c.visitor_id == ^visitor_id and c.status == :active)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def add_message(%Conversation{} = conversation, message) do
    conversation
    |> Conversation.add_message_changeset(message)
    |> Repo.update()
  end

  def resolve_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    conversation
    |> Conversation.resolve_changeset(attrs)
    |> Repo.update()
  end

  def escalate_conversation(%Conversation{} = conversation, attrs \\ %{}) do
    conversation
    |> Conversation.escalate_changeset(attrs)
    |> Repo.update()
  end

  def conversations_this_month(client_id) do
    start_of_month =
      Date.utc_today()
      |> Date.beginning_of_month()
      |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(c in Conversation,
      join: a in Agent,
      on: a.id == c.agent_id,
      where: a.client_id == ^client_id and c.inserted_at >= ^start_of_month
    )
    |> Repo.aggregate(:count, :id)
  end

  def total_conversations_all_time do
    Repo.aggregate(Conversation, :count, :id)
  end
end
