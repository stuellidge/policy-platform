# Policy Library Platform — AdonisJS v7 Project Structure & Scaffold Guide

## Prerequisites

AdonisJS v7 requires **Node.js ≥ 24** and **npm ≥ 11**. Verify both before starting:

```bash
node -v   # Must be v24.x or higher
npm -v    # Must be v11.x or higher
```

Ensure these versions are set in CI pipelines and production servers as well as
locally — mismatches cause build failures. Node.js 24 became the LTS version
in October 2025 and the v7 framework takes advantage of its native APIs
(built-in glob, `crypto.randomUUID`, `util.parseEnv`, `import.meta.dirname`).

---

## Key v7 Principles

These shape every decision in this document:

- **`node ace add <package>`** installs *and* configures in one command. Never `npm install` an AdonisJS package alone.
- **`node ace make:*`** generates every file that has a generator. Never hand-write controllers, models, migrations, validators, services, events, listeners, policies, transformers, mails, or tests.
- **Path aliases** (`#controllers/`, `#transformers/`, `#generated/`, etc.) replace all relative imports, defined in `package.json` `imports`.
- **Direct controller imports in routes** — no magic strings.
- **ESM throughout** — no `require()`.
- **`HttpRequest` / `HttpResponse`** — v7 renamed `Request` → `HttpRequest` and `Response` → `HttpResponse` to avoid conflicts with the platform-native `Request`/`Response` globals.
- **`urlFor()`** replaces `router.makeUrl()` — the new type-safe URL builder, works on both server and client.
- **Hooks in `adonisrc.ts`** — v7 introduces a hooks system for build-time code generation. `node ace add` wires these automatically, but the configuration must be reviewed after each package install.
- **Transformers are first-class** — v7 formalises model serialisation into `app/transformers/`. Use `node ace make:transformer` rather than ad-hoc object mapping. Transformer output types flow automatically into `.adonisjs/client/data.d.ts` for the frontend.
- **`.adonisjs/` is generated, never edited** — the framework writes TypeScript type definitions here at build time. Commit `.adonisjs/` to version control so types are available without a build step.

---

## What Changed from v6 (Summary)

For reference when reading the rest of this document:

| Area | v6 | v7 |
|---|---|---|
| Node.js minimum | 20 | **24** |
| npm minimum | 8 | **11** |
| Init command | `npm init adonisjs@latest` | **`npm create adonisjs@latest`** |
| React kit flag | `--kit=inertia --adapter=react` | **`--kit=react`** (React baked in) |
| Default database | Postgres via `--db=postgres` | **SQLite — configure Postgres post-creation** |
| TypeScript JIT | `ts-node` | **`@poppinss/ts-exec`** (auto-replaced by init) |
| `youch` | Bundled | **Must install separately: `npm install -D youch`** |
| `adonisrc.ts` | `assetsBundler`, `onBuildStarting` | **Hooks system: `buildStarting`, `fileChanged`, etc.** |
| Inertia entrypoints | `inertia/app/app.tsx` | **`inertia/app.tsx`** (moved up one level) |
| Inertia shared data | `config/inertia.ts` `sharedData` | **`InertiaMiddleware` class** |
| Inertia config | `history.encrypt`, `entrypoint` | **`encryptHistory`, no `entrypoint`** |
| Circular type refs | N/A | **`tsconfig.inertia.json` required at root** |
| Encryption config | `appKey` in `config/app.ts` | **`config/encryption.ts`** (separate file) |
| URL generation | `router.makeUrl()` | **`urlFor()` from `@adonisjs/core/services/url_builder`** |
| Controller imports | Explicit lazy imports only | **Barrel (`#generated/controllers`) or lazy — both valid** |
| HTTP classes | `Request`, `Response` | **`HttpRequest`, `HttpResponse`** |
| Flash errors key | `flashMessages.get('errors.x')` | **`flashMessages.get('inputErrorsBag.x')`** |
| `getDirname()` helper | Available | **Removed — use `import.meta.dirname`** |
| Transformers | Ad-hoc (no generator) | **`node ace make:transformer` — first-class** |
| Test glob syntax | `(.ts\|.js)` | **`.{ts,js}`** (Node.js built-in glob) |
| Lucid schema | Manually typed `@column()` decorators | **Auto-generated after `migration:run`** |
| Starter kit auth | No login/signup scaffold | **Basic login + signup pages included** |

---

## Step 1: Project Initialisation

The correct v7 command is `npm create`, not `npm init`:

```bash
npm create adonisjs@latest policy-platform -- --kit=react
```

