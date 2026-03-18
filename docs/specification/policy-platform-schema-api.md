# Policy Library Platform — Database Schema & API Design

## Design Principles

**The golden rule of data ownership:**
- **GitLab owns:** Markdown content, file history, branches, MRs, diffs, MR-level comments, commit SHAs
- **PostgreSQL owns:** Metadata, workflow state (enriched mirror of GitLab MR state), RBAC, rendered output, AI embeddings, audit logs, notifications, bot interactions, user sessions

The database never duplicates what GitLab owns. When the application needs diff content, it calls the GitLab API. When it needs who approved what and when, it reads PostgreSQL. The two systems are joined by `gitlab_mr_iid` and `gitlab_file_path` as foreign keys into GitLab.

---

## Schema

### ERD Overview

```
users ──────────────────────────────────────────────────────────┐
  │                                                             │
  ├──< user_roles >── roles                                     │
  ├──< user_audience_groups >── audience_groups                 │
  │                                  │                          │
  │                            policy_audience_groups           │
  │                                  │                          │
  ├──< policies >─────────────────────┘                         │
  │       │                                                     │
  │       ├──< policy_versions >── policy_chunks (pgvector)     │
  │       ├──< policy_related_policies                          │
  │       ├──< workflow_instances >── workflow_approvals ───────┘
  │       │          │                workflow_reviewers ───────┘
  │       │          └──< comments                              │
  │       └──< notifications ──────────────────────────────────┘
  │
  └──< bot_interactions >── bot_interaction_sources
  └──< audit_logs
```

---

### Table Definitions

#### `users`
Synced from the configured IdP on first login and refreshed on each subsequent
login. Provider-agnostic: works with Entra, Okta, Google Workspace, GitLab, or
any OIDC-compliant provider.

```sql
CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  idp_subject   VARCHAR(255) NOT NULL,    -- OIDC 'sub' claim (stable per provider)
  idp_provider  VARCHAR(100) NOT NULL DEFAULT 'entra',
  -- e.g. 'entra' | 'okta' | 'google' | 'gitlab'
  -- Composite unique: same sub from different providers = different users
  email         VARCHAR(255) NOT NULL UNIQUE,
  display_name  VARCHAR(255) NOT NULL,
  avatar_url    VARCHAR(500),
  is_active     BOOLEAN NOT NULL DEFAULT true,
  last_login_at TIMESTAMPTZ,

  -- Local auth (only populated when LOCAL_AUTH_ENABLED=true)
  -- NULL for all SSO users; never set in production
  password      VARCHAR(255),

  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (idp_subject, idp_provider)
);

CREATE INDEX idx_users_idp   ON users(idp_subject, idp_provider);
CREATE INDEX idx_users_email ON users(email);
```

---

#### `roles`
Authoring-side RBAC. These control who can perform editorial actions.

