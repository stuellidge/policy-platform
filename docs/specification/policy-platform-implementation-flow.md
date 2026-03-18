# Policy Library Platform — Implementation Flow
## Shaped for Early Human Testability

---

## Governing Principle: Vertical Slices, Not Horizontal Layers

The conventional failure mode on a project like this is building infrastructure horizontally:
*"Month 1: Auth. Month 2: Editor. Month 3: Workflow. Month 4: Portal. Month 5: AI. Month 6: Show someone."*

By month 6, the riskiest assumptions — can non-technical policy authors actually use this? does the diff view make sense to a manager? — have been baked in and are expensive to unpick.

Instead, every milestone in this plan delivers a **complete, narrow, vertical slice**: a thin strip of functionality that runs all the way from the user's browser to GitLab and back. Each slice is testable by a real human the day it is built. Each subsequent slice widens the strip.

---

## The Assumptions That Must Be Validated Early

Before writing a line of code, rank what you actually don't know:

| Assumption | Risk if wrong | When to test |
|---|---|---|
| Non-technical authors can use a WYSIWYG-to-git workflow without confusion | High — core UX thesis of the entire product | Milestone 1 |
| Reviewers can interpret a markdown diff view | High — the PR-review-as-approval concept is novel for policy people | Milestone 2 |
| The two-stage approval routing maps to how your org actually approves policies | Medium — workflow may need reconfiguring | Milestone 2 |
| The template/boilerplate produces documents people consider "finished" | Medium — aesthetic and structural expectations vary | Milestone 3 |
| The policy bot answers questions reliably enough to be trusted | High — a bot that gives wrong answers is worse than no bot | Milestone 5 |
| Role-based filtering correctly segments policies for each audience | Medium — RBAC design is only as good as your role taxonomy | Milestone 4 |

---

## The Five Milestones

```
M1          M2            M3              M4            M5
[Author]──►[Review]──►[Publish]──►[Read+Search]──►[AI Bot]
   │           │           │            │              │
 Day 20     Day 45       Day 70        Day 95        Day 130
   │           │           │            │              │
Policy      Reviewer    Committee    All-staff      Power
author      + manager   + owner      pilot          users
tests it    test it     tests it     test it        test it
```

Each milestone has:
- A **definition of done** that is human-testable, not technically defined
- A **who tests it** list (real users, not developers)
- A **what to learn** list (specific questions to answer)
- A **go/no-go** gate before proceeding

---

## Milestone 1: "Can a policy author write and save something?" *(Target: Day 20)*

### What gets built

**GitLab setup (Days 1–5):**
- Single GitLab project with the agreed folder structure
- `main` branch set as protected (no direct push)
- Service account created for application API calls
- Branch naming conventions configured

**Thin auth slice (Days 3–8):**
- Auth.js wired to Entra ID (OIDC)
- Single hardcoded test user can log in
- Session persists correctly
- No RBAC yet — everyone who logs in gets full access

**Minimal editor (Days 6–18):**
- TipTap editor renders in the browser
- Standard formatting: headings, bold, italic, bullet lists, tables
- Markdown source toggle (for technical users)
- A single hardcoded policy template loads on "New Policy"
- Save button: creates a GitLab branch (`draft/[policy-title]-[date]`) and commits the markdown file
- No workflow state, no approval, no portal — just write and save

**Confirmation screen:**
- After save: "Your draft has been saved. Branch: `draft/expense-policy-2025-03`"
- Link to view the raw file in GitLab (this is temporary; the UX will improve later)

### Definition of done (human-testable)
> A non-technical policy author, given only a link and their Entra credentials, can log in, start a new policy from the template, write content, and save it — without any guidance from the development team.

### Who tests it
- 2–3 real policy authors from the organisation
- At least one who is not particularly technical

### What to learn
- Does the editor feel familiar enough? (Compare to Word / Google Docs expectation)
- Is the template structure right, or does it miss standard sections?
- Do authors understand what "saving" means in this context?
- Any friction points that cause confusion or hesitation?

### Go / no-go gate
**Proceed only if:** Authors can complete the task without assistance, and feedback does not reveal a fundamental UX mismatch. If the editor model is wrong (e.g., people expect to paste from Word and the formatting breaks), fix it before building the workflow on top.

---

## Milestone 2: "Can a reviewer see what changed and respond?" *(Target: Day 45)*

### What gets built