In v7 the React kit is a standalone named kit — there is no separate `--adapter`
flag. The `--kit=react` value selects Inertia + React + SSR as a single
pre-configured unit. SSR is included and wired by default; no separate flag is
needed.

Note the double `--` before `--kit=react` — npm requires this to pass flags
through to the `create-adonisjs` initialiser rather than consuming them itself.

This command performs the following automatically:
1. Scaffolds the base application
2. Runs `npm install`
3. Generates `APP_KEY`
4. Configures `@adonisjs/lucid` — **defaulting to SQLite**
5. Configures `@adonisjs/auth` (session guard) — **including basic login and
   signup page scaffolding**, which makes Milestone 1 local auth testing viable
   with no extra work
6. Configures `@adonisjs/inertia` (React + SSR) and wires `adonisrc.ts` hooks
7. Creates `tsconfig.inertia.json` and `config/encryption.ts` (v7 new files)

**Switching to PostgreSQL** — the React kit scaffolds with SQLite by default.
Switch to Postgres by updating `config/database.ts` and installing the driver:

```bash
npm install pg
```

```typescript
// config/database.ts
export default defineConfig({
  connection: 'postgres',
  connections: {
    postgres: {
      client: 'pg',
      connection: {
        host: env.get('DB_HOST', '127.0.0.1'),
        port: env.get('DB_PORT', 5432),
        user: env.get('DB_USER'),
        password: env.get('DB_PASSWORD'),
        database: env.get('DB_DATABASE'),
      },
    },
  },
})
```

After init, install `youch` — it is no longer bundled:

```bash
npm install -D youch
```

---

## Step 2: Install & Configure All Required Packages

```bash
node ace add @adonisjs/bouncer
node ace add @adonisjs/mail
node ace add @adonisjs/drive
node ace add @adonisjs/redis
node ace add @adonisjs/queue
node ace add @adonisjs/limiter
```

After all packages are installed, the `hooks` section of `adonisrc.ts` should
resemble:

```typescript
// adonisrc.ts
import { indexEntities } from '@adonisjs/core'
import { indexPages } from '@adonisjs/inertia'
import { indexPolicies } from '@adonisjs/bouncer'
import { defineConfig } from '@adonisjs/core/app'

export default defineConfig({
  hooks: {
    init: [
      indexEntities(),                     // Always required in v7
      indexPages({ framework: 'react' }),  // Inertia: scans pages, generates types
      indexEntities({                      // Transformer type generation
        transformers: { enabled: true, withSharedProps: true },
      }),
      indexPolicies(),                     // Bouncer: indexes policy classes
    ],
    buildStarting: [
      () => import('@adonisjs/vite/build_hook'),  // Vite production build step
    ],
  },
})
```

If any `node ace add` command does not update the hooks correctly, add
the missing entry manually — the docs for each package show the required hook.

---

## Step 3: Complete Folder Structure

`← node ace make:...` = generated by command, never hand-written.
`← generated by add/init` = created during package installation.

