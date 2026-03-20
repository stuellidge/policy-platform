# CLAUDE.md — PolicyHub

This file tells Claude Code how to work in this repository. Read it before
writing any code, generating any files, or suggesting any commands.

---

## What This Repository Is

**PolicyHub** is a git-backed policy management platform. Policy documents
are stored as Markdown files in GitLab. The application provides:

- A non-technical authoring surface (TipTap WYSIWYG editor)
- A structured approval workflow (mirroring GitLab MRs)
- A role-filtered reader portal with full-text search
- An AI policy bot (RAG over published policies)
- An AI editor assistant (draft, check, suggest)

**Current state:** The `docs/specification/` directory contains the complete
design. No application code exists yet. Development follows the 5-milestone
plan in `docs/specification/policy-platform-implementation-flow.md`.

---

## Specification Documents

Before implementing anything, read the relevant spec:

| Document | Read when… |
|----------|-----------|
| `docs/specification/policy-platform-architecture.md` | Understanding system design, tech choices, component boundaries |
| `docs/specification/policy-platform-project-structure.md` | Creating files, running ace commands, understanding v7 conventions |
| `docs/specification/policy-platform-schema-api.md` | Working on database, models, migrations, or API routes |
| `docs/specification/policy-platform-implementation-flow.md` | Understanding milestone scope and go/no-go gates |
| `docs/specification/README.md` | Setting up locally for the first time |
| `docs/specification/.env.example` | Understanding required environment variables |
| `docs/specification/docker-compose.yml` | Local service configuration |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend framework | AdonisJS v7 (TypeScript, Node.js ≥ 24, npm ≥ 11) |
| Frontend | React + Inertia (SSR enabled) |
| Database | PostgreSQL 16 + pgvector extension |
| Cache / Queue | Valkey 7 (Redis-compatible) via BullMQ |
| Search | Typesense 28 |
| Git backend | GitLab CE (self-hosted recommended) or GitHub |
| Auth | OIDC (Entra ID primary, pluggable) via AdonisJS auth |
| Authorization | Bouncer (AdonisJS) |
| AI / LLM | Anthropic Claude API (`claude-sonnet-4-6`) |
| RAG pipeline | LlamaIndex (TypeScript) + pgvector |
| Editor | TipTap (ProseMirror-based) |
| Diff viewer | Monaco Editor (diff mode) |
| ORM | Lucid (AdonisJS) |
| Testing | Japa (AdonisJS built-in) |
| Mail | AdonisJS Mail (Resend / SendGrid) |

---

## AdonisJS v7 — Critical Conventions

The project uses **AdonisJS v7**, which has significant breaking changes from
v6. Violating these conventions causes runtime or type errors.

### Never do these things

```
# ❌ Wrong — installs without configuring
npm install @adonisjs/mail

# ✅ Correct — installs AND configures in one step
node ace add @adonisjs/mail
```

```
# ❌ Wrong — hand-writing files that have generators
# Creating app/controllers/foo_controller.ts manually

# ✅ Correct — always use the ace generator
node ace make:controller foo
```

```typescript
// ❌ Removed in v7
import { Request, Response } from '@adonisjs/core/http'
router.makeUrl('route.name', { id })
flashMessages.get('errors.email')
getDirname()

// ✅ v7 replacements
import { HttpRequest, HttpResponse } from '@adonisjs/core/http'
urlFor('route.name', { id })
flashMessages.get('inputErrorsBag.email')
import.meta.dirname
```

```typescript
// ❌ Old test glob syntax (v6)
files: ['tests/**/*.spec(.ts|.js)']

// ✅ v7 Node.js built-in glob syntax
files: ['tests/**/*.spec.{ts,js}']
```

### HTTP method spoofing

HTML forms only support `GET` and `POST`. To send `PUT`, `PATCH`, or `DELETE`
from a form you must use method spoofing. Two things are required:

**1. Enable it in `config/app.ts` — it is `false` by default:**

```typescript
// config/app.ts
export const http = defineConfig({
  allowMethodSpoofing: true,
})
```

**2. Put `_method` in the query string — NOT as a hidden form field:**

```tsx
{/* ✅ Correct — _method in the query string */}
<form method="POST" action={`/api/v1/policies/${id}?_method=PUT`}>

{/* ❌ Wrong — hidden field is silently ignored */}
<form method="POST" action={`/api/v1/policies/${id}`}>
  <input type="hidden" name="_method" value="PUT" />
```

The source form method must be `POST` — spoofing does not apply to `GET`.
`request.method()` returns the spoofed method; `request.intended()` returns
the original `POST`.

### Always use ace generators