```sql
CREATE TABLE roles (
  id          SERIAL PRIMARY KEY,
  name        VARCHAR(100) NOT NULL UNIQUE,
  -- e.g. policy:author | policy:reviewer | policy:approver:l1
  --      policy:approver:l2 | policy:admin
  description TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

#### `user_roles`
Many-to-many: a user may hold multiple authoring roles.

```sql
CREATE TABLE user_roles (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id     INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  assigned_by UUID REFERENCES users(id),
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, role_id)
);
```

---

#### `idp_group_role_mappings`
Maps an IdP group (from the ID token `groups` claim) to an authoring role.
Populated and maintained by admins. Evaluated on every login to sync `user_roles`.
The `idp_provider` column scopes mappings to a specific provider, supporting
multi-provider setups or provider migrations without ambiguity.

```sql
CREATE TABLE idp_group_role_mappings (
  idp_provider    VARCHAR(100) NOT NULL DEFAULT 'entra',
  -- Matches users.idp_provider
  idp_group_id    VARCHAR(255) NOT NULL,
  -- Group object ID / external ID from the IdP's groups claim
  role_id         INTEGER NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  description     VARCHAR(255),
  PRIMARY KEY (idp_provider, idp_group_id, role_id)
);
```

**Why this exists separately from `user_roles`:** IdP group membership changes
outside the application (e.g., someone joins the Finance team in Entra/Okta).
This mapping table lets the application re-evaluate roles on each login without
manual admin intervention. `user_roles` is the resolved state; this table is
the rule.

---

#### `audience_groups`
Reader-side RBAC. These control which published policies a user can see.
Each entry corresponds to either an IdP group or a manually managed segment.

```sql
CREATE TABLE audience_groups (
  id              SERIAL PRIMARY KEY,
  name            VARCHAR(100) NOT NULL UNIQUE,
  -- e.g. all-staff | finance | it | hr | executives | legal
  idp_group_id    VARCHAR(255),
  -- Group ID from the IdP's groups claim. NULL = manually managed group
  -- (admin assigns users directly via user_audience_groups)
  description     TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

---

#### `user_audience_groups`
Resolved reader permissions per user — rebuilt on login from IdP group claims.

```sql
CREATE TABLE user_audience_groups (
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  audience_group_id INTEGER NOT NULL REFERENCES audience_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (user_id, audience_group_id)
);
```

---

#### `categories`
Mirrors the GitLab folder structure. Self-referential for nesting.

```sql
CREATE TABLE categories (
  id            SERIAL PRIMARY KEY,
  name          VARCHAR(255) NOT NULL,
  slug          VARCHAR(255) NOT NULL UNIQUE,
  parent_id     INTEGER REFERENCES categories(id) ON DELETE SET NULL,
  gitlab_path   VARCHAR(500) NOT NULL UNIQUE,
  -- e.g. 'hr' | 'hr/recruitment' | 'it/security'
  description   TEXT,
  sort_order    INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_categories_parent ON categories(parent_id);
CREATE INDEX idx_categories_path   ON categories(gitlab_path);
```

---

#### `policies`
The central metadata record. Content lives in GitLab; this record is the
application's authoritative source of truth for everything else.

```sql
CREATE TABLE policies (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title                       VARCHAR(500) NOT NULL,
  slug                        VARCHAR(500) NOT NULL UNIQUE,
  category_id                 INTEGER NOT NULL REFERENCES categories(id),
  owner_id                    UUID NOT NULL REFERENCES users(id),

  -- GitLab pointers
  gitlab_project_id           VARCHAR(100) NOT NULL,
  gitlab_file_path            VARCHAR(500) NOT NULL UNIQUE,
  -- e.g. 'hr/expense-policy.md'

  -- Current state
  status                      VARCHAR(50) NOT NULL DEFAULT 'draft',
  -- enum: draft | in_review | changes_requested |
  --       approved_l1 | approved_final | published | archived
  current_published_version_id UUID,  -- FK added after policy_versions created

  -- Policy metadata (stored here, also injected into published template)
  purpose                     TEXT,
  review_date                 DATE,
  effective_date              DATE,
  sensitivity_level           VARCHAR(50) NOT NULL DEFAULT 'standard',
  -- enum: standard | restricted | confidential

  -- Authoring
  created_by_id               UUID NOT NULL REFERENCES users(id),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_policies_category  ON policies(category_id);
CREATE INDEX idx_policies_owner     ON policies(owner_id);
CREATE INDEX idx_policies_status    ON policies(status);
CREATE INDEX idx_policies_review    ON policies(review_date);
```

---

#### `policy_audience_groups`
Which audience groups can see a published policy in the reader portal.
A policy with no audience groups is invisible to all portal readers (only
visible to authoring admins). `all-staff` makes it universally visible.

```sql
CREATE TABLE policy_audience_groups (
  policy_id         UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  audience_group_id INTEGER NOT NULL REFERENCES audience_groups(id) ON DELETE CASCADE,
  PRIMARY KEY (policy_id, audience_group_id)
);

CREATE INDEX idx_pag_audience ON policy_audience_groups(audience_group_id);
```

---

#### `policy_related_policies`
Directional relationships between policies. Stored once per direction
(A→B and B→A) to simplify queries. The publishing service reads this
to render the "Related Policies" section.

```sql
CREATE TABLE policy_related_policies (
  policy_id         UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  related_policy_id UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  relationship_type VARCHAR(100),
  -- e.g. 'see-also' | 'supersedes' | 'required-reading'
  PRIMARY KEY (policy_id, related_policy_id),
  CHECK (policy_id <> related_policy_id)
);
```

---

#### `policy_versions`
Immutable snapshots of each published version. Once created, never updated.
The `rendered_html` is the canonical published document.

```sql
CREATE TABLE policy_versions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id           UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,

  version_number      INTEGER NOT NULL,
  -- Auto-incremented per policy: 1, 2, 3...
  git_commit_sha      VARCHAR(40) NOT NULL,
  -- The exact commit on main branch this version corresponds to

  title_at_version    VARCHAR(500) NOT NULL,
  -- Snapshot of title in case it changes

  rendered_html       TEXT NOT NULL,
  -- Full published HTML including boilerplate
  pdf_storage_path    VARCHAR(500),
  -- Path in object storage (S3/local disk)

  change_summary      TEXT,
  -- AI-generated or manually written summary of what changed
  change_summary_type VARCHAR(20) DEFAULT 'ai',
  -- enum: ai | manual

  published_by_id     UUID NOT NULL REFERENCES users(id),
  published_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  effective_date      DATE,

  UNIQUE (policy_id, version_number)
);

CREATE INDEX idx_pv_policy    ON policy_versions(policy_id);
CREATE INDEX idx_pv_published ON policy_versions(published_at DESC);
```

**After `policy_versions` is created, add the FK on `policies`:**

```sql
ALTER TABLE policies
  ADD CONSTRAINT fk_policies_current_version
  FOREIGN KEY (current_published_version_id)
  REFERENCES policy_versions(id)
  ON DELETE SET NULL;
```

---

#### `workflow_instances`
One record per review cycle (each time a policy goes through draft →
review → approval → publish). A policy may have many workflow instances
over its lifetime. Only one should be `active` at a time.

```sql
CREATE TABLE workflow_instances (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_id               UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,

  -- GitLab pointers
  gitlab_mr_iid           INTEGER,
  -- The MR number within the project (NULL until MR is opened)
  gitlab_branch_name      VARCHAR(500) NOT NULL,
  -- e.g. 'draft/expense-policy-2025-03'

  -- State machine
  status                  VARCHAR(50) NOT NULL DEFAULT 'draft',
  -- enum: draft | submitted | under_review | changes_requested |
  --       approved_l1 | approved_final | merged | closed

  -- Authoring
  submitted_by_id         UUID REFERENCES users(id),
  submitted_at            TIMESTAMPTZ,

  -- Change guardrail
  change_magnitude_score  NUMERIC(5,2),
  -- Calculated on MR open: 0.0 (no change) – 100.0 (complete rewrite)
  change_justification    TEXT,
  -- Required when score exceeds threshold

  -- AI outputs
  ai_change_summary       TEXT,
  -- Generated when MR is opened, cached here
  ai_summary_generated_at TIMESTAMPTZ,

  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wi_policy     ON workflow_instances(policy_id);
CREATE INDEX idx_wi_status     ON workflow_instances(status);
CREATE INDEX idx_wi_gitlab_mr  ON workflow_instances(gitlab_mr_iid);
```

---

#### `workflow_reviewers`
Tracks who is assigned to each role in a workflow instance.
Allows configurable routing per policy category.

```sql
CREATE TABLE workflow_reviewers (
  id                    SERIAL PRIMARY KEY,
  workflow_instance_id  UUID NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  user_id               UUID NOT NULL REFERENCES users(id),
  reviewer_role         VARCHAR(50) NOT NULL,
  -- enum: reviewer | approver_l1 | approver_l2
  assigned_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notified_at           TIMESTAMPTZ,

  UNIQUE (workflow_instance_id, user_id, reviewer_role)
);
```

---

#### `workflow_approvals`
Immutable record of each approval action. Never updated; append-only.

```sql
CREATE TABLE workflow_approvals (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_instance_id  UUID NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  approver_id           UUID NOT NULL REFERENCES users(id),
  approval_level        VARCHAR(10) NOT NULL,
  -- enum: l1 | l2
  action                VARCHAR(30) NOT NULL,
  -- enum: approved | rejected | changes_requested
  comment               TEXT,
  acted_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wa_workflow ON workflow_approvals(workflow_instance_id);
```

---

#### `comments`
Mirrored from GitLab MR notes. GitLab is the source of truth; this table
is a cache to avoid hammering the GitLab API on every page load, and to
support notifications and resolution tracking.

```sql
CREATE TABLE comments (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_instance_id  UUID NOT NULL REFERENCES workflow_instances(id) ON DELETE CASCADE,
  gitlab_note_id        BIGINT UNIQUE,
  -- NULL for comments created via application UI (synced to GitLab async)
  author_id             UUID REFERENCES users(id),
  body                  TEXT NOT NULL,
  is_resolved           BOOLEAN NOT NULL DEFAULT false,
  resolved_by_id        UUID REFERENCES users(id),
  resolved_at           TIMESTAMPTZ,
  gitlab_created_at     TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_comments_workflow ON comments(workflow_instance_id);
```

---

#### `notifications`
In-app and email notification queue.

```sql
CREATE TABLE notifications (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type                  VARCHAR(100) NOT NULL,
  -- enum: review_requested | changes_requested | approved_l1 |
  --       approved_final | published | review_due | comment_added |
  --       policy_updated
  policy_id             UUID REFERENCES policies(id) ON DELETE CASCADE,
  workflow_instance_id  UUID REFERENCES workflow_instances(id) ON DELETE CASCADE,
  payload               JSONB,
  -- Arbitrary context data for rendering the notification
  read_at               TIMESTAMPTZ,
  emailed_at            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notif_user    ON notifications(user_id, read_at);
CREATE INDEX idx_notif_created ON notifications(created_at DESC);
```

---

#### `audit_logs`
Append-only compliance record. Never updated or deleted.

```sql
CREATE TABLE audit_logs (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES users(id) ON DELETE SET NULL,
  action        VARCHAR(100) NOT NULL,
  -- e.g. policy.created | policy.submitted | policy.approved_l1 |
  --      policy.approved_final | policy.published | policy.archived |
  --      user.role_assigned | comment.added
  entity_type   VARCHAR(50),
  -- e.g. policy | workflow_instance | user
  entity_id     VARCHAR(255),
  before_state  JSONB,
  after_state   JSONB,
  metadata      JSONB,
  ip_address    INET,
  user_agent    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_entity  ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_user    ON audit_logs(user_id);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_action  ON audit_logs(action);
```

---

#### `policy_chunks`
RAG source chunks. One policy version is split into many chunks.
Each chunk has a vector embedding for semantic search.

```sql
-- Requires: CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE policy_chunks (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  policy_version_id   UUID NOT NULL REFERENCES policy_versions(id) ON DELETE CASCADE,
  policy_id           UUID NOT NULL REFERENCES policies(id) ON DELETE CASCADE,
  -- Denormalised for efficient filtering without JOIN
  chunk_index         INTEGER NOT NULL,
  -- Position within the document: 0, 1, 2...
  section_path        TEXT,
  -- Breadcrumb of headings: 'Scope > Domestic Travel > Hotel Limits'
  content             TEXT NOT NULL,
  -- Plain text, markdown stripped
  token_count         INTEGER,
  embedding           VECTOR(1536),
  -- OpenAI text-embedding-3-small | or equivalent
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (policy_version_id, chunk_index)
);

-- HNSW index for fast approximate nearest-neighbour search
CREATE INDEX idx_chunks_embedding
  ON policy_chunks USING hnsw (embedding vector_cosine_ops)
  WITH (m = 16, ef_construction = 64);

CREATE INDEX idx_chunks_policy   ON policy_chunks(policy_id);
CREATE INDEX idx_chunks_version  ON policy_chunks(policy_version_id);
```

---

#### `bot_interactions`
Every question asked to the policy bot, logged for quality review
and policy gap analysis.

```sql
CREATE TABLE bot_interactions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID REFERENCES users(id) ON DELETE SET NULL,
  question            TEXT NOT NULL,
  -- Verbatim user input
  rewritten_question  TEXT,
  -- Query-rewritten version used for embedding
  answer              TEXT,
  -- NULL if no answer was generated (fallback to search)
  was_answered        BOOLEAN NOT NULL DEFAULT false,
  confidence_score    NUMERIC(4,3),
  -- Average similarity of top retrieved chunks: 0.000–1.000
  feedback            VARCHAR(20),
  -- enum: positive | negative | NULL (no feedback given)
  feedback_note       TEXT,
  session_id          VARCHAR(255),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bot_user     ON bot_interactions(user_id);
CREATE INDEX idx_bot_answered ON bot_interactions(was_answered);
CREATE INDEX idx_bot_created  ON bot_interactions(created_at DESC);
```

---

#### `bot_interaction_sources`
Which policy chunks were cited in a bot answer.

```sql
CREATE TABLE bot_interaction_sources (
  bot_interaction_id  UUID NOT NULL REFERENCES bot_interactions(id) ON DELETE CASCADE,
  policy_chunk_id     UUID NOT NULL REFERENCES policy_chunks(id) ON DELETE CASCADE,
  rank                INTEGER NOT NULL,
  -- Position in retrieved results: 1 = most relevant
  similarity_score    NUMERIC(4,3),
  PRIMARY KEY (bot_interaction_id, policy_chunk_id)
);
```

---

### Lucid Model Summary (AdonisJS)

Each table above maps to a Lucid model. Key relationships:

```typescript
// User model (abbreviated)
class User extends BaseModel {
  @hasMany(() => UserRole)      roles: HasMany<typeof UserRole>
  @hasMany(() => Notification)  notifications: HasMany<typeof Notification>
  @hasMany(() => Policy, { fk: 'owner_id' })  ownedPolicies: HasMany<typeof Policy>
  @hasMany(() => AuditLog)      auditLogs: HasMany<typeof AuditLog>
}

// Policy model (abbreviated)
class Policy extends BaseModel {
  @belongsTo(() => Category)              category: BelongsTo<typeof Category>
  @belongsTo(() => User, { fk: 'owner_id' }) owner: BelongsTo<typeof User>
  @hasMany(() => PolicyVersion)           versions: HasMany<typeof PolicyVersion>
  @hasMany(() => WorkflowInstance)        workflowInstances: HasMany<typeof WorkflowInstance>
  @manyToMany(() => AudienceGroup, { pivotTable: 'policy_audience_groups' })
    audienceGroups: ManyToMany<typeof AudienceGroup>
  @manyToMany(() => Policy, { pivotTable: 'policy_related_policies',
    localKey: 'id', relatedKey: 'related_policy_id' })
    relatedPolicies: ManyToMany<typeof Policy>
}

// WorkflowInstance model (abbreviated)
class WorkflowInstance extends BaseModel {
  @belongsTo(() => Policy)              policy: BelongsTo<typeof Policy>
  @hasMany(() => WorkflowApproval)      approvals: HasMany<typeof WorkflowApproval>
  @hasMany(() => WorkflowReviewer)      reviewers: HasMany<typeof WorkflowReviewer>
  @hasMany(() => Comment)               comments: HasMany<typeof Comment>
}
```

---

## API Design

### Overview

All routes are prefixed. Two route groups:
- `/api/v1/*` — Authoring surface (authors, reviewers, approvers, admins)
- `/portal/api/*` — Reader surface (all authenticated staff, role-filtered)
- `/webhooks/*` — GitLab webhook receiver (verified by secret token)

Authentication: All routes require a valid session via AdonisJS Auth (SSO or local auth if enabled).
Authorization: Middleware checks role assignments per route group.

---

### Authentication

#### SSO (primary — all environments)

```
GET  /auth/login          → Redirect to configured IdP OIDC endpoint
GET  /auth/callback       → Handle OIDC callback, create session,
                            sync user_roles + user_audience_groups from IdP claims
DELETE /auth/logout       → Destroy session
GET  /auth/me             → Current user profile + roles + audience groups
```

**On callback, the application:**
1. Upserts the user record from the ID token `sub` + `email` + `name` claims
2. Reads the `groups` claim from the token (claim name is IdP-specific, configured via env)
3. Resolves `idp_group_role_mappings` for this provider → writes `user_roles`
4. Resolves `audience_groups.idp_group_id` matches → writes `user_audience_groups`
5. Writes an `audit_log` entry for the login

The post-login sync logic lives in a single `syncUserFromSession(user, claims)`
service method called by all auth paths, so behaviour is consistent regardless
of how the session was established.

#### Local auth (dev and staging only — gated by `LOCAL_AUTH_ENABLED=true`)

When `LOCAL_AUTH_ENABLED` is false (the default, and always in production) these
routes do not exist — they return 404, not a disabled message. There is no
attack surface. When enabled, uses AdonisJS's built-in database-backed auth
with bcrypt password hashing.

```
POST /auth/local/login
  → Body: { email, password }
  → Validates credentials against users.password (bcrypt)
  → Calls syncUserFromSession() — roles must be seeded directly in DB
  → Creates session identical to SSO session

POST /auth/local/register
  → Body: { email, password, displayName }
  → Only available when LOCAL_AUTH_ENABLED=true
  → Creates user with idp_provider = 'local', idp_subject = email
  → Does NOT auto-assign roles — admin must assign via /api/v1/admin/users/:id/roles
```

**Note for local users:** Because local auth bypasses the IdP callback, the
`idp_group_role_mappings` sync does not fire. Roles must be assigned manually
via the admin API or seeded in the database. This is intentional — local auth
is for testing only, and explicit role seeding makes test scenarios precise.

#### Automated testing (Japa)

For automated tests, bypass auth entirely using Japa's built-in `loginAs`
helper. This is strictly better than local auth for tests — no HTTP roundtrip,
no credential management, factories can set roles precisely:

```typescript
const author = await UserFactory
  .with('roles', 1, r => r.merge({ name: 'policy:author' }))
  .create()

await client
  .post('/api/v1/policies')
  .loginAs(author)
  .json({ title: 'Test Policy', ... })
```

---

### Policies (Authoring)

```
GET    /api/v1/policies
  → List policies the user can author/review
  → Query: ?status=&category=&owner=&search=&page=&perPage=

POST   /api/v1/policies
  → Create policy metadata record + GitLab branch + empty MD file from template
  → Body: { title, categoryId, purpose, audienceGroups[], reviewDate,
             sensitivityLevel, relatedPolicies[] }

GET    /api/v1/policies/:id
  → Policy metadata + current workflow instance + latest version info

PATCH  /api/v1/policies/:id
  → Update metadata (title, owner, reviewDate, audienceGroups, etc.)
  → Does NOT touch GitLab content — that is editor saves

DELETE /api/v1/policies/:id
  → Soft delete (status = archived). Only admins. Cannot delete published.

GET    /api/v1/policies/:id/versions
  → List all published versions (version number, date, summary, published by)

GET    /api/v1/policies/:id/versions/:versionId
  → Single version: rendered HTML, change summary, git SHA

GET    /api/v1/policies/:id/versions/:versionId/diff
  → Diff between this version and the previous one
  → Returns: { rawDiff, renderedBefore, renderedAfter }

GET    /api/v1/policies/:id/versions/:versionId/pdf
  → Redirect to PDF download URL (pre-generated, stored in object storage)
```

---

### Editor (Content Saves — Bridge to GitLab)

These routes are the thin bridge between TipTap saves and GitLab commits.
The application calls the GitLab API on behalf of the user.

```
GET    /api/v1/policies/:id/content
  → Fetch current draft content from GitLab branch
  → Returns: { markdown, branchName, lastCommitSha, lastCommitAt, lastCommitBy }

PUT    /api/v1/policies/:id/content
  → Commit updated content to GitLab branch (create or update file)
  → Body: { markdown, commitMessage }
  → Returns: { commitSha, committedAt }
  → Debounced on client: fires at most once per 30s during active editing,
    always on explicit Save
  → Creates branch if it doesn't exist (new policy)

GET    /api/v1/policies/:id/content/history
  → Last N commits on the draft branch (from GitLab API, cached 60s)
  → Returns: [{ sha, message, author, committedAt }]
```

---

### Workflow (State Transitions)

State transitions are explicit named actions, not generic PATCH calls.
Each action validates the current state, performs the GitLab operation,
updates the database, and fires notifications.

```
POST   /api/v1/policies/:id/workflow/submit
  → Draft → Submitted
  → Creates GitLab MR (draft MR targeting main branch)
  → Assigns reviewers from category defaults or request body
  → Calculates change_magnitude_score
  → Triggers async AI change summary generation
  → Body: { reviewerIds[], approverL1Id, approverL2Id, changeJustification? }

POST   /api/v1/policies/:id/workflow/withdraw
  → Submitted/UnderReview/ChangesRequested → Draft
  → Closes GitLab MR
  → Only the submitter or admin

POST   /api/v1/policies/:id/workflow/approve-l1
  → UnderReview → ApprovedL1
  → Adds approval to GitLab MR
  → Fires notification to L2 approver
  → Body: { comment? }
  → Requires role: policy:approver:l1

POST   /api/v1/policies/:id/workflow/approve-final
  → ApprovedL1 → ApprovedFinal
  → Merges the GitLab MR
  → Triggers publishing pipeline (async job)
  → Body: { comment? }
  → Requires role: policy:approver:l2

POST   /api/v1/policies/:id/workflow/request-changes
  → UnderReview/ApprovedL1 → ChangesRequested
  → Posts comment to GitLab MR
  → Notifies author
  → Body: { comment } (required — must explain what to change)
  → Requires role: policy:reviewer | policy:approver:l1 | policy:approver:l2

POST   /api/v1/policies/:id/workflow/resubmit
  → ChangesRequested → UnderReview
  → Re-opens the GitLab MR (or creates a new one if closed)
  → Only the original submitter
```

---

### Review Interface

```
GET    /api/v1/policies/:id/workflow/current
  → Current workflow instance: status, reviewers, approvals, timeline
  → Includes: ai_change_summary, change_magnitude_score, change_justification

GET    /api/v1/policies/:id/workflow/diff
  → Side-by-side diff for review screen
  → Returns:
      rawDiff:        unified diff string (for Monaco Editor)
      beforeMarkdown: current main branch content (empty string for new policies)
      afterMarkdown:  current draft branch content
      beforeRendered: HTML render of main branch version
      afterRendered:  HTML render of draft version
  → Both branches fetched from GitLab API; rendered server-side
  → Cached for 30s (invalidated by new commit)

GET    /api/v1/policies/:id/comments
  → All comments on the current workflow instance
  → Fetched from local DB (synced from GitLab)

POST   /api/v1/policies/:id/comments
  → Post a comment (saved to DB, also posted to GitLab MR via API)
  → Body: { body }

PATCH  /api/v1/policies/:id/comments/:commentId/resolve
  → Mark comment as resolved (DB + GitLab)
```

---

### Publishing Pipeline (Internal — triggered by workflow, not directly called)

These are internal service methods, not exposed HTTP routes. Called by the
`approve-final` action via an async job.

```
PublishingJob.handle(policyId, workflowInstanceId):
  1. Fetch merged markdown from GitLab main branch
  2. Fetch policy metadata from DB
  3. Inject boilerplate template:
       - Title, owner, effective date, version number
       - Table of contents (generated from headings)
       - Related policies (resolved from policy_related_policies)
       - Version history table (last 5 versions from policy_versions)
  4. Render markdown → HTML (unified/remark/rehype pipeline)
  5. Generate PDF via Puppeteer
  6. Store PDF in object storage
  7. Insert policy_versions record
  8. Update policies.current_published_version_id
  9. Update policies.status = 'published'
  10. Index in Typesense (title + plaintext body)
  11. Chunk + embed for RAG → insert policy_chunks
  12. Fire 'policy_updated' notification to all users in audience groups
```

---

### Admin

```
GET    /api/v1/admin/users
  → List all users with roles
  → Query: ?search=&role=&page=

GET    /api/v1/admin/users/:id
POST   /api/v1/admin/users/:id/roles         → Assign role
DELETE /api/v1/admin/users/:id/roles/:roleId → Remove role

GET    /api/v1/admin/categories
POST   /api/v1/admin/categories
PATCH  /api/v1/admin/categories/:id
DELETE /api/v1/admin/categories/:id  → Only if no policies assigned

GET    /api/v1/admin/audience-groups
POST   /api/v1/admin/audience-groups
PATCH  /api/v1/admin/audience-groups/:id

GET    /api/v1/admin/idp-mappings
  → List IdP group → role mappings (filterable by ?provider=)
POST   /api/v1/admin/idp-mappings      → Create mapping
DELETE /api/v1/admin/idp-mappings/:id  → Remove mapping

GET    /api/v1/admin/audit-logs
  → Query: ?entityType=&entityId=&userId=&action=&from=&to=&page=

GET    /api/v1/admin/workflow-config
  → Per-category approval routing configuration
PATCH  /api/v1/admin/workflow-config/:categoryId
  → Set default approver assignments for a category
```

---

### Portal (Reader Surface)

All portal routes return only policies where the user's audience groups
intersect with `policy_audience_groups`. This filtering happens at the
query layer — missing records are invisible, not 403.

```
GET    /portal/api/policies
  → Published policies visible to the current user
  → Query: ?category=&search=&page=&perPage=
  → Sorted by: title | effective_date | updated_at

GET    /portal/api/policies/:id
  → Full rendered policy (HTML from current_published_version)
  → Returns 404 (not 403) if not in user's audience — policy existence is hidden
  → Includes: metadata, related policies, version info

GET    /portal/api/policies/:id/pdf
  → Redirect to pre-generated PDF

GET    /portal/api/categories
  → Category tree, pre-filtered to only categories containing visible policies
  → Returns nested structure: [{ id, name, slug, children[], policyCount }]

GET    /portal/api/search
  → Full-text search via Typesense
  → Query: ?q=&category=&page=
  → Results are role-filtered at query time (Typesense filter_by)
  → Returns: [{ policyId, title, category, excerpt, score }]
```

---

### Policy Bot

```
POST   /portal/api/bot/ask
  → Submit a question to the policy bot
  → Body: { question, sessionId? }
  → Processing (server-side, streamed):
      1. Rewrite question to canonical search form
      2. Embed rewritten question
      3. Vector search policy_chunks WHERE policy_id IN (user's visible policies)
      4. If max similarity < threshold: return search fallback
      5. Build grounded prompt with retrieved chunks + source metadata
      6. Stream Claude response to client
      7. Log bot_interaction + bot_interaction_sources records
  → Returns (streamed): { answer, sources[], wasAnswered, confidence }

POST   /portal/api/bot/interactions/:id/feedback
  → Submit thumbs up/down on a bot response
  → Body: { feedback: 'positive'|'negative', note? }

GET    /api/v1/admin/bot/interactions
  → Admin view of all bot interactions for quality review
  → Query: ?wasAnswered=false&feedback=negative&from=&to=
  → Unanswered questions → policy gap analysis
```

---

### GitLab Webhooks

```
POST   /webhooks/gitlab
  → Receives GitLab MR events
  → Verified by X-Gitlab-Token header (shared secret)
  → Handled event types:

  merge_request.opened
    → Update workflow_instance.gitlab_mr_iid
    → Update workflow_instance.status = 'under_review'

  merge_request.approved
    → Record approval in workflow_approvals
    → Advance workflow state machine

  merge_request.merged
    → Trigger PublishingJob (if not already triggered by approve-final)
    → Safety net for direct GitLab merges by admins

  merge_request.closed
    → Update workflow_instance.status = 'closed'
    → Notify author

  note.created (MR comment)
    → Upsert comment into comments table
    → Notify relevant parties
```

---

## Key Query Patterns

### Policy listing with RBAC filter (portal)

```sql
SELECT p.*, pv.published_at, pv.version_number, c.name as category_name
FROM policies p
JOIN policy_versions pv ON p.current_published_version_id = pv.id
JOIN categories c ON p.category_id = c.id
WHERE p.status = 'published'
  AND EXISTS (
    SELECT 1 FROM policy_audience_groups pag
    JOIN user_audience_groups uag ON pag.audience_group_id = uag.audience_group_id
    WHERE pag.policy_id = p.id
      AND uag.user_id = :currentUserId
  )
ORDER BY p.title
LIMIT :limit OFFSET :offset;
```

### RAG vector search with RBAC filter

```sql
SELECT
  pc.id,
  pc.content,
  pc.section_path,
  pc.policy_id,
  p.title as policy_title,
  1 - (pc.embedding <=> :queryEmbedding) AS similarity
FROM policy_chunks pc
JOIN policies p ON pc.policy_id = p.id
WHERE pc.policy_id IN (
  -- Subquery: only chunks from policies visible to this user
  SELECT p2.id FROM policies p2
  WHERE p2.status = 'published'
    AND EXISTS (
      SELECT 1 FROM policy_audience_groups pag
      JOIN user_audience_groups uag ON pag.audience_group_id = uag.audience_group_id
      WHERE pag.policy_id = p2.id AND uag.user_id = :currentUserId
    )
)
AND 1 - (pc.embedding <=> :queryEmbedding) > :similarityThreshold
ORDER BY similarity DESC
LIMIT :topK;
```

### Policies approaching review date (for reminders job)

```sql
SELECT p.*, u.email as owner_email, u.display_name as owner_name
FROM policies p
JOIN users u ON p.owner_id = u.id
WHERE p.status = 'published'
  AND p.review_date BETWEEN NOW() AND NOW() + INTERVAL '30 days'
  AND NOT EXISTS (
    -- Don't re-notify if already notified this month
    SELECT 1 FROM notifications n
    WHERE n.policy_id = p.id
      AND n.type = 'review_due'
      AND n.created_at > NOW() - INTERVAL '30 days'
  );
```

---

## Migration Sequencing

Migrations should be created in this order to satisfy foreign key dependencies:

```
001_create_users
002_create_roles
003_create_user_roles
004_create_idp_group_role_mappings
005_create_audience_groups
006_create_user_audience_groups
007_create_categories
008_create_policies                    ← no FK to policy_versions yet
009_create_policy_audience_groups
010_create_policy_related_policies
011_create_policy_versions
012_add_current_version_fk_to_policies ← ADD the FK now
013_create_workflow_instances
014_create_workflow_reviewers
015_create_workflow_approvals
016_create_comments
017_create_notifications
018_create_audit_logs
019_create_pgvector_extension
020_create_policy_chunks
021_create_bot_interactions
022_create_bot_interaction_sources
```

The `password` column on `users` is included in `001_create_users` as a
nullable column. No separate migration is needed — it is always present in
the schema and simply `NULL` for all SSO users. When `LOCAL_AUTH_ENABLED` is
false, the application never reads or writes it.

---

## Environment Variables (AdonisJS `.env`)

```bash
# App
APP_KEY=                       # 32-char random key for encryption
NODE_ENV=production
PORT=3333
HOST=0.0.0.0

# Database
DB_CONNECTION=pg
DB_HOST=
DB_PORT=5432
DB_USER=
DB_PASSWORD=
DB_DATABASE=policy_platform

# Redis / Valkey
REDIS_HOST=
REDIS_PORT=6379
REDIS_PASSWORD=

# Identity Provider (OIDC)
# Variable names use the provider for clarity, but the schema is provider-agnostic.
# To switch providers: update these values + idp_group_role_mappings table. No code changes.
IDP_PROVIDER=entra             # Value written to users.idp_provider
IDP_CLIENT_ID=
IDP_CLIENT_SECRET=
IDP_ISSUER_URL=                # e.g. https://login.microsoftonline.com/{tenant}/v2.0
                               #      https://{domain}.okta.com
                               #      https://accounts.google.com
IDP_REDIRECT_URI=https://yourdomain.com/auth/callback
IDP_GROUPS_CLAIM=groups        # The JWT claim containing group IDs (provider-specific)
                               # Entra: 'groups' | Okta: 'groups' | Google: varies

# Local Auth (dev and staging only — NEVER set to true in production)
LOCAL_AUTH_ENABLED=false

# GitLab
GITLAB_URL=https://gitlab.yourdomain.com
GITLAB_SERVICE_ACCOUNT_TOKEN=
GITLAB_PROJECT_ID=
GITLAB_WEBHOOK_SECRET=

# AI
ANTHROPIC_API_KEY=
ANTHROPIC_MODEL=claude-sonnet-4-6
OPENAI_API_KEY=                # For text-embedding-3-small
EMBEDDING_MODEL=text-embedding-3-small

# Search
TYPESENSE_HOST=
TYPESENSE_PORT=8108
TYPESENSE_API_KEY=

# Storage (PDF / assets)
STORAGE_DRIVER=s3              # or 'local' for dev
S3_BUCKET=
S3_REGION=
S3_KEY=
S3_SECRET=

# Mail
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASSWORD=
MAIL_FROM=policies@yourdomain.com

# Thresholds (tunable without code change)
CHANGE_MAGNITUDE_WARN_THRESHOLD=40    # 0-100, warn above this
CHANGE_MAGNITUDE_BLOCK_THRESHOLD=75   # 0-100, require justification above this
BOT_CONFIDENCE_THRESHOLD=0.72         # below this = show search fallback
BOT_TOP_K_CHUNKS=6                    # chunks to retrieve per question
```