```
policy-platform/
│
├── ace.js                          # Ace entry point — never edit directly
├── adonisrc.ts                     # App config + v7 hooks
├── package.json                    # Path aliases in "imports" field
├── tsconfig.json                   # Root TS config; references tsconfig.inertia.json
├── tsconfig.inertia.json           ← generated by init (v7 — prevents circular refs)
├── eslint.config.js
├── vite.config.ts
├── .env
├── .env.example
│
├── .adonisjs/                      # Auto-generated types — commit, never edit
│   ├── server/
│   │   └── pages.d.ts              # Inertia page prop types (from page components)
│   └── client/
│       └── data.d.ts               # Transformer output types (for frontend)
│
├── bin/
│   ├── console.ts
│   ├── server.ts
│   └── test.ts
│
├── app/
│   │
│   ├── controllers/
│   │   ├── auth/
│   │   │   └── oidc_controller.ts          ← node ace make:controller auth/oidc
│   │   │   # Basic login/register controllers already generated by init.
│   │   │   # oidc_controller handles the IdP redirect/callback flow.
│   │   ├── admin/
│   │   │   ├── users_controller.ts         ← node ace make:controller admin/users
│   │   │   ├── categories_controller.ts    ← node ace make:controller admin/categories
│   │   │   ├── audience_groups_controller.ts ← node ace make:controller admin/audience_groups
│   │   │   ├── idp_mappings_controller.ts  ← node ace make:controller admin/idp_mappings
│   │   │   ├── audit_logs_controller.ts    ← node ace make:controller admin/audit_logs
│   │   │   └── bot_interactions_controller.ts ← node ace make:controller admin/bot_interactions
│   │   ├── authoring/
│   │   │   ├── policies_controller.ts      ← node ace make:controller authoring/policies
│   │   │   ├── content_controller.ts       ← node ace make:controller authoring/content
│   │   │   ├── workflow_controller.ts      ← node ace make:controller authoring/workflow
│   │   │   └── comments_controller.ts      ← node ace make:controller authoring/comments
│   │   ├── portal/
│   │   │   ├── policies_controller.ts      ← node ace make:controller portal/policies
│   │   │   ├── categories_controller.ts    ← node ace make:controller portal/categories
│   │   │   ├── search_controller.ts        ← node ace make:controller portal/search
│   │   │   └── bot_controller.ts           ← node ace make:controller portal/bot
│   │   └── webhooks/
│   │       └── gitlab_controller.ts        ← node ace make:controller webhooks/gitlab
│   │
│   ├── models/
│   │   │   # v7: after migration:run, column definitions are auto-generated
│   │   │   # into the model. Define relationships, computed properties, and
│   │   │   # hooks — not @column() decorators for schema columns.
│   │   │
│   │   ├── user.ts                         ← node ace make:model user
│   │   ├── role.ts                         ← node ace make:model role
│   │   ├── user_role.ts                    ← node ace make:model user_role
│   │   ├── idp_group_role_mapping.ts       ← node ace make:model idp_group_role_mapping
│   │   ├── audience_group.ts               ← node ace make:model audience_group
│   │   ├── user_audience_group.ts          ← node ace make:model user_audience_group
│   │   ├── category.ts                     ← node ace make:model category
│   │   ├── policy.ts                       ← node ace make:model policy
│   │   ├── policy_version.ts               ← node ace make:model policy_version
│   │   ├── policy_audience_group.ts        ← node ace make:model policy_audience_group
│   │   ├── policy_related_policy.ts        ← node ace make:model policy_related_policy
│   │   ├── workflow_instance.ts            ← node ace make:model workflow_instance
│   │   ├── workflow_reviewer.ts            ← node ace make:model workflow_reviewer
│   │   ├── workflow_approval.ts            ← node ace make:model workflow_approval
│   │   ├── comment.ts                      ← node ace make:model comment
│   │   ├── notification.ts                 ← node ace make:model notification
│   │   ├── audit_log.ts                    ← node ace make:model audit_log
│   │   ├── policy_chunk.ts                 ← node ace make:model policy_chunk
│   │   ├── bot_interaction.ts              ← node ace make:model bot_interaction
│   │   └── bot_interaction_source.ts       ← node ace make:model bot_interaction_source
│   │
│   ├── transformers/                       # v7 first-class serialisation layer
│   │   │   # Convert models to typed JSON. Output types flow to frontend
│   │   │   # automatically via .adonisjs/client/data.d.ts.
│   │   │
│   │   ├── user_transformer.ts             ← node ace make:transformer user
│   │   ├── policy_transformer.ts           ← node ace make:transformer policy
│   │   ├── policy_version_transformer.ts   ← node ace make:transformer policy_version
│   │   ├── workflow_instance_transformer.ts ← node ace make:transformer workflow_instance
│   │   └── bot_interaction_transformer.ts  ← node ace make:transformer bot_interaction
│   │
│   ├── middleware/
│   │   ├── auth_middleware.ts              ← generated by init
│   │   ├── initialize_bouncer_middleware.ts ← generated by `add @adonisjs/bouncer`
│   │   ├── inertia_middleware.ts           ← node ace make:middleware inertia_middleware
│   │   │   # v7: shared data (authenticated user, flash messages, validation
│   │   │   # errors) lives here, not in config/inertia.ts.
│   │   │   # The init starter kit generates a base version; customise for our
│   │   │   # UserTransformer and role data.
│   │   ├── require_role_middleware.ts      ← node ace make:middleware require_role
│   │   ├── portal_access_middleware.ts     ← node ace make:middleware portal_access
│   │   └── webhook_secret_middleware.ts    ← node ace make:middleware webhook_secret
│   │
│   ├── validators/
│   │   ├── policy_validator.ts             ← node ace make:validator policy
│   │   ├── workflow_validator.ts           ← node ace make:validator workflow
│   │   ├── comment_validator.ts            ← node ace make:validator comment
│   │   └── admin_validator.ts              ← node ace make:validator admin
│   │   # Auth validators generated by init as part of login/signup scaffold
│   │
│   ├── services/
│   │   ├── auth/
│   │   │   └── sync_user_service.ts        ← node ace make:service auth/sync_user
│   │   │       # Single shared post-login method called by both OIDC callback
│   │   │       # and local auth login. Resolves roles and audience groups.
│   │   ├── git/
│   │   │   └── gitlab_service.ts           ← node ace make:service git/gitlab
│   │   ├── workflow/
│   │   │   └── workflow_service.ts         ← node ace make:service workflow/workflow
│   │   ├── publishing/
│   │   │   ├── template_service.ts         ← node ace make:service publishing/template
│   │   │   ├── rendering_service.ts        ← node ace make:service publishing/rendering
│   │   │   └── pdf_service.ts              ← node ace make:service publishing/pdf
│   │   ├── search/
│   │   │   └── typesense_service.ts        ← node ace make:service search/typesense
│   │   └── ai/
│   │       ├── embedding_service.ts        ← node ace make:service ai/embedding
│   │       ├── change_summary_service.ts   ← node ace make:service ai/change_summary
│   │       └── bot_service.ts              ← node ace make:service ai/bot
│   │
│   ├── jobs/
│   │   ├── publishing_job.ts               ← node ace make:job publishing
│   │   ├── ai_change_summary_job.ts        ← node ace make:job ai_change_summary
│   │   ├── index_policy_job.ts             ← node ace make:job index_policy
│   │   └── send_notification_job.ts        ← node ace make:job send_notification
│   │
│   ├── events/
│   │   ├── policy_submitted.ts             ← node ace make:event policy_submitted
│   │   ├── policy_approved.ts              ← node ace make:event policy_approved
│   │   ├── policy_published.ts             ← node ace make:event policy_published
│   │   └── comment_added.ts                ← node ace make:event comment_added
│   │
│   ├── listeners/
│   │   ├── notify_reviewers.ts             ← node ace make:listener notify_reviewers \
│   │   │                                        --event=policy_submitted
│   │   ├── notify_approvers.ts             ← node ace make:listener notify_approvers \
│   │   │                                        --event=policy_approved
│   │   ├── notify_published.ts             ← node ace make:listener notify_published \
│   │   │                                        --event=policy_published
│   │   └── queue_ai_summary.ts             ← node ace make:listener queue_ai_summary \
│   │                                            --event=policy_submitted
│   │
│   ├── policies/
│   │   ├── main.ts                         ← generated by `add @adonisjs/bouncer`
│   │   ├── policy_policy.ts                ← node ace make:policy policy \
│   │   │                                        --resource-model=Policy
│   │   └── workflow_policy.ts              ← node ace make:policy workflow \
│   │                                            --resource-model=WorkflowInstance
│   │
│   ├── abilities/
│   │   └── main.ts                         ← generated by `add @adonisjs/bouncer`
│   │
│   ├── exceptions/
│   │   ├── handler.ts                      ← generated by framework
│   │   └── workflow_exception.ts           ← node ace make:exception workflow
│   │
│   └── mails/
│       ├── review_requested_mail.ts        ← node ace make:mail review_requested
│       ├── changes_requested_mail.ts       ← node ace make:mail changes_requested
│       ├── policy_approved_mail.ts         ← node ace make:mail policy_approved
│       └── policy_published_mail.ts        ← node ace make:mail policy_published
│
├── config/
│   ├── app.ts                              ← generated (no appKey export in v7)
│   ├── encryption.ts                       ← generated by init (v7 — dedicated file)
│   │   # Uses the 'legacy' driver for new apps to maintain forward-compatibility.
│   │   # Upgrade to 'aes256gcm' driver once the app is in production.
│   ├── auth.ts                             ← generated by init
│   ├── database.ts                         ← generated by init
│   ├── inertia.ts                          ← generated by init
│   │   # v7: no sharedData, no entrypoint. Use encryptHistory: true (not history.encrypt).
│   ├── mail.ts                             ← generated by `add @adonisjs/mail`
│   ├── drive.ts                            ← generated by `add @adonisjs/drive`
│   ├── redis.ts                            ← generated by `add @adonisjs/redis`
│   ├── queue.ts                            ← generated by `add @adonisjs/queue`
│   └── limiter.ts                          ← generated by `add @adonisjs/limiter`
│
├── database/
│   ├── migrations/
│   │   ├── 001_create_users_table.ts       ← node ace make:migration create_users_table
│   │   └── ... (022 total, per schema doc)
│   │
│   ├── seeders/
│   │   ├── role_seeder.ts                  ← node ace make:seeder role
│   │   ├── audience_group_seeder.ts        ← node ace make:seeder audience_group
│   │   └── dev_seeder.ts                   ← node ace make:seeder dev
│   │
│   └── factories/
│       ├── user_factory.ts                 ← node ace make:factory user --model=user
│       ├── policy_factory.ts               ← node ace make:factory policy --model=policy
│       └── workflow_instance_factory.ts    ← node ace make:factory workflow_instance \
│                                                --model=workflow_instance
│
├── start/
│   ├── routes.ts
│   ├── kernel.ts
│   ├── events.ts
│   └── env.ts
│
├── resources/
│   └── views/
│       └── inertia_layout.edge             ← generated by init
│
├── inertia/                                # React frontend
│   │   # v7 structure: entrypoints at root of inertia/, not inertia/app/
│   │
│   ├── app.tsx                             ← generated by init (was inertia/app/app.tsx in v6)
│   ├── ssr.tsx                             ← generated by init (was inertia/app/ssr.tsx in v6)
│   ├── client.ts                           ← generated by init (Tuyau type-safe client setup)
│   ├── tsconfig.json                       ← generated by init
│   ├── types.ts
│   ├── css/
│   │   └── app.css
│   │
│   ├── layouts/
│   │   ├── admin_layout.tsx
│   │   └── portal_layout.tsx
│   │
│   ├── components/
│   │   ├── editor/
│   │   │   ├── policy_editor.tsx
│   │   │   ├── editor_toolbar.tsx
│   │   │   └── template_picker.tsx
│   │   ├── diff/
│   │   │   ├── monaco_diff_viewer.tsx
│   │   │   └── rendered_diff_viewer.tsx
│   │   ├── workflow/
│   │   │   ├── workflow_timeline.tsx
│   │   │   └── approval_actions.tsx
│   │   ├── portal/
│   │   │   ├── policy_card.tsx
│   │   │   ├── category_tree.tsx
│   │   │   └── search_bar.tsx
│   │   └── bot/
│   │       ├── policy_bot.tsx
│   │       ├── bot_message.tsx
│   │       └── bot_feedback.tsx
│   │
│   └── pages/
│       │   # v7: prop types inferred from component definitions by the assembler
│       │   # hook and stored in .adonisjs/server/pages.d.ts. inertia.render()
│       │   # is type-safe — TypeScript will catch mismatched props at compile time.
│       │
│       ├── auth/
│       │   ├── login.tsx                   ← generated by init (basic login)
│       │   └── register.tsx                ← generated by init (basic signup)
│       │   # The OIDC flow uses the login page with a "Sign in with [IdP]" button
│       │   # that redirects to /auth/sso/redirect.
│       │
│       ├── admin/
│       │   ├── users/
│       │   │   ├── index.tsx
│       │   │   └── show.tsx
│       │   ├── categories/index.tsx
│       │   ├── idp_mappings/index.tsx
│       │   ├── audience_groups/index.tsx
│       │   └── audit_logs/index.tsx
│       │
│       ├── authoring/
│       │   ├── dashboard.tsx
│       │   └── policies/
│       │       ├── index.tsx
│       │       ├── create.tsx
│       │       ├── edit.tsx
│       │       └── review.tsx
│       │
│       └── portal/
│           ├── index.tsx
│           ├── policy.tsx
│           └── search.tsx
│
├── commands/
│   └── sync_idp_groups.ts                  ← node ace make:command sync_idp_groups
│
├── tests/
│   ├── bootstrap.ts
│   │
│   ├── unit/
│   │   ├── services/
│   │   │   ├── workflow_service.spec.ts    ← node ace make:test services/workflow_service \
│   │   │   │                                    --suite=unit
│   │   │   ├── template_service.spec.ts    ← node ace make:test services/template_service \
│   │   │   │                                    --suite=unit
│   │   │   └── change_summary_service.spec.ts ← node ace make:test services/change_summary \
│   │   │                                            --suite=unit
│   │   └── validators/
│   │       └── policy_validator.spec.ts    ← node ace make:test validators/policy --suite=unit
│   │
│   └── functional/
│       ├── auth/
│       │   └── oidc_callback.spec.ts       ← node ace make:test auth/oidc_callback \
│       │                                        --suite=functional
│       ├── policies/
│       │   ├── create.spec.ts              ← node ace make:test policies/create \
│       │   │                                    --suite=functional
│       │   ├── workflow.spec.ts            ← node ace make:test policies/workflow \
│       │   │                                    --suite=functional
│       │   └── portal_access.spec.ts       ← node ace make:test policies/portal_access \
│       │                                        --suite=functional
│       └── bot/
│           └── ask.spec.ts                 ← node ace make:test bot/ask --suite=functional
│
└── public/
    └── favicon.ico
```

