# PolicyHub

**Git-backed policy management with structured approval workflows, a role-filtered reader portal, and an AI policy bot.**

PolicyHub stores all policy content as Markdown in a GitLab repository, manages the full authoring-to-publishing lifecycle through a PR-style approval workflow, and surfaces published policies to staff through a searchable, role-filtered portal. Non-technical authors never see git.

---

## Table of contents

- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Environment variables](#environment-variables)
- [Key commands](#key-commands)
- [Project structure](#project-structure)
- [Development workflow](#development-workflow)
- [Testing](#testing)
- [Database](#database)
- [Local services](#local-services)
- [Deployment](#deployment)
- [Document index](#document-index)
- [Contributing](#contributing)

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Node.js | **≥ 24 LTS** | `node --version` |
| npm | **≥ 11** | `npm --version` |
| Docker + Docker Compose | Any recent | For local Postgres, Valkey, Typesense |
| GitLab CE instance | 16.x+ | Separate from this repo — see [GitLab setup guide](docs/GitLab_Setup_Guide.docx) |

> **Apple Silicon (M-series):** All Docker images used have `linux/arm64` variants. No Rosetta required.

---

## Getting started

> **Target: running application in under 5 minutes.**
> Steps 1–5 are one-time setup. After that, only step 6 is needed each day.

**1. Clone and install**

```bash
git clone https://gitlab.yourcompany.com/your-namespace/policy-platform.git
cd policy-platform
npm install
```

**2. Start local services**

```bash
docker compose up -d
```

This starts PostgreSQL 16, Valkey 7, and Typesense 28. Verify they're healthy:

```bash
docker compose ps
```

All three services should show `healthy` status before continuing.

**3. Configure environment**

```bash
cp .env.example .env.local
```

Open `.env.local` and fill in at minimum:

```bash
# Required for the app to start:
APP_KEY=                    # Generate with: node ace generate:key
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=policyhub
DB_PASSWORD=policyhub
DB_DATABASE=policyhub

# Required for login (use LOCAL_AUTH_ENABLED=true until Entra is configured):
LOCAL_AUTH_ENABLED=true
SESSION_DRIVER=cookie
```

GitLab and Entra/SSO variables can be left blank for initial local development — see [Environment variables](#environment-variables) for the full reference.

**4. Run migrations and seed**

```bash
node ace migration:run
node ace db:seed
```

The default seeder creates:
- 3 users: `author@example.com`, `reviewer@example.com`, `admin@example.com` (password: `password` for all)
- 4 categories: Finance, HR, IT, Legal
- 2 draft policies with sample content

**5. Start the development server**

```bash
node ace serve --hmr
```

Open [http://localhost:3333](http://localhost:3333). Sign in with `author@example.com` / `password`.

**6. Daily startup (after first-time setup)**

```bash
docker compose up -d && node ace serve --hmr
```

---

## Environment variables

Full variable reference. All variables listed in `.env.example` with descriptions. Only the groups marked **required to start** must be set before `node ace serve` will run.

<details>
<summary><strong>Application (required to start)</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `APP_KEY` | ✅ | — | 32-byte base64 encryption key. Generate with `node ace generate:key` |
| `APP_URL` | ✅ | `http://localhost:3333` | Full base URL including scheme, no trailing slash |
| `NODE_ENV` | ✅ | `development` | `development`, `test`, or `production` |
| `PORT` | — | `3333` | HTTP listen port |
| `HOST` | — | `0.0.0.0` | HTTP listen host |
| `LOG_LEVEL` | — | `info` | Pino log level: `trace`, `debug`, `info`, `warn`, `error` |

</details>

<details>
<summary><strong>Database (required to start)</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DB_HOST` | ✅ | `127.0.0.1` | PostgreSQL host |
| `DB_PORT` | ✅ | `5432` | PostgreSQL port |
| `DB_USER` | ✅ | `policyhub` | PostgreSQL username |
| `DB_PASSWORD` | ✅ | — | PostgreSQL password |
| `DB_DATABASE` | ✅ | `policyhub` | PostgreSQL database name |
| `DB_SSL` | — | `false` | Set `true` in production |

</details>

<details>
<summary><strong>Cache & queues — Valkey (required to start)</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `REDIS_HOST` | ✅ | `127.0.0.1` | Valkey host (wire-compatible with Redis) |
| `REDIS_PORT` | ✅ | `6379` | Valkey port |
| `REDIS_PASSWORD` | — | — | Valkey password (leave blank for local dev) |
| `QUEUE_DRIVER` | — | `redis` | Queue driver. Use `sync` in tests to run jobs inline |

</details>

<details>
<summary><strong>Authentication</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SESSION_DRIVER` | ✅ | `cookie` | `cookie` or `redis` |
| `SESSION_COOKIE_NAME` | — | `policyhub_session` | Session cookie name |
| `LOCAL_AUTH_ENABLED` | — | `false` | **Dev/staging only.** Enables `/auth/local/login`. Never `true` in production |
| `IDP_ISSUER_URL` | SSO only | — | OIDC issuer URL. E.g. `https://login.microsoftonline.com/<tenant-id>/v2.0` |
| `IDP_CLIENT_ID` | SSO only | — | Entra (or other IdP) application client ID |
| `IDP_CLIENT_SECRET` | SSO only | — | Entra application client secret |
| `IDP_CALLBACK_URL` | SSO only | — | Must match the redirect URI registered in Entra. E.g. `https://policyhub.yourco.com/auth/sso/callback` |
| `IDP_GROUPS_CLAIM` | — | `groups` | ID token claim name containing group IDs. Entra default: `groups` |

</details>

<details>
<summary><strong>GitLab content repository</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `GITLAB_BASE_URL` | ✅ | — | GitLab CE base URL, no trailing slash |
| `GITLAB_TOKEN` | ✅ | — | Service account PAT — `api` + `write_repository` scopes |
| `GITLAB_MERGE_TOKEN` | ✅ | — | Maintainer PAT used only for MR merge during publishing |
| `GITLAB_PROJECT_ID` | ✅ | — | Numeric project ID of the `policy-content` repository |
| `GITLAB_WEBHOOK_SECRET` | ✅ | — | Shared secret for `X-Gitlab-Token` verification |
| `GITLAB_DEFAULT_BRANCH` | — | `main` | Target branch for all MRs |
| `GITLAB_CONTENT_PATH` | — | `policies` | Root folder for policy Markdown files |
| `GITLAB_RATE_LIMIT_RPS` | — | `10` | Max requests/second to the GitLab API |

See [docs/GitLab_Setup_Guide.docx](docs/GitLab_Setup_Guide.docx) for step-by-step setup.

</details>

<details>
<summary><strong>Search — Typesense</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TYPESENSE_HOST` | ✅ | `127.0.0.1` | Typesense host |
| `TYPESENSE_PORT` | — | `8108` | Typesense port |
| `TYPESENSE_PROTOCOL` | — | `http` | `http` or `https` |
| `TYPESENSE_API_KEY` | ✅ | — | Typesense admin API key (set in `docker-compose.yml` for local dev) |

</details>

<details>
<summary><strong>AI — Anthropic</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | AI features | — | Anthropic API key. AI features degrade gracefully if absent |
| `ANTHROPIC_MODEL` | — | `claude-sonnet-4-6` | Model for chat/generation. Do not change without testing |
| `ANTHROPIC_EMBEDDING_MODEL` | — | `text-embedding-3-small` | Model for pgvector embeddings |
| `AI_BOT_RATE_LIMIT` | — | `20` | Bot requests per minute per user |
| `AI_EDITOR_RATE_LIMIT` | — | `10` | Editor assistant calls per hour per author |

</details>

<details>
<summary><strong>Mail</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `MAIL_DRIVER` | — | `logger` | `smtp` for production, `logger` for dev (prints to console), `memory` for tests |
| `MAIL_FROM` | ✅ prod | `noreply@yourcompany.com` | From address for all outbound mail |
| `SMTP_HOST` | SMTP only | — | SMTP server host |
| `SMTP_PORT` | SMTP only | `587` | SMTP port |
| `SMTP_USERNAME` | SMTP only | — | SMTP auth username |
| `SMTP_PASSWORD` | SMTP only | — | SMTP auth password |

</details>

<details>
<summary><strong>File storage — Drive</strong></summary>

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DRIVE_DRIVER` | — | `local` | `local` for dev/test, `s3` for production |
| `DRIVE_LOCAL_ROOT` | local only | `./storage` | Local storage root path |
| `AWS_S3_BUCKET` | S3 only | — | S3 bucket name for PDF storage |
| `AWS_S3_REGION` | S3 only | — | S3 region |
| `AWS_ACCESS_KEY_ID` | S3 only | — | AWS access key |
| `AWS_SECRET_ACCESS_KEY` | S3 only | — | AWS secret key |

</details>

---

## Key commands

### Development

```bash
# Start dev server with hot module replacement
node ace serve --hmr

# Build for production
node ace build

# Start production build
node server.js
```

### Database

```bash
# Run all pending migrations
node ace migration:run

# Roll back the last batch
node ace migration:rollback

# Roll back all migrations
node ace migration:rollback --batch=0

# Check migration status
node ace migration:status

# Create a new migration
node ace make:migration create_<table_name>_table
```

### Seeders

```bash
# Run all seeders (development data)
node ace db:seed

# Run a specific seeder
node ace db:seed --seeder=UsabilityM1Seeder
node ace db:seed --seeder=UsabilityM2Seeder

# Wipe and reseed (destructive — dev only)
node ace migration:rollback --batch=0 && node ace migration:run && node ace db:seed
```

### Code generation

```bash
# Make a controller
node ace make:controller <Name>Controller

# Make a model + migration together
node ace make:model <Name> && node ace make:migration create_<name>s_table

# Make a transformer (v7 first-class)
node ace make:transformer <Name>Transformer

# Make a validator
node ace make:validator <Name>

# Make a Bouncer policy
node ace make:policy <Name>Policy

# Make a queue job
node ace make:job <Name>Job

# Make a mail class
node ace make:mail <Name>Mail

# Make an event + listener pair
node ace make:event <Name>Event && node ace make:listener <Name>Listener
```

### Queue

```bash
# Start the queue worker (required for jobs to process)
node ace queue:work

# Start worker in a specific queue only
node ace queue:work --queue=publishing

# List pending jobs
node ace queue:list
```

### AI & Search

```bash
# Verify GitLab integration (run after GitLab setup)
node ace gitlab:verify

# Re-embed all published policies (use after first deploy or embedding model change)
node ace ai:embed-all

# Run the bot red team evaluation
node ace ai:red-team

# Re-index all published policies in Typesense
node ace search:reindex
```

### Testing

```bash
# Run all tests
node ace test

# Run a specific test file
node ace test tests/unit/services/GitLabService.spec.ts

# Run tests matching a pattern
node ace test --filter="auth"

# Run with coverage
node ace test --coverage
```

---

## Project structure

<details>
<summary><strong>Expand full directory tree</strong></summary>

```
policy-platform/
│
├── app/
│   ├── controllers/
│   │   ├── auth/              # SSO callback, local login, logout
│   │   ├── admin/             # Users, categories, audience groups, audit log
│   │   ├── authoring/         # Policies, editor, workflow actions
│   │   ├── portal/            # Reader portal, policy detail, history, diff
│   │   └── webhooks/          # GitLab webhook receiver
│   │
│   ├── models/                # 20 Lucid models (auto-typed after migration:run)
│   │
│   ├── services/
│   │   ├── auth/              # OIDC callback, role mapping
│   │   ├── git/               # GitLabService — all GitLab API operations
│   │   ├── workflow/          # WorkflowService — state machine
│   │   ├── publishing/        # PublishingService — HTML/PDF rendering
│   │   ├── search/            # TypesenseService — index and query
│   │   └── ai/                # AIService — change summaries, RAG, embeddings
│   │
│   ├── jobs/                  # Queue jobs (PublishPolicy, IndexPolicy, etc.)
│   ├── events/                # Event classes
│   ├── listeners/             # Event listener classes
│   ├── middleware/            # Auth, Bouncer, InertiaMiddleware, RateLimit, etc.
│   ├── policies/              # Bouncer access policies (PolicyPolicy, WorkflowPolicy)
│   ├── transformers/          # v7 response transformers (UserTransformer, etc.)
│   ├── validators/            # VineJS validators
│   └── mails/                 # Mail classes (ReviewRequestedMail, etc.)
│
├── config/                    # AdonisJS config files
│   ├── app.ts
│   ├── auth.ts
│   ├── database.ts
│   ├── drive.ts
│   ├── encryption.ts          # v7: separate from app.ts
│   ├── mail.ts
│   ├── queue.ts
│   └── redis.ts               # Points to Valkey
│
├── database/
│   ├── migrations/            # 022 migrations — run in order
│   └── seeders/               # Development and usability test seeders
│
├── inertia/                   # React frontend (v7 layout — NOT inertia/app/app.tsx)
│   ├── app.tsx                # Client entrypoint
│   ├── ssr.tsx                # SSR entrypoint
│   └── pages/
│       ├── auth/              # Login page
│       ├── admin/             # Admin surfaces
│       ├── authoring/         # Dashboard, editor, review queue, review screen
│       └── portal/            # Policy library, policy detail, history, diff
│
├── start/
│   ├── routes.ts              # All application routes
│   ├── kernel.ts              # Middleware registration
│   └── events.ts              # Event → listener bindings
│
├── tests/
│   ├── unit/                  # Service and model unit tests
│   ├── functional/            # Route/controller tests (uses loginAs())
│   └── e2e/                   # Playwright end-to-end tests
│
├── docs/                      # Design documents (see Document index below)
│
├── .adonisjs/                 # Auto-generated types — COMMIT this directory, never edit
├── .env.example               # All env vars with descriptions — commit this
├── .env.local                 # Your local secrets — NEVER commit (in .gitignore)
├── docker-compose.yml         # Local Postgres, Valkey, Typesense
├── adonisrc.ts                # AdonisJS v7 configuration
└── package.json
```

</details>

### Files to know first

| File | Why it matters |
|------|----------------|
| `start/routes.ts` | Every route in the application. Read this before adding a controller. |
| `app/services/git/GitLabService.ts` | All GitLab API calls go through here. Never call the GitLab API directly from a controller. |
| `app/services/workflow/WorkflowService.ts` | The policy workflow state machine. All state transitions go through this service. |
| `app/middleware/portal_access.ts` | Enforces RBAC on portal routes (returns 404 not 403). |
| `database/migrations/` | Read these in order to understand the full data model. |
| `.adonisjs/` | Auto-generated barrel files. Commit this directory — it powers the `#generated/*` path aliases. |

---

## Development workflow

All development follows a standard GitLab flow:

```
main (protected)
  └── feature/S1-04-entra-sso-login       ← branch per story
        └── commits
              └── MR → CI passes → review → merge to main
```

**Branch naming convention:**

```bash
# Format: <type>/<story-id>-<short-description>
feature/S2-04-tiptap-editor-core
fix/S3-05-submit-workflow-atomic-failure
chore/S1-02-project-scaffold
```

**Before raising an MR:**

```bash
# Format code
npm run format

# Type-check
npm run typecheck

# Run tests
node ace test

# Verify no migration drift
node ace migration:status
```

CI runs all of the above on every MR. A failing CI pipeline blocks merge.

---

## Testing

Tests use **Japa** (AdonisJS's built-in test runner). The key pattern for auth-gated routes is `loginAs()` — no live IdP required.

### Running tests

```bash
# All tests
node ace test

# Unit tests only
node ace test tests/unit

# Functional (route) tests only
node ace test tests/functional

# Playwright end-to-end (requires dev server running)
npx playwright test
```

### Writing a functional test

```typescript
// tests/functional/authoring/policies.spec.ts
import { test } from '@japa/runner'
import { UserFactory } from '#database/factories/UserFactory'

test.group('Policy creation', () => {
  test('author can create a draft policy', async ({ client }) => {
    // Create a user and log in as them — no IdP needed
    const user = await UserFactory.with('roles', 1, r => r.merge({ name: 'policy:author' })).create()

    const response = await client
      .post('/api/v1/policies')
      .loginAs(user)
      .json({ title: 'Test Policy', category_id: 1, description: 'A test.' })

    response.assertStatus(201)
    response.assertBodyContains({ status: 'draft' })
  })
})
```

### Test environment behaviour

| Setting | Test value | Why |
|---------|-----------|-----|
| `QUEUE_DRIVER` | `sync` | Jobs run inline — no worker needed in tests |
| `MAIL_DRIVER` | `memory` | Mail is captured, not sent |
| `LOCAL_AUTH_ENABLED` | `true` | `loginAs()` uses local auth under the hood |
| `DRIVE_DRIVER` | `local` | Files written to a temp directory, cleaned up after each test |
| `NODE_ENV` | `test` | Disables certain middleware (e.g. CSRF) that would block API tests |

These are set in `.env.test` which is committed to the repository. Do not override them locally unless you know what you're doing.

---

## Database

### Migration order

Migrations must run in order (001 → 022). The sequence is:

```
001 create_users
002 create_roles
003 create_user_roles
004 create_idp_group_role_mappings
005 create_audience_groups
006 create_user_audience_groups
007 create_categories
008 create_policies
009 create_policy_versions
010 create_workflow_instances
011 create_workflow_approvals
012 add_current_version_fk_to_policies   ← deferred FK resolving circular ref
013 create_comments
014 create_notification_preferences
015 create_notifications
016 create_policy_related_policies
017 create_vector_extension
018 create_policy_chunks
019 create_bot_interactions
020 create_bot_interaction_sources
021 create_audit_logs
022 create_search_index_queue
```

> **Migration 012** uses a deferred `ALTER TABLE` to resolve the circular foreign key between `policies` and `policy_versions`. Do not reorder migrations 008–012.

### Seeders

| Seeder | Purpose |
|--------|---------|
| `MainSeeder` | Runs all seeders in sequence (default for `db:seed`) |
| `RoleSeeder` | Creates the 6 application roles |
| `CategorySeeder` | Creates 4 default categories with approval defaults |
| `DevUserSeeder` | Creates `author@`, `reviewer@`, `admin@` test accounts |
| `SamplePolicySeeder` | Creates 2 draft policies with realistic content |
| `UsabilityM1Seeder` | M1 test gate data (3 authors, 4 categories, 2 drafts) |
| `UsabilityM2Seeder` | M2 test gate data (policy under review with diff) |

---

## Local services

All managed by `docker-compose.yml`. Start with `docker compose up -d`.

| Service | Port | What it is | Inspect |
|---------|------|-----------|---------|
| `postgres` | `5432` | PostgreSQL 16 — primary data store | `docker compose exec postgres psql -U policyhub` |
| `valkey` | `6379` | Valkey 7 (Redis-compatible) — queues and cache | `docker compose exec valkey valkey-cli ping` |
| `typesense` | `8108` | Typesense 28 — full-text search | `curl http://localhost:8108/health` |

**Reset a service:**

```bash
# Wipe and restart Postgres (loses all data)
docker compose down postgres && docker volume rm policy-platform_postgres_data
docker compose up -d postgres && node ace migration:run && node ace db:seed

# Flush Valkey (clears queues and cache)
docker compose exec valkey valkey-cli FLUSHALL

# Wipe Typesense index (reindex after)
docker compose down typesense && docker volume rm policy-platform_typesense_data
docker compose up -d typesense && node ace search:reindex
```

---

## Deployment

> A full deployment and operations runbook is tracked as a future document. The notes below cover the essentials.

**Runtime requirements:**
- Node.js 24 LTS
- PostgreSQL 16 with the `vector` extension (`CREATE EXTENSION IF NOT EXISTS vector`)
- Valkey 7 (or Redis 7.2 — but see [ADR-004](docs/PolicyHub_ADRs.docx) on why Valkey is preferred)
- Typesense 28 with persistent volume

**Build and start:**

```bash
node ace build
node server.js
```

**Process management:** Use PM2 or systemd to manage the Node process and the queue worker as separate processes:

```bash
# Application server
node server.js

# Queue worker (must run alongside the app server)
node ace queue:work
```

**Entra app registration:** Before first production deployment, an IT admin must complete the Entra application registration and provide the values for `IDP_ISSUER_URL`, `IDP_CLIENT_ID`, and `IDP_CLIENT_SECRET`. This has IT lead time — raise it early. See Sprint 1 story S1-04 in the sprint breakdown document.

---

## Document index

All design documents for this project live in the `docs/` directory.

| Document | Description |
|----------|-------------|
| [Architecture & Stack](docs/policy-platform-architecture.md) | Technology choices, system components, data flow |
| [Licensing Analysis](docs/policy-platform-licensing.md) | Licence review for all dependencies |
| [Implementation Flow](docs/policy-platform-implementation-flow.md) | 5 milestones, 130-day plan, go/no-go gates |
| [Database Schema & API](docs/policy-platform-schema-api.md) | Full schema (22 tables), API route reference |
| [Project Structure](docs/policy-platform-project-structure.md) | AdonisJS v7 scaffold, path aliases, key v6→v7 differences |
| [UX Specification](docs/PolicyHub_UX_Spec.pdf) | Annotated wireframes for all 8 screens with design decisions |
| [Architecture Decision Records](docs/PolicyHub_ADRs.docx) | 10 ADRs covering all major technical decisions |
| [Sprint Breakdown](docs/PolicyHub_Sprints.docx) | 10 sprints, ~80 stories with acceptance criteria and estimates |
| [GitLab Setup Guide](docs/PolicyHub_GitLab_Setup.docx) | Step-by-step content repository configuration |

---

## Contributing

### Commit message convention

```
<type>(<scope>): <description>

Types: feat, fix, chore, docs, test, refactor, perf
Scope: auth, editor, workflow, publishing, portal, bot, admin, infra

# Examples:
feat(workflow): add resubmit action with new AI summary generation
fix(editor): resolve auto-save race condition on rapid keystrokes
chore(infra): update Valkey from 7.2 to 7.4
test(portal): add RBAC leakage tests for audience group filtering
```

### MR checklist

Before marking an MR ready for review:

- [ ] Story acceptance criteria all met (reference story ID in MR description)
- [ ] New code has corresponding tests (`node ace test` passes)
- [ ] `npm run typecheck` passes with no errors
- [ ] No new environment variables added without updating `.env.example`
- [ ] No new dependencies added without checking licence compatibility (see [Licensing Analysis](docs/policy-platform-licensing.md))
- [ ] Migration rollback tested if a migration is included
- [ ] `LOCAL_AUTH_ENABLED=true` not referenced outside of conditional guards

### Adding a new environment variable

1. Add it to `.env.example` with a description comment
2. Add it to the [Environment variables](#environment-variables) table in this README
3. Add it to the CI secrets configuration
4. If it is sensitive (token, key, password), add it to the team password manager and document the rotation procedure

---

*Questions or issues with this setup? Open an issue in this repository or post in #policyhub-dev.*