| To create | Command |
|-----------|---------|
| Controller | `node ace make:controller <name>` |
| Model | `node ace make:model <name>` |
| Migration | `node ace make:migration <name>` |
| Transformer | `node ace make:transformer <name>` |
| Middleware | `node ace make:middleware <name>` |
| Validator | `node ace make:validator <name>` |
| Service | `node ace make:service <name>` |
| Event | `node ace make:event <name>` |
| Listener | `node ace make:listener <name> --event=<event>` |
| Mail | `node ace make:mail <name>` |
| Policy (Bouncer) | `node ace make:policy <name> --resource-model=<Model>` |
| Exception | `node ace make:exception <name>` |
| Ace command | `node ace make:command <name>` |
| Test | `node ace make:test <name> --suite=unit\|functional` |
| Job | `node ace make:job <name>` |
| Seeder | `node ace make:seeder <name>` |
| Factory | `node ace make:factory <name> --model=<model>` |

### Key v7 concepts

**Models:** After `node ace migration:run`, column definitions are
auto-generated into each model. Do NOT write `@column()` decorators for
schema columns manually — define relationships, computed properties, and
hooks only.

**Transformers:** v7 formalises model serialisation. Always use
`node ace make:transformer` instead of ad-hoc object mapping. Transformer
output types flow automatically into `.adonisjs/client/data.d.ts`.

**`.adonisjs/` directory:** Auto-generated by the framework at build time.
Commit it to version control. Never edit files inside it.

**Path aliases:** Use `#controllers/*`, `#services/*`, etc. — never relative
imports. Aliases are defined in `package.json` `imports`.

**Routes:** Use explicit lazy imports (not the barrel pattern) for readability
in route groups. Every route gets an `.as()` name for type-safe `urlFor()`.

**InertiaMiddleware:** Shared data (auth user, flash messages, validation
errors) lives in `app/middleware/inertia_middleware.ts`, not `config/inertia.ts`.

**Encryption:** Config is in `config/encryption.ts` (not `config/app.ts`).
Use the `legacy` driver for new apps; upgrade to `aes256gcm` in production.

---

## Project Structure Quick Reference

```
app/
  controllers/         # auth/ | admin/ | authoring/ | portal/ | webhooks/
  models/              # Lucid ORM models (20 planned)
  transformers/        # Typed serialisation (v7 first-class)
  services/            # auth/ | git/ | workflow/ | publishing/ | search/ | ai/
  jobs/                # Async queue jobs
  events/              # Class-based events
  listeners/           # Event listeners
  middleware/          # Auth, Bouncer init, Inertia, require_role, etc.
  policies/            # Bouncer authorization classes
  validators/          # VineJS schemas
  mails/               # Mail classes
config/                # Framework config (app, auth, database, inertia, etc.)
database/
  migrations/          # 22 migrations (timestamp-prefixed, run in order)
  seeders/             # role, audience_group, dev
  factories/           # user, policy, workflow_instance
start/
  routes.ts            # All routes with explicit lazy controller imports
  kernel.ts            # Middleware registration
  events.ts            # Event→listener bindings
  env.ts               # Validated env vars
inertia/               # React frontend
  app.tsx              # Entry point (v7: root of inertia/, not inertia/app/)
  ssr.tsx              # SSR entry
  pages/               # auth/ | admin/ | authoring/ | portal/
  components/          # editor/ | diff/ | workflow/ | portal/ | bot/
  layouts/             # admin_layout.tsx | portal_layout.tsx
.adonisjs/             # Auto-generated types — commit, never edit
tests/
  unit/
  functional/
```

---

## Data Ownership: GitLab vs PostgreSQL

**GitLab owns:**
- Markdown content, file history, branches, MRs, diffs, MR-level comments, commit SHAs

**PostgreSQL owns:**
- User profiles, roles, audience groups
- Policy metadata (category, owner, review date, audience tags)
- Workflow state (enriched mirror of GitLab MR state)
- Rendered HTML, AI embeddings (pgvector), audit logs
- Notifications, bot interactions, sessions

Never store in PostgreSQL what GitLab already owns. Join the two systems via
`gitlab_mr_iid` and `gitlab_file_path`.

---

## RBAC Overview

**Authoring roles** (who can draft/review/approve):
- `policy:author` — create drafts, submit for review
- `policy:reviewer` — comment, request changes on MRs
- `policy:approver:l1` — first-level approval (manager)
- `policy:approver:l2` — final approval (committee)
- `policy:admin` — manage categories, assign roles, publish

**Reader access:** Policies are tagged with `audience` groups (e.g.,
`all-staff`, `finance-team`). A user sees only policies where their groups
intersect the policy's audience tags. Search is always role-filtered — no
query can surface policies a user is not permitted to see.

---

## Workflow State Machine

```
DRAFT → SUBMITTED → UNDER_REVIEW → APPROVED_L1 → APPROVED_FINAL → PUBLISHED
                         ↓                ↓               ↓
                     CHANGES_REQUESTED  REJECTED      WITHDRAWN
                         ↓
                       DRAFT
```

| Workflow State | GitLab equivalent |
|----------------|------------------|
| DRAFT | Branch exists, no MR |
| SUBMITTED | MR opened (draft) |
| UNDER_REVIEW | MR open, reviewer assigned |
| APPROVED_L1 | MR has 1 required approval |
| APPROVED_FINAL | MR has all required approvals |
| PUBLISHED | MR merged to main |

---

## Environment Variables

Minimum required to start locally (see `docs/specification/.env.example`
for the full list):