---

## Step 4: Route Structure (`start/routes.ts`)

Three v7 patterns to note:

**Named routes** — every route gets an explicit `.as()` name to enable type-safe
`urlFor()` on both server and client.

**`InertiaMiddleware`** — registered in `start/kernel.ts` as a server middleware
(not a router middleware), so it runs on every request.

**Controller imports** — v7 auto-generates barrel files for controllers in
`.adonisjs/server/`. You can use either the barrel pattern or the explicit lazy
import pattern. Both are valid; the barrel pattern is the v7 default generated
by the starter kit and gives you tighter type inference:

```typescript
// v7 barrel pattern (starter kit default — uses auto-generated index)
import { controllers } from '#generated/controllers'
router.get('/posts', [controllers.Posts, 'index'])

// Explicit lazy import pattern (also valid — useful for grouping)
const PostsController = () => import('#controllers/posts_controller')
router.get('/posts', [PostsController, 'index'])
```

This project uses the **explicit lazy import** pattern in groups because it makes
the grouping and middleware structure more readable across many controller files.

```typescript
// start/routes.ts
import router from '@adonisjs/core/services/router'
import { middleware } from '#start/kernel'

// ── Auth ──────────────────────────────────────────────────────────────────────
// The create command generates basic /login and /register routes.
// We add the OIDC SSO flow on top.
const OidcController = () => import('#controllers/auth/oidc_controller')
router.get('/auth/sso/redirect', [OidcController, 'redirect']).as('auth.sso.redirect')
router.get('/auth/sso/callback', [OidcController, 'callback']).as('auth.sso.callback')
router.delete('/auth/logout', [OidcController, 'logout']).as('auth.logout')

// ── Authoring API ──────────────────────────────────────────────────────────────
router.group(() => {

  const PoliciesController = () => import('#controllers/authoring/policies_controller')
  router.resource('policies', PoliciesController).except(['show'])

  const ContentController = () => import('#controllers/authoring/content_controller')
  router.get('policies/:id/content', [ContentController, 'show'])
        .as('policies.content.show')
  router.put('policies/:id/content', [ContentController, 'update'])
        .as('policies.content.update')

  const WorkflowController = () => import('#controllers/authoring/workflow_controller')
  router.post('policies/:id/workflow/submit',          [WorkflowController, 'submit'])
        .as('policies.workflow.submit')
  router.post('policies/:id/workflow/withdraw',        [WorkflowController, 'withdraw'])
        .as('policies.workflow.withdraw')
  router.post('policies/:id/workflow/approve-l1',      [WorkflowController, 'approveL1'])
        .as('policies.workflow.approveL1')
  router.post('policies/:id/workflow/approve-final',   [WorkflowController, 'approveFinal'])
        .as('policies.workflow.approveFinal')
  router.post('policies/:id/workflow/request-changes', [WorkflowController, 'requestChanges'])
        .as('policies.workflow.requestChanges')
  router.post('policies/:id/workflow/resubmit',        [WorkflowController, 'resubmit'])
        .as('policies.workflow.resubmit')
  router.get('policies/:id/workflow/current',          [WorkflowController, 'current'])
        .as('policies.workflow.current')
  router.get('policies/:id/workflow/diff',             [WorkflowController, 'diff'])
        .as('policies.workflow.diff')

  const CommentsController = () => import('#controllers/authoring/comments_controller')
  router.get('policies/:id/comments',                      [CommentsController, 'index'])
        .as('policies.comments.index')
  router.post('policies/:id/comments',                     [CommentsController, 'store'])
        .as('policies.comments.store')
  router.patch('policies/:id/comments/:commentId/resolve', [CommentsController, 'resolve'])
        .as('policies.comments.resolve')

}).prefix('/api/v1').middleware([middleware.auth()])

// ── Admin / Portal / Webhooks groups follow the same pattern ──────────────────
```

