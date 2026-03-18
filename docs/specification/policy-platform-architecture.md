# Policy Library Platform — Architecture & Tech Stack

## Guiding Principles

1. **GitLab/GitHub does what it's good at.** Version control, branching, MR/PR workflow, diff rendering, inline commenting, branch protection, and webhooks are all solved problems. We do not re-implement any of these.
2. **Custom code fills genuine gaps.** Non-technical UX, role-based reader portal, policy templating, AI features, and Entra SSO are where we build.
3. **Decouple authoring from consumption.** The editorial workflow (git-backed) and the reader portal (RBAC, search, AI bot) are separate surfaces, independently deployable.
4. **Markdown is the canonical format, always.** No proprietary document formats. Everything renders from source.

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        AUTHORING SURFACE                        │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────────┐   │
│  │  Policy Editor  │    │     GitLab / GitHub (backend)    │   │
│  │  (WYSIWYG / MD) │◄──►│  - Repos (folder = category)    │   │
│  │  TipTap editor  │    │  - Branches (drafts)             │   │
│  │  Template picker│    │  - MRs/PRs (review/approval)     │   │
│  │  AI assistant   │    │  - Branch protection (gates)     │   │
│  │  Diff viewer    │    │  - Webhooks (event triggers)     │   │
│  └─────────────────┘    └──────────────────────────────────┘   │
└────────────────────────────────┬────────────────────────────────┘
                                 │ Webhooks + API
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                       APPLICATION CORE                          │
│                                                                 │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────────┐  │
│  │  Auth Service│  │Workflow Engine│  │  Publishing Service  │  │
│  │  Entra OIDC  │  │ State machine │  │  MD → HTML / PDF     │  │
│  │  SAML / OIDC │  │ Notifications │  │  Template injection  │  │
│  │  pluggable   │  │ Approval gates│  │  ToC, version history│  │
│  └──────────────┘  └───────────────┘  └─────────────────────┘  │
│                                                                 │
│  ┌──────────────┐  ┌───────────────┐  ┌─────────────────────┐  │
│  │  RBAC Service│  │ Search Service│  │    AI Service        │  │
│  │  Roles/groups│  │ Typesense     │  │  Change summaries    │  │
│  │  Policy→role │  │ Full-text idx │  │  RAG policy bot      │  │
│  │  mapping     │  │ Title+content │  │  Editor assistant    │  │
│  └──────────────┘  └───────────────┘  └─────────────────────┘  │
│                                                                 │
│                    PostgreSQL  │  Redis                         │
└────────────────────────────────┬────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                       READER PORTAL                             │
│                                                                 │
│  ┌─────────────────┐    ┌──────────────────────────────────┐   │
│  │  Policy Library │    │         Policy Bot               │   │
│  │  Filtered by    │    │  "What is the travel expense     │   │
│  │  user role      │    │   policy for overnight stays?"   │   │
│  │  Full-text srch │    │  RAG over indexed policies       │   │
│  │  Category tree  │    │  Cited, role-gated answers       │   │
│  └─────────────────┘    └──────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Component Detail

### 1. Git Backend: GitLab (Recommended) or GitHub

**Recommendation: Self-hosted GitLab CE** (Community Edition, free) or **GitLab SaaS** (paid but managed).

Reasons to prefer GitLab over GitHub here:
- Merge Request (MR) comments and approvals are more configurable than GitHub PRs for non-code use cases
- Built-in SAML SSO on all tiers (GitHub requires Enterprise Cloud for SAML)
- More granular branch protection and required approval rules
- Self-hosted option avoids your policy content leaving your infrastructure
- GitLab's API is slightly richer for programmatic MR management

**Repository structure:**
```
policy-library/
├── hr/
│   ├── recruitment-policy.md
│   ├── expense-policy.md
│   └── leave-policy.md
├── it/
│   ├── acceptable-use-policy.md
│   └── data-classification-policy.md
├── finance/
│   └── procurement-policy.md
└── _templates/
    └── policy-template.md
```

**Branch conventions:**
- `main` — published, live policies
- `draft/expense-policy-2025-update` — work in progress
- `review/expense-policy-2025-update` — submitted for review (MR open against main)

**Branch protection on `main`:**
- Requires N approvals (configurable per policy category)
- Can require specific approver roles (SME + Manager + Committee)
- No direct pushes — all changes via MR

**Service account:** The application uses a GitLab/GitHub service account with API access. Users never interact with git directly — all git operations are mediated through the application API.

---

### 2. Frontend: Next.js (App Router)

**Framework:** Next.js 14+ with App Router

**Why Next.js:**
- Server-side rendering for the reader portal (important for search SEO and fast first load)
- API routes for the application backend (reduces infrastructure complexity in v1)
- Excellent TypeScript support
- Easy deployment to Vercel, or self-hosted with Docker

