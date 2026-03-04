defmodule AgentPlatform.Workers.OnboardingWorker do
  @moduledoc """
  Oban worker for autonomous client onboarding.

  Handles the full onboarding pipeline:
  1. Create Stripe customer and subscription
  2. Scrape client website to build knowledge base
  3. Generate industry-specific agent system prompts
  4. Configure agent personas from templates
  5. Generate embeddable widget code
  6. Send welcome email with setup instructions
  """

  use Oban.Worker,
    queue: :onboarding,
    max_attempts: 3,
    tags: ["onboarding"]

  require Logger

  alias AgentPlatform.{Clients, Agents, Billing, ClaudeClient, KnowledgeBase, Widget}
  alias AgentPlatform.Clients.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"client_id" => client_id}}) do
    Logger.info("Starting onboarding for client #{client_id}")

    with {:ok, client} <- fetch_client(client_id),
         {:ok, client} <- setup_stripe(client),
         {:ok, knowledge} <- build_knowledge_base(client),
         {:ok, agents} <- deploy_agents(client, knowledge),
         :ok <- generate_widgets(client, agents),
         :ok <- send_welcome_email(client, agents) do
      Clients.activate_client(client, %{})
      broadcast_onboarding_complete(client)
      Logger.info("Onboarding complete for client #{client_id}: #{client.business_name}")
      :ok
    else
      {:error, step, reason} ->
        Logger.error("Onboarding failed at #{step} for client #{client_id}: #{inspect(reason)}")
        {:error, "#{step}: #{inspect(reason)}"}

      {:error, reason} ->
        Logger.error("Onboarding failed for client #{client_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_client(client_id) do
    case Clients.get_client(client_id) do
      nil -> {:error, :step_fetch, "Client not found"}
      client -> {:ok, client}
    end
  end

  defp setup_stripe(%Client{} = client) do
    Logger.info("Setting up Stripe for #{client.business_name}")

    case Billing.create_stripe_customer(client) do
      {:ok, client_with_stripe} ->
        case Billing.create_subscription(client_with_stripe) do
          {:ok, client_with_sub} ->
            Billing.record_revenue_event(%{
              client_id: client.id,
              type: :setup_fee,
              amount_cents: 0,
              metadata: %{note: "Onboarding setup"}
            })

            {:ok, client_with_sub}

          {:error, reason} ->
            {:error, :stripe_subscription, reason}
        end

      {:error, reason} ->
        {:error, :stripe_customer, reason}
    end
  end

  defp build_knowledge_base(%Client{} = client) do
    Logger.info("Building knowledge base for #{client.business_name}")

    case KnowledgeBase.build_from_website(client) do
      {:ok, knowledge} -> {:ok, knowledge}
      {:error, reason} ->
        Logger.warn("Knowledge base build failed, using industry defaults: #{inspect(reason)}")
        {:ok, KnowledgeBase.industry_defaults(client.industry)}
    end
  end

  defp deploy_agents(%Client{} = client, knowledge) do
    Logger.info("Deploying agents for #{client.business_name} (#{client.industry})")

    agent_configs = industry_agent_templates(client.industry)

    agents =
      Enum.map(agent_configs, fn config ->
        system_prompt = ClaudeClient.generate_system_prompt(client, config)
        kb_key = "clients/#{client.id}/knowledge/#{config.type}"

        KnowledgeBase.store(kb_key, knowledge)

        {:ok, agent} =
          Agents.create_agent(%{
            client_id: client.id,
            name: config.name,
            type: config.type,
            system_prompt: system_prompt,
            knowledge_base_key: kb_key,
            status: :active,
            config: %{
              greeting: config.greeting,
              escalation_triggers: config.escalation_triggers,
              business_hours: config.business_hours,
              language: "en"
            }
          })

        agent
      end)

    {:ok, agents}
  end

  defp generate_widgets(%Client{} = client, agents) do
    Logger.info("Generating widgets for #{client.business_name}")

    Enum.each(agents, fn agent ->
      _widget_code = Widget.generate_embed_code(agent)
      Logger.info("Widget generated for agent #{agent.name} (token: #{agent.widget_token})")
    end)

    :ok
  end

  defp send_welcome_email(%Client{} = client, agents) do
    Logger.info("Sending welcome email to #{client.contact_email}")

    agent_details =
      Enum.map(agents, fn agent ->
        %{
          name: agent.name,
          type: agent.type,
          widget_token: agent.widget_token,
          embed_url: "#{AgentPlatformWeb.Endpoint.url()}/api/agents/#{agent.id}/widget.js"
        }
      end)

    _email_body = """
    Welcome to AgentPlatform, #{client.contact_name}!

    Your AI agents are now live and ready to help your business:

    #{Enum.map_join(agent_details, "\n", fn a -> "- #{a.name} (#{a.type}): #{a.embed_url}" end)}

    Quick Start:
    1. Add the widget script to your website
    2. Your agents will start handling conversations immediately
    3. View your dashboard at #{AgentPlatformWeb.Endpoint.url()}

    Your #{Client.plan_display_name(client.plan)} plan includes up to
    #{plan_conversation_limit(client.plan)} conversations per month.

    Best regards,
    The AgentPlatform Team
    """

    # In production, this would send via a transactional email service
    Logger.info("Welcome email prepared for #{client.contact_email}")
    :ok
  end

  defp broadcast_onboarding_complete(client) do
    Phoenix.PubSub.broadcast(
      AgentPlatform.PubSub,
      "platform:events",
      {:client_onboarded, client}
    )
  end

  defp plan_conversation_limit(:starter), do: "1,000"
  defp plan_conversation_limit(:professional), do: "5,000"
  defp plan_conversation_limit(:enterprise), do: "unlimited"

  defp industry_agent_templates(:real_estate) do
    [
      %{
        type: :receptionist,
        name: "Property Concierge",
        greeting: "Welcome! I can help you find your perfect property or schedule a viewing. How can I assist you today?",
        escalation_triggers: ["speak to agent", "human", "offer", "contract", "negotiation"],
        business_hours: %{start: "08:00", end: "20:00", timezone: "America/New_York"}
      },
      %{
        type: :appointment_booker,
        name: "Viewing Scheduler",
        greeting: "I'd love to help you schedule a property viewing. What area are you interested in?",
        escalation_triggers: ["urgent", "complaint", "manager"],
        business_hours: %{start: "09:00", end: "18:00", timezone: "America/New_York"}
      },
      %{
        type: :lead_qualifier,
        name: "Buyer Qualifier",
        greeting: "Welcome! Let me help match you with the right properties. What's your ideal home like?",
        escalation_triggers: ["budget over 1m", "commercial", "investment portfolio"],
        business_hours: %{start: "00:00", end: "23:59", timezone: "America/New_York"}
      }
    ]
  end

  defp industry_agent_templates(:medical) do
    [
      %{
        type: :receptionist,
        name: "Patient Coordinator",
        greeting: "Welcome to our practice. I can help with appointments, general questions, or direct you to the right department.",
        escalation_triggers: ["emergency", "urgent", "pain", "chest", "breathing", "911"],
        business_hours: %{start: "07:00", end: "19:00", timezone: "America/New_York"}
      },
      %{
        type: :appointment_booker,
        name: "Appointment Assistant",
        greeting: "I can help you schedule, reschedule, or cancel an appointment. What would you like to do?",
        escalation_triggers: ["same day", "emergency", "specialist referral"],
        business_hours: %{start: "07:00", end: "19:00", timezone: "America/New_York"}
      },
      %{
        type: :faq_responder,
        name: "Health Information Guide",
        greeting: "I can answer general questions about our services, insurance, and office procedures. How can I help?",
        escalation_triggers: ["medical advice", "diagnosis", "prescription", "symptoms"],
        business_hours: %{start: "00:00", end: "23:59", timezone: "America/New_York"}
      }
    ]
  end

  defp industry_agent_templates(:legal) do
    [
      %{
        type: :receptionist,
        name: "Legal Intake Specialist",
        greeting: "Welcome to our firm. I can help you understand our services and connect you with the right attorney.",
        escalation_triggers: ["emergency", "court date tomorrow", "arrested", "detained"],
        business_hours: %{start: "08:00", end: "18:00", timezone: "America/New_York"}
      },
      %{
        type: :lead_qualifier,
        name: "Case Evaluator",
        greeting: "I can help determine if we can assist with your legal matter. Could you briefly describe your situation?",
        escalation_triggers: ["class action", "corporate", "high value"],
        business_hours: %{start: "08:00", end: "18:00", timezone: "America/New_York"}
      }
    ]
  end

  defp industry_agent_templates(:restaurant) do
    [
      %{
        type: :receptionist,
        name: "Restaurant Host",
        greeting: "Welcome! I can help with reservations, our menu, catering inquiries, or answer any questions about our restaurant.",
        escalation_triggers: ["complaint", "food allergy emergency", "manager"],
        business_hours: %{start: "10:00", end: "23:00", timezone: "America/New_York"}
      },
      %{
        type: :appointment_booker,
        name: "Reservation Agent",
        greeting: "I'd be happy to help you make a reservation. When would you like to dine with us?",
        escalation_triggers: ["large party", "private event", "catering"],
        business_hours: %{start: "10:00", end: "22:00", timezone: "America/New_York"}
      },
      %{
        type: :review_manager,
        name: "Guest Experience Manager",
        greeting: "Thank you for dining with us! We'd love to hear about your experience.",
        escalation_triggers: ["food poisoning", "serious complaint", "legal"],
        business_hours: %{start: "00:00", end: "23:59", timezone: "America/New_York"}
      }
    ]
  end

  defp industry_agent_templates(_industry) do
    [
      %{
        type: :receptionist,
        name: "Virtual Receptionist",
        greeting: "Welcome! How can I help you today?",
        escalation_triggers: ["speak to human", "manager", "complaint", "emergency"],
        business_hours: %{start: "08:00", end: "18:00", timezone: "America/New_York"}
      },
      %{
        type: :faq_responder,
        name: "FAQ Assistant",
        greeting: "I can answer questions about our services and help point you in the right direction.",
        escalation_triggers: ["complex issue", "speak to someone", "urgent"],
        business_hours: %{start: "00:00", end: "23:59", timezone: "America/New_York"}
      }
    ]
  end
end