---

## Step 5: Ace Command Sequence by Milestone

### Milestone 1 (Days 1–20): Auth + Editor scaffold

```bash
# Install remaining packages
node ace add @adonisjs/bouncer
node ace add @adonisjs/redis

# Auth — OIDC controller on top of the login scaffold from init
node ace make:controller auth/oidc

# Core models + migrations (run in schema dependency order)
node ace make:model user             && node ace make:migration create_users_table
node ace make:model role             && node ace make:migration create_roles_table
node ace make:model user_role        && node ace make:migration create_user_roles_table
node ace make:model idp_group_role_mapping \
                                     && node ace make:migration create_idp_group_role_mappings_table
node ace make:model audience_group   && node ace make:migration create_audience_groups_table
node ace make:model user_audience_group \
                                     && node ace make:migration create_user_audience_groups_table
node ace make:model category         && node ace make:migration create_categories_table
node ace make:model policy           && node ace make:migration create_policies_table
node ace make:migration create_policy_audience_groups_table
node ace make:migration create_policy_related_policies_table

# Services + validators + middleware
node ace make:service auth/sync_user
node ace make:service git/gitlab
node ace make:validator policy
node ace make:middleware require_role
node ace make:middleware portal_access
node ace make:middleware webhook_secret
node ace make:middleware inertia_middleware

# Bouncer authorization
node ace make:policy policy --resource-model=Policy

# Transformers (v7 first-class serialisation)
node ace make:transformer user
node ace make:transformer policy

# Authoring controllers
node ace make:controller authoring/policies
node ace make:controller authoring/content

# Seeders + factories
node ace make:seeder role
node ace make:seeder audience_group
node ace make:seeder dev
node ace make:factory user --model=user
node ace make:factory policy --model=policy

# Tests
node ace make:test auth/oidc_callback --suite=functional
node ace make:test policies/create --suite=functional

# Run migrations (v7: also triggers schema class generation into models)
node ace migration:run
node ace db:seed --files=database/seeders/role_seeder.ts
node ace db:seed --files=database/seeders/audience_group_seeder.ts
node ace db:seed --files=database/seeders/dev_seeder.ts
```

