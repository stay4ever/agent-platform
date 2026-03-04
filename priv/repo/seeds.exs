# Script for populating the database.
#
# Run with: mix run priv/repo/seeds.exs

alias AgentPlatform.{Repo, Clients.Client, Agents.Agent}

IO.puts("Seeding AgentPlatform database...")

# Seed demo clients
demo_clients = [
  %{
    business_name: "Skyline Realty Group",
    industry: :real_estate,
    contact_name: "Sarah Chen",
    contact_email: "sarah@skylinerealty.demo",
    phone: "+1-555-0101",
    website: "https://skylinerealty.demo",
    status: :active,
    plan: :professional,
    monthly_price_cents: 59_900,
    total_paid_cents: 299_500,
    onboarded_at: ~U[2024-01-15 10:00:00Z]
  },
  %{
    business_name: "ClearView Medical Center",
    industry: :medical,
    contact_name: "Dr. James Park",
    contact_email: "jpark@clearviewmed.demo",
    phone: "+1-555-0102",
    website: "https://clearviewmed.demo",
    status: :active,
    plan: :enterprise,
    monthly_price_cents: 149_900,
    total_paid_cents: 749_500,
    onboarded_at: ~U[2024-02-01 09:00:00Z]
  },
  %{
    business_name: "Morrison & Associates Law",
    industry: :legal,
    contact_name: "Katherine Morrison",
    contact_email: "k.morrison@morrisonlaw.demo",
    phone: "+1-555-0103",
    website: "https://morrisonlaw.demo",
    status: :active,
    plan: :professional,
    monthly_price_cents: 59_900,
    total_paid_cents: 179_700,
    onboarded_at: ~U[2024-03-10 14:00:00Z]
  },
  %{
    business_name: "The Golden Fork Restaurant",
    industry: :restaurant,
    contact_name: "Marco Bellini",
    contact_email: "marco@goldenfork.demo",
    phone: "+1-555-0104",
    website: "https://goldenfork.demo",
    status: :active,
    plan: :starter,
    monthly_price_cents: 29_900,
    total_paid_cents: 89_700,
    onboarded_at: ~U[2024-04-05 11:00:00Z]
  },
  %{
    business_name: "FitZone Wellness",
    industry: :fitness,
    contact_name: "Alex Rivera",
    contact_email: "alex@fitzone.demo",
    phone: "+1-555-0105",
    website: "https://fitzone.demo",
    status: :onboarding,
    plan: :starter,
    monthly_price_cents: 29_900,
    total_paid_cents: 0
  }
]

clients =
  Enum.map(demo_clients, fn attrs ->
    %Client{}
    |> Client.changeset(attrs)
    |> Repo.insert!(on_conflict: :nothing, conflict_target: :contact_email)
  end)

IO.puts("Seeded #{length(clients)} clients")

# Seed agents for active clients
agent_seeds = [
  # Skyline Realty agents
  {0, %{name: "Property Concierge", type: :receptionist, status: :active, system_prompt: "You are Property Concierge for Skyline Realty Group...", total_conversations: 342, total_messages: 2847, satisfaction_score: 4.3, conversations_today: 12}},
  {0, %{name: "Viewing Scheduler", type: :appointment_booker, status: :active, system_prompt: "You are the Viewing Scheduler for Skyline Realty Group...", total_conversations: 189, total_messages: 1256, satisfaction_score: 4.5, conversations_today: 7}},
  {0, %{name: "Buyer Qualifier", type: :lead_qualifier, status: :active, system_prompt: "You are the Buyer Qualifier for Skyline Realty Group...", total_conversations: 156, total_messages: 1890, satisfaction_score: 4.1, conversations_today: 5}},
  # ClearView Medical agents
  {1, %{name: "Patient Coordinator", type: :receptionist, status: :active, system_prompt: "You are the Patient Coordinator for ClearView Medical Center...", total_conversations: 567, total_messages: 3401, satisfaction_score: 4.6, conversations_today: 28}},
  {1, %{name: "Appointment Assistant", type: :appointment_booker, status: :active, system_prompt: "You are the Appointment Assistant for ClearView Medical Center...", total_conversations: 423, total_messages: 2115, satisfaction_score: 4.7, conversations_today: 19}},
  {1, %{name: "Health Info Guide", type: :faq_responder, status: :active, system_prompt: "You are the Health Information Guide for ClearView Medical Center...", total_conversations: 301, total_messages: 1806, satisfaction_score: 4.4, conversations_today: 15}},
  # Morrison Law agents
  {2, %{name: "Legal Intake Specialist", type: :receptionist, status: :active, system_prompt: "You are the Legal Intake Specialist for Morrison & Associates...", total_conversations: 198, total_messages: 2376, satisfaction_score: 4.2, conversations_today: 8}},
  {2, %{name: "Case Evaluator", type: :lead_qualifier, status: :active, system_prompt: "You are the Case Evaluator for Morrison & Associates...", total_conversations: 87, total_messages: 1305, satisfaction_score: 3.9, conversations_today: 3}},
  # Golden Fork agents
  {3, %{name: "Restaurant Host", type: :receptionist, status: :active, system_prompt: "You are the Restaurant Host for The Golden Fork...", total_conversations: 234, total_messages: 1170, satisfaction_score: 4.5, conversations_today: 15}},
  {3, %{name: "Reservation Agent", type: :appointment_booker, status: :active, system_prompt: "You are the Reservation Agent for The Golden Fork...", total_conversations: 178, total_messages: 890, satisfaction_score: 4.6, conversations_today: 11}},
  {3, %{name: "Guest Experience", type: :review_manager, status: :active, system_prompt: "You are the Guest Experience Manager for The Golden Fork...", total_conversations: 89, total_messages: 534, satisfaction_score: 4.3, conversations_today: 4}}
]

agents =
  Enum.map(agent_seeds, fn {client_idx, attrs} ->
    client = Enum.at(clients, client_idx)

    if client && client.id do
      %Agent{}
      |> Agent.changeset(Map.put(attrs, :client_id, client.id))
      |> Repo.insert!()
    end
  end)
  |> Enum.reject(&is_nil/1)

IO.puts("Seeded #{length(agents)} agents")
IO.puts("Seeding complete!")