```bash
APP_KEY=          # 32-byte base64 — generate with: node ace generate:key
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USER=policyhub
DB_PASSWORD=policyhub
DB_DATABASE=policyhub
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
SESSION_DRIVER=cookie
TYPESENSE_HOST=localhost
TYPESENSE_PORT=8108
TYPESENSE_API_KEY=local-dev-typesense-key
```

For local auth during development:
```bash
LOCAL_AUTH_ENABLED=true
```

For AI features (optional — degrade gracefully if absent):
```bash
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-sonnet-4-6
```

For SSO (required in production):
```bash
IDP_ISSUER_URL=
IDP_CLIENT_ID=
IDP_CLIENT_SECRET=
IDP_CALLBACK_URL=
```

For GitLab integration:
```bash
GITLAB_BASE_URL=
GITLAB_TOKEN=
GITLAB_PROJECT_ID=
GITLAB_WEBHOOK_SECRET=
```

---

## Local Development Setup

```bash
# 1. Install dependencies
npm install

# 2. Start services (Postgres, Valkey, Typesense)
docker compose up -d

# 3. Create .env from example and fill in required vars
cp docs/specification/.env.example .env

# 4. Run migrations (also triggers model schema generation)
node ace migration:run

# 5. Seed the database
node ace db:seed

# 6. Start dev server with hot reload
node ace serve --hmr
```

Default local service ports:
- App: `http://localhost:3333`
- PostgreSQL: `5432` (user: policyhub, pw: policyhub)
- Valkey: `6379`
- Typesense: `8108`

Default test users (after `db:seed`):
- `author@example.com` / `password`
- `reviewer@example.com` / `password`
- `admin@example.com` / `password`

---

## Common Development Commands

```bash
# Dev server
node ace serve --hmr

# Migrations
node ace migration:run
node ace migration:rollback
node ace migration:status

# Seeding
node ace db:seed
node ace db:seed --files=database/seeders/dev_seeder.ts

# Tests
node ace test
node ace test --suite=unit
node ace test --suite=functional
node ace test --files=tests/functional/policies/workflow.spec.ts

# Routes
node ace list:routes

# Queue worker (separate process)
node ace queue:listen

# Production build
node ace build

# Type check
npx tsc --noEmit

# Lint / format
npm run lint
npm run format
```

CI gate (must pass before pushing):
```bash
npm run format && npx tsc --noEmit && node ace test && node ace migration:status
```

---

## Testing Patterns

Use `loginAs()` — never mock auth middleware or call live IdPs in tests:

```typescript
const user = await UserFactory
  .with('roles', 1, r => r.merge({ name: 'policy:author' }))
  .create()

await client
  .post('/api/v1/policies')
  .loginAs(user)
  .json({ title: 'Test Policy' })
  .assertStatus(201)
```

Test suites:
- `unit` — services and validators (no HTTP, no database preferred)
- `functional` — route/controller tests (database, no live IdP or GitLab)
- `e2e` — Playwright end-to-end (optional, runs against a live dev server)

---

## AI Service Notes

- AI calls are always server-side — never expose `ANTHROPIC_API_KEY` to the browser
- The policy bot answers **only** from retrieved context chunks, never from training knowledge
- If confidence is below threshold, return "I couldn't find a policy that covers this"
- All bot responses must include source citations (policy name, section, link)
- Bot responses are logged to `bot_interactions` for quality review
- AI features degrade gracefully when `ANTHROPIC_API_KEY` is absent

---

## Milestone Scope Summary

| Milestone | Days | Deliverable | Who tests |
|-----------|------|-------------|-----------|
| M1 | 1–20 | Auth + TipTap editor + GitLab branch save | Policy author |
| M2 | 21–45 | Workflow + MR review + diff viewer | Reviewer + manager |
| M3 | 46–70 | Publishing pipeline (HTML/PDF + search index) | Committee + owner |
| M4 | 71–95 | Reader portal + RBAC + full-text search | All-staff pilot |
| M5 | 96–130 | AI bot (RAG) + editor assistant + change summary | Power users |

Each milestone ends with a **go/no-go gate** — real users test it before
the next milestone begins. Do not start M2 work until M1 is human-validated.

---

## What NOT to Do

- Do not re-implement git features (versioning, diffing, branch management) — GitLab does these
- Do not write `@column()` decorators manually in models — they are auto-generated after `migration:run`
- Do not edit files in `.adonisjs/` — they are auto-generated
- Do not use `router.makeUrl()` — use `urlFor()` instead
- Do not use `Request`/`Response` imports — use `HttpRequest`/`HttpResponse`
- Do not use relative imports — use `#path-alias/*` imports
- Do not hand-write files that have `node ace make:*` generators
- Do not call the Claude API from the browser — all AI calls are server-side
- Do not store policy Markdown content in PostgreSQL — GitLab owns it
- Do not skip the CI gate (`format + typecheck + test + migration:status`) before pushing
- Do not put `_method` in a hidden form field — it must be in the query string (`?_method=PUT`), and `allowMethodSpoofing: true` must be set in `config/app.ts`