### Milestone 2 (Days 21–45): Workflow + Review

```bash
node ace make:model policy_version   && node ace make:migration create_policy_versions_table
node ace make:migration add_current_version_fk_to_policies_table
node ace make:model workflow_instance && node ace make:migration create_workflow_instances_table
node ace make:model workflow_reviewer && node ace make:migration create_workflow_reviewers_table
node ace make:model workflow_approval && node ace make:migration create_workflow_approvals_table
node ace make:model comment           && node ace make:migration create_comments_table
node ace make:model notification      && node ace make:migration create_notifications_table

node ace make:controller authoring/workflow
node ace make:controller authoring/comments
node ace make:service workflow/workflow
node ace make:policy workflow --resource-model=WorkflowInstance
node ace make:transformer workflow_instance
node ace make:validator workflow
node ace make:validator comment

node ace make:event policy_submitted
node ace make:listener notify_reviewers --event=policy_submitted
node ace make:listener queue_ai_summary --event=policy_submitted

node ace add @adonisjs/mail
node ace make:mail review_requested
node ace make:mail changes_requested

node ace add @adonisjs/queue
node ace make:job send_notification
node ace make:controller webhooks/gitlab

node ace make:test policies/workflow --suite=functional
node ace make:test services/workflow_service --suite=unit

node ace migration:run
```