**Submit for review (Days 21–26):**
- "Submit for Review" button opens a GitLab MR (draft MR → open MR) via API
- Author sees a confirmation: "Submitted. Your reviewer has been notified."
- Hardcoded reviewer assignment for now (configurable later)
- Email notification fires to the assigned reviewer

**Review screen (Days 24–38):**
- Reviewer lands on a review page for the submitted policy
- **Side-by-side diff view** (Monaco Editor): left = `main` (current published or blank), right = draft
- Rendered preview pane: shows the formatted policy as it will appear when published
- Inline comment box: reviewer can leave a comment on the whole MR (not yet line-level)
- Two action buttons: "Request Changes" and "Approve"
- Both buttons update the MR state in GitLab and send an email to the author

**Author response (Days 36–42):**
- Author receives email with reviewer comment
- Author can reopen their draft, make edits, and re-save (new commit to existing branch)
- Review screen updates to show the latest version

**Basic workflow state display (Days 40–45):**
- Policy list view shows each policy with its current state: Draft / In Review / Changes Requested
- No portal yet — this is the admin/author view only

### Definition of done (human-testable)
> A reviewer, given only a link and their credentials, can open a submitted policy, read the diff, understand what changed, leave a comment, and either approve or request changes — without any guidance from the development team.

### Who tests it
- 2–3 reviewers (managers / subject matter experts)
- Have them review a real draft policy, not a dummy one

### What to learn
- Does the diff view make sense to a non-technical reviewer? (This is the highest-risk UX assumption in the product)
- Is the rendered preview necessary, or is the diff sufficient?
- Is email notification enough, or do reviewers need a dashboard?
- Does the two-action model (Approve / Request Changes) map to how people actually work, or are there missing states?

### Go / no-go gate
**Proceed only if:** Reviewers can interpret the diff view without explanation. If this fails, it is a fundamental assumption about the product that needs to be resolved — possibly by investing in a richer visual diff (change highlighting in the rendered view, not just raw markdown diffs) before proceeding to approval workflow.

---

## Milestone 3: "Can a policy get fully approved and published?" *(Target: Day 70)*

### What gets built

**Two-stage approval (Days 46–58):**
- First approver (L1: manager/SME) — already wired from M2
- Second approver (L2: committee/owner) — added as a required second approval on the MR
- MR transitions through states: `APPROVED_L1` → `APPROVED_FINAL`
- Both approvers receive email at the right time in sequence

**Publishing pipeline (Days 55–65):**
- On final MR approval, a GitLab webhook fires to the application
- Publishing service runs:
  - Template injection: wraps markdown in boilerplate (title, owner, effective date, version, ToC, related policies section)
  - Auto-increment version number
  - Auto-generate Table of Contents from headings
  - Render to HTML (stored in database, not in GitLab)
  - Render to PDF (Puppeteer)
- Policy status moves to `PUBLISHED`
- Published policy is accessible at a URL (no auth yet — just a direct link for testing)

**Version history (Days 63–70):**
- Each published version is archived (both HTML and the source markdown)
- "Version History" tab on the published policy shows previous versions with dates and change authors
- Diff between any two published versions is viewable

### Definition of done (human-testable)
> A policy owner can take a draft all the way through both approval stages and see the final published document — with correct boilerplate, ToC, version number, and PDF download — without guidance from the development team.

### Who tests it
- Full workflow end-to-end with real participants: author + L1 approver + L2 approver
- Use a real policy that the organisation actually needs

### What to learn
- Does the boilerplate layout match what the organisation considers a "finished" policy document?
- Is the ToC auto-generation reliable for the heading structures authors actually use?
- Does the two-stage approval routing match the real org approval process, or does it need to be more flexible?
- Is the PDF output print-ready, or does it need styling work?

### Go / no-go gate
**Proceed only if:** The published output meets the organisation's standard for what a policy document should look like. Template and layout problems are much cheaper to fix here than after 50 policies have been authored.

---

## Milestone 4: "Can colleagues find and read the policies they need?" *(Target: Day 95)*

### What gets built

**Reader portal (Days 71–80):**
- Separate surface from the authoring admin area (`/portal` vs `/admin`)
- Entra SSO required to access
- Lists all published policies the logged-in user is permitted to see
- Category tree navigation (mirrors GitLab folder structure)
- Basic card layout: title, category, effective date, policy owner

**RBAC reader filtering (Days 78–88):**
- Policies tagged with `audience` groups in their front matter (e.g., `all-staff`, `finance`, `it`)
- User's Entra groups are mapped to audience tags on login
- Portal only shows policies whose audience includes the user's groups
- Sensitive policies are invisible to unauthorised users — they do not appear in search results