**Two distinct frontend surfaces in one codebase:**

| Surface | Path | Users | Auth |
|---|---|---|---|
| Authoring / Admin | `/admin/*` | Policy authors, reviewers, approvers | Entra SSO required |
| Reader Portal | `/portal/*` | All staff | Entra SSO required |
| Policy Bot | `/portal/ask` | All staff (role-filtered) | Inherited from portal session |

---

### 3. Policy Editor

**Core editor: TipTap** (https://tiptap.dev)

TipTap is the right choice here because:
- It is ProseMirror-based — rock solid, used in production at scale
- Has a clean WYSIWYG mode that generates and parses Markdown natively
- Supports collaborative editing (via TipTap Collaboration, Yjs-based)
- Has a rich extension ecosystem: tables, code blocks, custom nodes
- MIT licensed

**Editor features to build on TipTap:**
- Standard rich text (headings, bold, italic, lists, tables, links)
- Markdown source toggle (for technical users who prefer raw MD)
- Template picker — loads a policy template into the editor as a starting state
- Related policy selector — dropdown that injects a `## Related Policies` section with links
- AI assistant panel (sidebar) — generates draft content, suggests phrasing
- Auto-save to git branch via API (debounced, every 30s or on explicit save)

**Diff viewer: Monaco Editor (diff mode)**

Microsoft's Monaco Editor (the engine behind VS Code) has a built-in side-by-side diff view. This is used on the review screen to show `draft vs published` or `this MR vs main`. It handles markdown diffs beautifully and is familiar to anyone who has used VS Code.

Rendered diff (formatted view) is also shown alongside raw diff using a custom side-by-side HTML render for non-technical reviewers.

---

### 4. Application Backend

**Language/Runtime:** TypeScript with Node.js

**Framework:** The Next.js API routes handle simple endpoints. For heavier async work (AI, publishing pipeline), a separate **Fastify** microservice.

**Database: PostgreSQL** (via Prisma ORM)

The database stores everything that git doesn't own:
- User profiles and role assignments
- Policy metadata (category, owner, review date, related policies, sensitivity level)
- Workflow state (mirrors MR state but enriched)
- Notification history
- Audit log (who approved what, when)
- AI-generated change summaries (cached)

**Cache / Queue: Redis** (via BullMQ)

Used for:
- Job queue for async AI tasks (change summary generation, RAG index updates)
- Caching rendered policy HTML (invalidated on MR merge)
- Session store

---

### 5. Authentication & Authorisation

**Authentication: Auth.js (formerly NextAuth)** with OIDC provider

Auth.js supports pluggable OIDC/OAuth2 providers. Entra ID (Azure AD) is configured as the primary provider using the standard OIDC flow.

```
User visits /admin or /portal
  → redirected to Entra login
  → Entra returns ID token with user claims (email, groups, roles)
  → Auth.js creates session
  → Application maps Entra groups → internal RBAC roles
```

**Making it pluggable:** Because Auth.js uses a provider abstraction, swapping from Entra to Okta, Google Workspace, or a GitLab OAuth flow requires changing one provider config, not re-engineering auth. This satisfies your pluggable SSO requirement cleanly.

**Authorisation: Custom RBAC in PostgreSQL**

Two separate RBAC layers:

*Authoring RBAC* (controls who can draft/review/approve):
| Role | Can do |
|---|---|
| `policy:author` | Create drafts, submit for review |
| `policy:reviewer` | Comment, request changes on MRs |
| `policy:approver:l1` | First-level approval (manager) |
| `policy:approver:l2` | Final approval (committee) |
| `policy:admin` | Manage categories, assign roles, publish |

*Reader RBAC* (controls which policies are visible in the portal):
- Policies are tagged with one or more `audience` groups (e.g., `all-staff`, `finance-team`, `it-team`, `executives`)
- A user's portal view is filtered to policies where their role(s) intersect with the policy's `audience` tags
- Sensitive policies (e.g., executive compensation, disciplinary procedures) get restricted `audience` tags

---

### 6. Workflow Engine

This is the application-layer logic that wraps GitLab's MR workflow and adds policy-specific semantics.

**State machine:**

```
DRAFT → SUBMITTED → UNDER_REVIEW → APPROVED_L1 → APPROVED_FINAL → PUBLISHED
                         ↓                ↓               ↓
                     CHANGES_REQUESTED  REJECTED      WITHDRAWN
                         ↓
                       DRAFT
```

**How it maps to GitLab:**
| Workflow State | GitLab equivalent |
|---|---|
| DRAFT | Branch exists, no MR |
| SUBMITTED | MR opened (draft) |
| UNDER_REVIEW | MR open, reviewer assigned |
| APPROVED_L1 | MR has 1 required approval |
| APPROVED_FINAL | MR has all required approvals |
| PUBLISHED | MR merged to main |

**Webhooks:** GitLab fires webhooks on MR events (opened, approved, commented, merged, closed). The application receives these, updates workflow state in PostgreSQL, and triggers notifications.

**Notifications:** Email (via Resend or SendGrid) + optional Teams/Slack webhook. Notifications fire on:
- Policy submitted for review (→ assigned reviewers)
- Review comment added (→ author)
- Approval received / rejected (→ author, next approver)
- Policy published (→ all users in audience groups)
- Policy approaching review date (→ policy owner)

**AI change guardrail:** When a new MR is created, a background job calculates the semantic change magnitude (word count delta + embedding cosine distance from previous version). If the change exceeds a configurable threshold, the MR is flagged in the workflow UI with a warning and requires a change justification field to be completed before submission. This is a soft gate — it warns, it does not block.

---

### 7. Publishing Service

When a policy MR is merged to `main`, a publishing pipeline runs:

1. **Template injection:** The raw markdown is wrapped in the standard policy boilerplate:
   - Policy title, owner, effective date, version number (auto-incremented)
   - Table of contents (auto-generated from headings)
   - Review date
   - Version history table (populated from git log)
   - Related policies (from metadata)
   - Policy purpose section

2. **Render to HTML:** Markdown → HTML using `unified` / `remark` / `rehype` pipeline. This is the canonical reader format.

3. **Render to PDF** (optional, for download): Using `Puppeteer` to print the styled HTML to PDF. PDF inherits the full branding/boilerplate.

4. **Search indexing:** The rendered plain-text content is sent to Typesense for indexing.

5. **RAG index update:** The policy chunks are re-embedded and upserted into the vector store.

**Policy template (markdown boilerplate):**

```markdown
---
title: {{title}}
owner: {{owner}}
audience: [{{audience_tags}}]
effective_date: {{effective_date}}
review_date: {{review_date}}
version: {{version}}
related_policies: [{{related_policy_ids}}]
---

# {{title}}

## Purpose
{{purpose}}

## Scope
{{scope}}

## Policy

{{body}}

## Related Policies
{{related_policies_list}}

---
*Version {{version}} | Effective {{effective_date}} | Owner: {{owner}}*
*Next review: {{review_date}}*
```

Front matter (YAML between `---` markers) is machine-readable metadata. The publishing service reads this to populate the boilerplate sections.

---

### 8. Search Service

**Engine: Typesense** (self-hosted, open source)

Typesense is chosen over Elasticsearch/OpenSearch because:
- Much simpler to operate (single binary, no JVM)
- Excellent full-text search quality including typo tolerance
- Fast enough for a policy library at any realistic scale
- Good Node.js SDK

**Indexed fields per policy:**
- `title` (weighted higher)
- `body_text` (plain text stripped of markdown)
- `category`
- `audience` (used to filter results by user role)
- `effective_date`, `version`

**Search is always role-filtered:** Every search query includes the user's audience groups as a filter. Users can never retrieve search results for policies they are not permitted to see, even if they craft the query to try.

---

### 9. AI Service

This is a separate Fastify microservice, independently deployable and scalable.

**LLM Provider: Anthropic Claude API** (claude-sonnet-4-6)

**Framework: LlamaIndex (TypeScript)** for the RAG pipeline

**Vector Store: pgvector** (PostgreSQL extension — no extra infrastructure in v1)

#### Feature A: Change Summary Generation

Triggered when an MR is opened. The service:
1. Fetches the diff from GitLab API
2. Constructs a prompt: *"Summarise the changes in this policy update in plain English for a non-technical reviewer. Be specific about what has changed, what has been added, and what has been removed. Maximum 150 words."*
3. Caches the summary in PostgreSQL, attached to the workflow record
4. Displays in the MR review UI above the diff

#### Feature B: Editor AI Assistant

Available as a sidebar panel in the editor. The user can:
- **"Draft this section"** — provide a heading and bullet points, Claude generates a full paragraph in policy-appropriate language
- **"Check consistency"** — Claude compares the current draft against existing published policies in the same category and flags contradictions or overlaps
- **"Suggest related policies"** — Claude identifies potentially related policies from the library

All editor AI calls are direct Claude API calls from the server (never client-side, to protect the API key).

#### Feature C: Policy Bot (RAG)

The reader-facing question-answering bot. Architecture:

```
User question
    ↓
Query rewriting (Claude rewrites to canonical form)
    ↓
Role-filtered vector search (pgvector, cosine similarity)
    ↓
Top-K chunks retrieved (with source + section metadata)
    ↓
Claude generates answer grounded only in retrieved chunks
    ↓
Response includes:
  - Plain English answer
  - Source citations (policy name, section, link)
  - "I don't know" fallback if confidence < threshold
  - Links to full policy documents
```

**Key guardrails:**
- The prompt instructs Claude to answer *only* from retrieved context, never from its training knowledge
- If no relevant chunks are retrieved, the bot returns "I couldn't find a policy that covers this — here are the closest results" and surfaces search results instead
- All bot responses include source links so users can verify
- Bot responses are logged for quality review and to identify policy gaps

---

### 10. Infrastructure & Deployment

**Containerisation: Docker + Docker Compose** (development) → **Kubernetes** (production, if scale demands) or a managed PaaS.

**Recommended deployment stack (v1, pragmatic):**

| Component | Hosted on |
|---|---|
| Next.js app | Vercel (simplest) or self-hosted Docker |
| AI microservice | Fly.io or Railway (easy Docker deploy) |
| PostgreSQL | Supabase (managed) or RDS |
| Redis | Upstash (serverless) or ElastiCache |
| Typesense | Self-hosted on a small VM (e.g., Hetzner €5/mo) |
| GitLab | GitLab SaaS (free tier works for v1) or self-hosted |

**Alternatively, fully self-hosted** (if data sovereignty is a requirement):
- All services on a Kubernetes cluster (GKE, AKS, or on-prem)
- GitLab CE self-hosted
- Supabase self-hosted or managed Postgres
- Everything behind your corporate VPN / Entra Conditional Access

---

## Phased Delivery Plan

### Phase 1 — Core Authoring & Publication (Months 1–4)
*Goal: Replace current policy chaos with a governed, structured library.*

- GitLab setup with repo structure and branch protection rules
- Auth.js + Entra SSO integration
- Basic policy editor (TipTap) with template support
- Workflow engine: draft → review → approved → published states
- MR-based review with Monaco diff viewer
- Publishing pipeline: template injection, HTML render, PDF export
- Role-based reader portal with full-text search (Typesense)
- Email notifications for workflow events

**End state:** A working, governed policy library with non-technical authoring, structured approval, and a role-filtered reader portal.

### Phase 2 — AI Features (Months 4–7)
*Goal: Reduce manual effort and improve policy consumption.*

- AI change summary generation on MR open
- Policy bot (RAG) in the reader portal
- Editor AI assistant (draft section, check consistency)
- AI-suggested related policies
- Change magnitude guardrail on submission

**End state:** AI-assisted authoring and a conversational policy Q&A bot.

### Phase 3 — Governance & Analytics (Months 7–9)
*Goal: Enterprise-grade compliance features.*

- Policy review date reminders and escalation
- Attestation tracking (did this user read this policy?)
- Audit log export (who approved what, when)
- Policy gap analysis (bot questions that returned no answer → flag for new policy)
- Advanced RBAC (per-policy sensitivity overrides)
- Multiple SSO provider support (Okta, Google Workspace)

---

## Key Technology Decisions Summary

| Concern | Decision | Rationale |
|---|---|---|
| Document store | GitLab/GitHub (git) | Versioning, diff, PR workflow for free |
| Document format | Markdown | Portable, diffable, renderable anywhere |
| Editor | TipTap | ProseMirror-based, WYSIWYG + MD, MIT |
| Diff view | Monaco Editor | VS Code quality, familiar, handles MD well |
| Frontend | Next.js (TypeScript) | SSR, API routes, excellent ecosystem |
| Auth | Auth.js + OIDC | Pluggable, supports Entra + others |
| Database | PostgreSQL | Reliable, pgvector for AI embeddings |
| Search | Typesense | Simple to operate, fast, role-filterable |
| AI/RAG | LlamaIndex + Claude | Best-in-class RAG tooling + LLM quality |
| Queue | BullMQ + Redis | Reliable async job processing |
| PDF export | Puppeteer | Print-to-PDF from styled HTML |

---

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Non-technical users find git concepts confusing | They never see git. All git operations are abstracted behind application UI. "Submit for review" = open MR. They see policy names and workflow states. |
| GitLab goes down / rate limits hit | Application caches rendered policies. Read-only portal continues to work. Writes queue until GitLab recovers. |
| AI bot gives wrong policy answers | Strict RAG guardrails (answer only from context), mandatory source citations, "I don't know" fallback, logs for review. |
| Policy content leaving corporate infrastructure | GitLab self-hosted + self-hosted deployment + Anthropic's data processing agreement covers this. AI calls can be directed to Azure OpenAI if Anthropic is not approved. |
| Scope creep on AI features | Phase 2 is strictly time-boxed. AI features are a separate service — they do not block Phase 1 delivery. |
| Entra group → role mapping maintenance | Sync script runs nightly from Entra Graph API. Role mapping is configuration, not code. |