### Milestone 3 (Days 46–70): Publishing pipeline

```bash
node ace make:service publishing/template
node ace make:service publishing/rendering
node ace make:service publishing/pdf
node ace make:job publishing
node ace make:transformer policy_version

node ace make:event policy_published
node ace make:listener notify_published --event=policy_published
node ace make:mail policy_published
node ace make:mail policy_approved

node ace add @adonisjs/drive
node ace make:factory workflow_instance --model=workflow_instance
node ace make:test services/template_service --suite=unit
```

### Milestone 4 (Days 71–95): Reader portal + search

```bash
node ace make:controller portal/policies
node ace make:controller portal/categories
node ace make:controller portal/search
node ace make:service search/typesense
node ace make:model audit_log && node ace make:migration create_audit_logs_table

node ace make:controller admin/users
node ace make:controller admin/categories
node ace make:controller admin/audience_groups
node ace make:controller admin/idp_mappings
node ace make:controller admin/audit_logs

node ace make:test policies/portal_access --suite=functional
node ace make:test validators/policy --suite=unit
node ace migration:run
```

### Milestone 5 (Days 96–130): AI + policy bot

```bash
node ace make:migration create_pgvector_extension
node ace make:model policy_chunk      && node ace make:migration create_policy_chunks_table
node ace make:model bot_interaction   && node ace make:migration create_bot_interactions_table
node ace make:model bot_interaction_source \
                                      && node ace make:migration create_bot_interaction_sources_table

node ace make:service ai/embedding
node ace make:service ai/change_summary
node ace make:service ai/bot
node ace make:job ai_change_summary
node ace make:job index_policy
node ace make:transformer bot_interaction
node ace make:controller portal/bot
node ace make:controller admin/bot_interactions

node ace make:test bot/ask --suite=functional
node ace make:test services/change_summary_service --suite=unit
node ace migration:run
```

---

## Reference: Complete `make:*` Command Set (v7)