**Full-text search (Days 85–92):**
- Typesense indexing pipeline: on publish, policy content is indexed
- Search bar in portal header: searches title and body content
- Results are role-filtered (Typesense filter applied per-query using user's groups)
- Results show policy title, category, and a short excerpt with the search term highlighted

**Policy detail view (Days 90–95):**
- Clicking a policy shows the full rendered HTML document
- Sidebar: metadata (owner, effective date, version, review date)
- Download PDF button
- Related policies shown as links

### Definition of done (human-testable)
> A colleague with no prior knowledge of the platform can find the answer to "where is the expense policy?" and "what is the travel policy for overnight stays?" using only the portal — without asking anyone for help.

### Who tests it
- Broader pilot: 10–20 colleagues across different roles/departments
- Include people who are known to struggle with finding policies currently
- Test with real published policies from M3

### What to learn
- Is the category tree intuitive, or do people search rather than browse?
- Is the role filtering correct — are people seeing policies they should, and not seeing ones they shouldn't?
- Is full-text search finding what people expect?
- What's the first thing people try to find? (Reveals whether your taxonomy matches mental models)

### Go / no-go gate
**Proceed only if:** Users can reliably find policies without guidance. If the taxonomy is wrong, fix it before the AI bot is trained on the same structure. If role filtering is producing unexpected gaps, resolve the RBAC model before expanding the pilot.

---

## Milestone 5: "Can the policy bot answer questions reliably?" *(Target: Day 130)*

This milestone is intentionally later and gated. The bot is only useful if the policy library it answers from is populated with real, published, high-quality policies. Building it before M3 and M4 are validated produces a bot that either has nothing to answer from, or answers from draft/messy content.

### What gets built

**RAG pipeline (Days 96–110):**
- On policy publish, document is chunked and embedded (text-embedding-3-small or equivalent)
- Embeddings stored in pgvector alongside chunk metadata (policy title, section heading, version, audience tags)
- Audience tags stored per-chunk: only chunks the user is permitted to see can be retrieved

**Policy bot UI (Days 108–120):**
- Chat interface in the portal sidebar (accessible from any page)
- User types a natural language question
- System retrieves top-K relevant chunks (role-filtered)
- Claude generates a grounded answer from retrieved chunks only
- Every answer includes: the answer in plain English, source citation(s) with policy name + section, links to the full policy
- "I couldn't find a specific policy on this — here are the closest results" fallback
- Unanswered questions are logged for policy gap analysis

**Guardrails (Days 118–128):**
- Confidence threshold: if retrieved chunks have low similarity scores, show search results rather than a synthesised answer
- Hallucination prevention: system prompt instructs Claude to answer only from context, never from training knowledge, and to say "I don't know" if the answer isn't in the retrieved content
- Answer logging for quality review

**Feedback mechanism (Days 125–130):**
- Thumbs up / thumbs down on each bot response
- Negative feedback prompts: "What was wrong? — Wrong answer / Incomplete / Couldn't find the policy"
- Logged for ongoing quality review

### Definition of done (human-testable)
> A colleague can ask the bot "what is the policy for booking a hotel for an overnight work trip?" and receive a correct, cited answer — without the bot fabricating content or pointing to the wrong policy.

### Who tests it
- Red team exercise: a small group tries to get the bot to give wrong or uncited answers
- Broad pilot: the M4 cohort is given access and asked to use the bot as their first port of call for policy questions for one week
- Policy owners review whether their policies are being answered correctly

### What to learn
- What percentage of real questions can the bot answer correctly from existing content?
- What are the most common unanswered questions? (These are your policy gap list)
- Do users trust the bot, or do they verify in the source document? (Trust calibration)
- Does the role-filtering work correctly — can users get answers about policies they are not authorised to see?

### Go / no-go gate
**Do not make the bot the primary interface for policy questions until:** It answers correctly in >85% of test cases, and every answer has a valid source citation. A bot that is wrong 20% of the time but confident damages organisational trust far more than having no bot.

---

## Parallel Workstreams

Some work can run in parallel to the milestones without blocking them:

```
Milestone track:  M1──────M2──────M3──────M4──────M5
                  │
Infrastructure:   GitLab setup ──► Docker/CI ──► Staging env ──► Prod env
                                                 (run in parallel with M2)
                  │
Design system:    Basic styles ──► Component library ──► Polish pass
                  (start in M1, iterate through M4)
                  │
Content:          Template design ──► 5 pilot policies ──► Full library
                  (start M1, pilot policies ready for M3 testing)
```

The CI/CD pipeline and staging environment should be set up by M2, not M3 — you need to be able to deploy rapidly once real users are testing.

---

## Testing Cadence

| After milestone | Session type | Participants | Duration | Output |
|---|---|---|---|---|
| M1 | Usability session | 2–3 policy authors | 45 min each | List of editor UX issues, template gaps |
| M2 | Workflow walkthrough | 2 reviewers + 1 author | 1 hour | Approval flow issues, diff view feedback |
| M3 | End-to-end pilot | Full approval chain for 2–3 real policies | 1–2 weeks | Published policy quality, workflow gaps |
| M4 | Broad portal pilot | 10–20 colleagues | 2 weeks | Search quality, taxonomy issues, RBAC gaps |
| M5 | Bot red team + broad pilot | Small red team + M4 cohort | 2 weeks | Bot accuracy report, policy gap list |

**Key principle:** Every testing session should be observed (not just surveyed). Watch what people do, not just what they say. The moment a user pauses, looks confused, or clicks the wrong thing is more valuable than any feedback form.

---

## What Deliberately Does Not Get Built Until Validated

These features are designed but not built until the relevant milestone has been validated:

| Feature | Held back until |
|---|---|
| AI change summary on MR | M2 validated (you need the review screen to exist first) |
| Editor AI assistant | M1 validated (only useful if basic editor works) |
| Policy review date reminders | M3 validated (only relevant once policies are being published) |
| Attestation tracking | M4 validated (only after portal is confirmed working) |
| Multi-SSO provider support | M4 validated (Entra is the only provider needed for internal use) |
| Advanced RBAC overrides | M4 validated (extend the model only once basic filtering is correct) |
| Policy gap analysis dashboard | M5 validated (requires a working bot and logged questions) |

This is not feature deferral — it is dependency management. Each of these features is only testable and useful after the layer beneath it is confirmed.

---

## Environment Strategy

| Environment | Purpose | Stands up by |
|---|---|---|
| **Local dev** | Individual developer machines | Day 1 |
| **Shared dev** | Shared GitLab instance, no real data | Day 5 |
| **Staging** | Production-like, test Entra SSO, real data structure | M2 (Day 35) |
| **Production** | Live, real users, real policies | M3 complete (Day 70) |

**Important:** Real policy authors should be testing in **staging with real Entra SSO** from M1 onwards — not against a mocked auth system. Auth issues that only appear with real Entra configuration (group claims, MFA, conditional access) are expensive to discover in production.

---

## Sprint Structure Recommendation

Two-week sprints with a fixed demo at the end of each sprint. The demo rule: **it must be demonstrated by someone who did not build it**. If the PM or a policy author cannot demo the feature, it is not done.

```
Sprint 1  (Days 1–14):   GitLab setup + Auth + Editor skeleton
Sprint 2  (Days 15–28):  Editor complete + Save to git → M1 TEST
Sprint 3  (Days 29–42):  Submit for review + Diff view
Sprint 4  (Days 43–56):  Comments + Approve/Reject + Email → M2 TEST
Sprint 5  (Days 57–70):  Two-stage approval + Publishing pipeline → M3 TEST
Sprint 6  (Days 71–84):  Reader portal + RBAC
Sprint 7  (Days 85–98):  Search (Typesense) + Policy detail → M4 TEST
Sprint 8  (Days 99–112): RAG pipeline + Embedding
Sprint 9  (Days 113–126): Bot UI + Guardrails
Sprint 10 (Days 127–140): Bot testing, feedback loop, hardening → M5 TEST
```

---

## Risk Register for Implementation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Entra SSO group claims don't contain the right data for RBAC | Medium | High | Audit Entra group structure in week 1, before any RBAC code is written |
| Non-technical authors find markdown diff view unreadable | Medium | High | M2 go/no-go gate; have a rendered-diff fallback designed but not built |
| GitLab API rate limits hit during heavy review activity | Low | Medium | Implement request queuing from the start; cache MR state locally |
| Policy template doesn't match org document standards | Medium | Medium | Get sign-off on template structure before M1 testing, not after |
| Claude API latency makes bot feel slow | Low | Medium | Stream responses; show typing indicator; set expectation in UI |
| Real policies contain sensitive data that shouldn't train the RAG index | Medium | High | RBAC per chunk from day one of RAG build; no shortcuts here |
