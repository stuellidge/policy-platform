# Milestone Gate Checklists

Each milestone ends with a **go/no-go gate tested by real users, not developers**.
Do not begin the next milestone until the current one has been human-validated.

The gate is not "tests pass and code is merged". It is "real users can complete
the task without guidance, and the answers to the learning questions do not
reveal a fundamental assumption is wrong."

Use this skill to generate the checklist for a specific milestone to share
with test participants and record outcomes.

---

## Milestone 1 — "Can a policy author write and save something?" *(Target: Day 20)*

### What was built
- GitLab project with folder structure and branch protection on `main`
- OIDC auth (Entra ID) — single test user can log in, session persists
- TipTap editor: headings, bold/italic, lists, tables, markdown toggle
- Single hardcoded policy template loads on "New Policy"
- Save creates a GitLab branch (`draft/[title]-[date]`) and commits the file
- Confirmation screen shows branch name and a link to the raw file in GitLab

### Definition of done
> A non-technical policy author, given only a link and their Entra credentials,
> can log in, start a new policy from the template, write content, and save it —
> **without any guidance from the development team.**

### Who tests it
- 2–3 real policy authors from the organisation
- At least one who is not particularly technical

### What to learn
- [ ] Does the editor feel familiar? (Expectation: like Word or Google Docs)
- [ ] Is the template structure right, or does it miss standard sections?
- [ ] Do authors understand what "saving" means in this context?
- [ ] Any friction points that cause confusion or hesitation?

### Go / no-go gate
**Proceed to M2 only if:** Authors can complete the task without assistance,
and feedback does not reveal a fundamental UX mismatch.

**If the editor model is wrong** (e.g., people expect to paste from Word and
formatting breaks, or the WYSIWYG feels unfamiliar) — fix this before building
the workflow on top. Workflow complexity on a broken editor foundation is very
expensive to unpick.

### Features deliberately held back until this gate passes
- Editor AI assistant (only useful if basic editor works)

---

## Milestone 2 — "Can a reviewer see what changed and respond?" *(Target: Day 45)*

### What was built
- Submit for Review: opens a GitLab MR, notifies reviewer by email
- Side-by-side Monaco diff view (main branch vs draft)
- Rendered preview pane alongside the diff
- Comment box, "Request Changes" and "Approve" buttons
- Both buttons update MR state in GitLab and email the author
- Author can re-edit after changes requested and re-save to the same branch
- Policy list shows current state per policy (Draft / In Review / Changes Requested)

### Definition of done
> A reviewer, given only a link and their credentials, can open a submitted
> policy, read the diff, understand what changed, leave a comment, and either
> approve or request changes — **without any guidance from the development team.**

### Who tests it
- 2–3 reviewers (managers / subject matter experts)
- Have them review a **real draft policy**, not a dummy one

### What to learn
- [ ] Does the diff view make sense to a non-technical reviewer? *(Highest-risk UX assumption in the product)*
- [ ] Is the rendered preview necessary, or is the raw diff sufficient?
- [ ] Is email notification enough, or do reviewers need a dashboard to track outstanding reviews?
- [ ] Does the two-action model (Approve / Request Changes) match how people actually work, or are there missing states?

### Go / no-go gate
**Proceed to M3 only if:** Reviewers can interpret the diff view without
explanation.

**If this fails:** It is a fundamental product assumption that needs resolving —
possibly by investing in a richer visual diff (change highlighting in the
rendered view, not just raw markdown) before proceeding. Do not build the
two-stage approval workflow on top of a review surface that reviewers cannot use.

### Features deliberately held back until this gate passes
- AI change summary on MR (needs the review screen to exist and be validated first)

---

## Milestone 3 — "Can a policy get fully approved and published?" *(Target: Day 70)*

### What was built
- Two-stage approval: L1 (manager/SME) → L2 (committee/owner), sequential
- Email notification to the right approver at the right stage
- Publishing pipeline on final approval:
  - Template injection: title, owner, effective date, version number, ToC, related policies, version history
  - Rendered to HTML (stored in database)
  - PDF generated via Puppeteer
- Policy status moves to Published, accessible at a direct URL
- Version history tab: previous versions with dates, change authors, and diff between versions

### Definition of done
> A policy owner can take a draft all the way through both approval stages and
> see the final published document — with correct boilerplate, ToC, version
> number, and PDF download — **without guidance from the development team.**

### Who tests it
- Full end-to-end with real participants: author + L1 approver + L2 approver
- Use a **real policy the organisation actually needs** (not dummy content)

### What to learn
- [ ] Does the boilerplate layout match what the organisation considers a "finished" policy document?
- [ ] Is ToC auto-generation reliable for the heading structures authors actually use?
- [ ] Does the two-stage approval routing match the real org approval process, or does it need to be more configurable?
- [ ] Is the PDF print-ready, or does it need styling work?

### Go / no-go gate
**Proceed to M4 only if:** The published output meets the organisation's standard
for what a policy document should look like.