| Command | Output location | Notes |
|---|---|---|
| `node ace make:controller <n>` | `app/controllers/` | `--resource` for CRUD scaffold |
| `node ace make:model <n>` | `app/models/` | Schema columns auto-generated after `migration:run` (v7) |
| `node ace make:migration <n>` | `database/migrations/` | Timestamp-prefixed automatically |
| `node ace make:seeder <n>` | `database/seeders/` | |
| `node ace make:factory <n>` | `database/factories/` | `--model=` links to a model |
| `node ace make:transformer <n>` | `app/transformers/` | **New in v7** — typed serialisation layer |
| `node ace make:middleware <n>` | `app/middleware/` | |
| `node ace make:validator <n>` | `app/validators/` | VineJS schema class |
| `node ace make:service <n>` | `app/services/` | Plain TypeScript class, no base class |
| `node ace make:event <n>` | `app/events/` | Class-based events (v6 pattern retained) |
| `node ace make:listener <n>` | `app/listeners/` | `--event=` to link to an event |
| `node ace make:mail <n>` | `app/mails/` | Requires `@adonisjs/mail` |
| `node ace make:policy <n>` | `app/policies/` | Requires `@adonisjs/bouncer` |
| `node ace make:exception <n>` | `app/exceptions/` | |
| `node ace make:command <n>` | `commands/` | Custom ace commands |
| `node ace make:test <n>` | `tests/` | `--suite=unit\|functional` |
| `node ace make:job <n>` | `app/jobs/` | Requires `@adonisjs/queue` |

---

## Reference: Path Aliases (`package.json`)

v7 adds `#generated/*` and `#transformers/*` to the v6 baseline set:

```json
{
  "imports": {
    "#controllers/*":  "./app/controllers/*.js",
    "#models/*":       "./app/models/*.js",
    "#services/*":     "./app/services/*.js",
    "#validators/*":   "./app/validators/*.js",
    "#transformers/*": "./app/transformers/*.js",
    "#middleware/*":   "./app/middleware/*.js",
    "#events/*":       "./app/events/*.js",
    "#listeners/*":    "./app/listeners/*.js",
    "#jobs/*":         "./app/jobs/*.js",
    "#mails/*":        "./app/mails/*.js",
    "#policies/*":     "./app/policies/*.js",
    "#generated/*":    "./.adonisjs/server/*.js",
    "#start/*":        "./start/*.js",
    "#config/*":       "./config/*.js",
    "#database/*":     "./database/*.js",
    "#tests/*":        "./tests/*.js"
  }
}
```

---

## Reference: v7 Code Patterns

```typescript
// ── URL generation ─────────────────────────────────────────────────────────
import { urlFor } from '@adonisjs/core/services/url_builder'
urlFor('policies.workflow.submit', { id: policyId })  // ✅ v7 type-safe
router.makeUrl('policies.workflow.submit', { id })     // ❌ deprecated in v7

// ── HTTP class names ───────────────────────────────────────────────────────
import { HttpRequest, HttpResponse } from '@adonisjs/core/http'  // ✅ v7
import { Request, Response } from '@adonisjs/core/http'          // ❌ removed in v7

// ── Flash message validation errors ───────────────────────────────────────
flashMessages.get('inputErrorsBag.email')  // ✅ v7
flashMessages.get('errors.email')          // ❌ removed in v7

// ── Directory helpers ──────────────────────────────────────────────────────
import.meta.dirname    // ✅ replaces getDirname() removed in v7
import.meta.filename   // ✅ replaces getFilename() removed in v7

// ── Test glob patterns in adonisrc.ts ──────────────────────────────────────
files: ['tests/unit/**/*.spec.{ts,js}']   // ✅ v7 Node.js built-in glob
files: ['tests/unit/**/*.spec(.ts|.js)']  // ❌ v6 pattern (fails in v7)

// ── Japa loginAs (unchanged — still the preferred test auth method) ─────────
const user = await UserFactory
  .with('roles', 1, r => r.merge({ name: 'policy:author' }))
  .create()

await client
  .post('/api/v1/policies')
  .loginAs(user)
  .json({ title: 'Test Policy' })
```

---

## Reference: Running the Application

```bash
# Development
node ace serve --hmr

# Migrations (v7: also triggers auto schema class generation into models)
node ace migration:run
node ace migration:rollback
node ace migration:status

# Seeding
node ace db:seed
node ace db:seed --files=database/seeders/dev_seeder.ts

# Testing (note .{ts,js} glob syntax in adonisrc.ts)
node ace test
node ace test --suite=unit
node ace test --suite=functional
node ace test --files=tests/functional/policies/workflow.spec.ts

# Routes
node ace list:routes

# Queue worker (separate process in production)
node ace queue:listen

# Production build
node ace build
```
