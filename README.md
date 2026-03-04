# AgentPlatform

White-label Claude agents sold on subscription to SMBs. Automated onboarding, agent deployment, billing, and monthly reporting.

## Target Industries

- Real Estate Agencies
- Medical Clinics
- Law Firms
- Restaurants
- Retail / Fitness / Salons

## Architecture

- **Elixir/Phoenix** application with LiveView dashboard
- **Oban** job processing for onboarding, agent runtime, billing, reporting, monitoring
- **Claude API** for conversation handling and report generation
- **Stripe** for subscription billing
- **Cloudflare R2** for knowledge base and report storage
- **PostgreSQL** for data persistence

## Setup

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Visit http://localhost:4003

## Environment Variables

```
DATABASE_URL=
SECRET_KEY_BASE=
CLAUDE_API_KEY=
STRIPE_SECRET_KEY=
STRIPE_WEBHOOK_SECRET=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_ENDPOINT=
R2_BUCKET=
```

## Deployment

Deployed to Fly.io. Push to `main` triggers CI/CD.

```bash
fly deploy
```