**Template and layout problems are much cheaper to fix here** than after 50
policies have been authored against the wrong structure. Get explicit sign-off
from the policy team on the published output before opening the portal.

### Features deliberately held back until this gate passes
- Policy review date reminders (only relevant once policies are being published)

### Production environment
M3 complete (Day 70) is the target date for the production environment to be
live with real users and real policies.

---

## Milestone 4 — "Can colleagues find and read the policies they need?" *(Target: Day 95)*

### What was built
- Reader portal at `/portal` (separate from authoring `/admin`)
- Entra SSO required to access
- Category tree navigation mirroring GitLab folder structure
- Policy card list: title, category, effective date, policy owner
- RBAC audience filtering: users see only policies matching their Entra groups
- Full-text search via Typesense (title + body, role-filtered per query)
- Search results with excerpt and highlighted search terms
- Policy detail view: full rendered HTML, metadata sidebar, PDF download, related policies

### Definition of done
> A colleague with no prior knowledge of the platform can find the answer to
> "where is the expense policy?" and "what is the travel policy for overnight
> stays?" using only the portal — **without asking anyone for help.**

### Who tests it
- Broader pilot: 10–20 colleagues across different roles and departments
- Include people who are known to struggle with finding policies currently
- Test with real published policies from M3

### What to learn
- [ ] Is the category tree intuitive, or do people search rather than browse?
- [ ] Is role filtering correct — seeing what they should, not seeing what they shouldn't?
- [ ] Is full-text search finding what people expect? Any surprising misses?
- [ ] What's the first thing people try to find? (Reveals whether your taxonomy matches mental models)

### Go / no-go gate
**Proceed to M5 only if:** Users can reliably find policies without guidance.

**If the taxonomy is wrong**, fix it before the AI bot is trained on the same
structure — the bot's answers are only as good as the structure it retrieves from.

**If role filtering has unexpected gaps**, resolve the RBAC model before the
pilot expands. A user who can't see a policy they need will stop trusting the
portal entirely.

### Features deliberately held back until this gate passes
- Attestation tracking (only after portal is confirmed working)
- Multi-SSO provider support (Entra is the only provider needed for internal use)
- Advanced RBAC overrides (extend the model only once basic filtering is correct)

---

## Milestone 5 — "Can the policy bot answer questions reliably?" *(Target: Day 130)*

### What was built
- RAG pipeline: on publish, document chunked and embedded, stored in pgvector
- Audience tags on each chunk: role-filtered retrieval at query time
- Chat interface in portal sidebar (accessible from any page)
- Query rewriting → embedding → vector search → grounded Claude response
- Every answer includes: plain English answer, source citations with policy name + section + link
- "I couldn't find a specific policy on this" fallback when confidence < threshold
- Unanswered questions logged for policy gap analysis
- Thumbs up/down feedback on each response

### Definition of done
> A colleague can ask the bot "what is the policy for booking a hotel for an
> overnight work trip?" and receive a correct, cited answer — **without the bot
> fabricating content or pointing to the wrong policy.**

### Who tests it
- **Red team exercise first:** A small group actively tries to get the bot to give wrong or uncited answers
- **Broad pilot:** The M4 cohort uses the bot as first port of call for policy questions for one week
- **Policy owners:** Review whether their policies are being answered correctly

### What to learn
- [ ] What percentage of real questions can the bot answer correctly from existing content?
- [ ] What are the most common unanswered questions? (This is your policy gap list)
- [ ] Do users trust the bot, or do they verify in the source document? (Trust calibration)
- [ ] Does role-filtering work correctly — can users get answers about policies they are not authorised to see?

### Go / no-go gate
**Do not make the bot the primary interface for policy questions until:**
- It answers correctly in **>85% of test cases**
- **Every answer has a valid source citation**

A bot that is wrong 20% of the time but confident damages organisational trust
far more than having no bot at all. The fallback ("I couldn't find a policy")
is a feature, not a failure.

### Features deliberately held back until this gate passes
- Policy gap analysis dashboard (requires a working bot and a log of unanswered questions)

---

## Testing Cadence Summary

| After milestone | Session type | Participants | Duration | Output |
|---|---|---|---|---|
| M1 | Usability session | 2–3 policy authors | 45 min each | Editor UX issues, template gaps |
| M2 | Workflow walkthrough | 2 reviewers + 1 author | 1 hour | Approval flow issues, diff view feedback |
| M3 | End-to-end pilot | Full approval chain for 2–3 real policies | 1–2 weeks | Published quality, workflow gaps |
| M4 | Broad portal pilot | 10–20 colleagues | 2 weeks | Search quality, taxonomy, RBAC gaps |
| M5 | Bot red team + broad pilot | Small red team + M4 cohort | 2 weeks | Bot accuracy report, policy gap list |

**Key principle:** Every testing session should be **observed**, not just surveyed.
Watch what people do, not just what they say. The moment a user pauses, looks
confused, or clicks the wrong thing is more valuable than any feedback form.

The demo rule for sprint reviews: **it must be demonstrated by someone who did
not build it.** If a policy author or PM cannot demo the feature, it is not done.
