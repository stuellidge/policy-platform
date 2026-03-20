# GitLab Integration

PolicyHub uses GitLab as its document store. All Markdown content, file
history, branches, MRs, diffs, and MR-level comments are **owned by GitLab**.
The application never re-implements these — it calls the GitLab API.

All GitLab operations are mediated through `app/services/git/gitlab_service.ts`.
Users never interact with git directly. Every git operation the application
performs goes through this single service.

---

## Data Ownership Boundary

| GitLab owns | PostgreSQL owns |
|-------------|-----------------|
| Markdown content | Policy metadata (title, owner, dates, audience) |
| File history and commit SHAs | Workflow state (enriched mirror of MR state) |
| Branches | User roles and audience group assignments |
| MRs, approvals, and MR-level comments | Rendered HTML and PDF |
| Diffs | AI embeddings (pgvector) |
| Webhooks | Audit logs, notifications, sessions |

The two systems are joined by two foreign keys into GitLab:
- `policies.gitlab_file_path` — e.g. `hr/expense-policy.md`
- `workflow_instances.gitlab_mr_iid` — the MR number within the project

Never store in PostgreSQL what GitLab already owns. When you need the diff
content, call the GitLab API. When you need who approved what and when, read
PostgreSQL.

---

## Environment Variables

```bash
GITLAB_URL=https://gitlab.yourdomain.com      # Base URL, no trailing slash
GITLAB_SERVICE_ACCOUNT_TOKEN=                  # Personal access token with api scope
GITLAB_PROJECT_ID=                             # Numeric project ID
GITLAB_WEBHOOK_SECRET=                         # Shared secret for verifying webhook requests
```

The service account token must have `api` scope. It is used for all GitLab
API calls — the application acts as a service account, not as the individual
user.

---

## Branch Naming Conventions

```
draft/[policy-slug]-[YYYY-MM]       # Active draft branch
review/[policy-slug]-[YYYY-MM]      # Branch when MR is open (optional rename)
main                                 # Published policies only — branch protected,
                                     # no direct push, all changes via MR
```

Examples:
```
draft/expense-policy-2025-03
draft/it-acceptable-use-2025-06
```

The branch name is stored in `workflow_instances.gitlab_branch_name` and used
for all subsequent API calls for that workflow instance.

---

## GitLab API Patterns per Workflow Operation

### Create policy — branch + file

Called when `POST /api/v1/policies` creates a new policy record.

```typescript
// 1. Create the branch from main
await gitlabService.createBranch({
  branchName: `draft/${policy.slug}-${DateTime.now().toFormat('yyyy-MM')}`,
  ref: 'main',
})

// 2. Create the file on the branch with the template content
await gitlabService.createFile({
  filePath: policy.gitlabFilePath,   // e.g. 'hr/expense-policy.md'
  branch: branchName,
  content: templateService.render(policy),
  commitMessage: `feat: create ${policy.title} draft`,
})
```

### Save editor content — commit to branch

Called by `PUT /api/v1/policies/:id/content`. Debounced on the client
(at most once per 30 seconds during active editing, always on explicit Save).

```typescript
// Check if file already exists on the branch
const existing = await gitlabService.getFile({
  filePath: policy.gitlabFilePath,
  ref: branchName,
})

if (existing) {
  // Update existing file
  await gitlabService.updateFile({
    filePath: policy.gitlabFilePath,
    branch: branchName,
    content: markdown,
    commitMessage: commitMessage ?? `chore: autosave ${policy.title}`,
    lastCommitId: existing.lastCommitId,  // Required by GitLab to detect conflicts
  })
} else {
  // First save — create the file
  await gitlabService.createFile({ ... })
}
```

The `lastCommitId` must be passed on update — GitLab uses it to detect
concurrent edits and return a 400 if the file has changed since the client
last loaded it.

### Submit for review — open a MR

Called by `POST /api/v1/policies/:id/workflow/submit`.

```typescript
const mr = await gitlabService.createMergeRequest({
  sourceBranch: workflow.gitlabBranchName,
  targetBranch: 'main',
  title: `Review: ${policy.title}`,
  description: changeJustification ?? '',
  draft: false,
  assigneeIds: reviewerGitlabIds,
  labels: ['policy-review'],
})

// Store the MR IID (GitLab's per-project MR number) — this is the join key
await workflow.merge({ gitlabMrIid: mr.iid })
await workflow.save()
```

The `mr.iid` is the MR number within the project (e.g. `42`). This is
`workflow_instances.gitlab_mr_iid`. Do not store `mr.id` (global GitLab ID) —
the IID is the stable per-project reference.

### Fetch diff for review screen

Called by `GET /api/v1/policies/:id/workflow/diff`. Cached for 30 seconds,
invalidated by new commit to the draft branch.

```typescript
// Raw unified diff — passed to Monaco Editor
const diff = await gitlabService.getMrDiff({
  mrIid: workflow.gitlabMrIid,
})

// Branch content for rendered side-by-side view
const [draftContent, mainContent] = await Promise.all([
  gitlabService.getFileContent({
    filePath: policy.gitlabFilePath,
    ref: workflow.gitlabBranchName,
  }),
  gitlabService.getFileContent({
    filePath: policy.gitlabFilePath,
    ref: 'main',
  }).catch(() => ''),  // New policy — main branch has no file yet
])
```

### Post a comment to MR

Called by `POST /api/v1/policies/:id/comments`. Saves to local DB first,
then syncs to GitLab asynchronously (via job) to keep the request fast.

```typescript
// Save to local DB immediately (for instant UI update)
const comment = await Comment.create({
  workflowInstanceId: workflow.id,
  authorId: user.id,
  body: data.body,
})

// Sync to GitLab MR asynchronously
await SendCommentToGitlabJob.dispatch({
  mrIid: workflow.gitlabMrIid,
  body: data.body,
  commentId: comment.id,
})
```

### Add approval — L1

Called by `POST /api/v1/policies/:id/workflow/approve-l1`.

```typescript
// Record approval in GitLab
await gitlabService.approveMergeRequest({
  mrIid: workflow.gitlabMrIid,
})

// Record in local DB (immutable append-only)
await WorkflowApproval.create({
  workflowInstanceId: workflow.id,
  approverId: user.id,
  approvalLevel: 'l1',
  action: 'approved',
  comment: data.comment,
})

await workflow.merge({ status: 'approved_l1' }).save()
```

### Merge MR — final approval triggers publish

Called by `POST /api/v1/policies/:id/workflow/approve-final`.

```typescript
// Merge the MR in GitLab
const mergeResult = await gitlabService.mergeMergeRequest({
  mrIid: workflow.gitlabMrIid,
  mergeCommitMessage: `policy: publish ${policy.title} v${nextVersion}`,
  shouldRemoveSourceBranch: false,  // Keep branch for audit trail
})

// Trigger publishing pipeline (async — webhook is the safety net)
await PublishingJob.dispatch({
  policyId: policy.id,
  workflowInstanceId: workflow.id,
  commitSha: mergeResult.mergeCommitSha,
})
```

### Withdraw — close MR

Called by `POST /api/v1/policies/:id/workflow/withdraw`.

```typescript
await gitlabService.closeMergeRequest({
  mrIid: workflow.gitlabMrIid,
})

await workflow.merge({ status: 'draft' }).save()
```

### Fetch published content — for publishing pipeline

The publishing pipeline fetches the merged markdown from `main` after the MR
is merged.

```typescript
const markdown = await gitlabService.getFileContent({
  filePath: policy.gitlabFilePath,
  ref: 'main',    // Always read from main — never from the draft branch
})

const commitSha = await gitlabService.getFileLastCommitSha({
  filePath: policy.gitlabFilePath,
  ref: 'main',
})
// Stored in policy_versions.git_commit_sha
```

---

## Webhook Handling

GitLab fires webhooks on MR events. The application receives them at
`POST /webhooks/gitlab`, verified by the `X-Gitlab-Token` header.

Webhooks are the **safety net** — they reconcile GitLab state with the
application's database. The application also performs direct API calls on
workflow transitions, so webhooks handle edge cases (e.g., an admin merges
directly in GitLab without going through the application UI).

### Verification middleware

```typescript
// app/middleware/webhook_secret_middleware.ts
export default class WebhookSecretMiddleware {
  async handle({ request, response }: HttpContext, next: NextFn) {
    const token = request.header('X-Gitlab-Token')
    if (token !== env.get('GITLAB_WEBHOOK_SECRET')) {
      return response.unauthorized('Invalid webhook token')
    }
    await next()
  }
}
```

### Handled event types

```typescript
// app/controllers/webhooks/gitlab_controller.ts
export default class GitlabController {
  async handle({ request, response }: HttpContext) {
    const event = request.header('X-Gitlab-Event')
    const payload = request.body()

    switch (event) {
      case 'Merge Request Hook':
        await this.handleMergeRequestEvent(payload)
        break
      case 'Note Hook':
        await this.handleNoteEvent(payload)
        break
    }

    return response.noContent()  // Always 204 — never let GitLab retry
  }

  private async handleMergeRequestEvent(payload: GitlabMrPayload) {
    const { object_attributes: mr } = payload

    const workflow = await WorkflowInstance.findByOrFail('gitlab_mr_iid', mr.iid)

    switch (mr.action) {
      case 'open':
        // MR opened — update iid if not already set (e.g. if webhook beat the API response)
        await workflow.merge({ gitlabMrIid: mr.iid, status: 'under_review' }).save()
        break

      case 'approved':
        // Approval recorded in GitLab — sync to workflow_approvals if not already there
        await this.syncApproval(workflow, payload)
        break

      case 'merge':
        // MR merged — trigger publishing if not already triggered
        if (workflow.status !== 'published') {
          await PublishingJob.dispatch({ policyId: workflow.policyId, workflowInstanceId: workflow.id })
        }
        break

      case 'close':
        await workflow.merge({ status: 'closed' }).save()
        break
    }
  }

  private async handleNoteEvent(payload: GitlabNotePayload) {
    const { object_attributes: note, merge_request: mr } = payload
    if (!mr) return  // Only handle MR notes, not commit/issue notes

    const workflow = await WorkflowInstance.findBy('gitlab_mr_iid', mr.iid)
    if (!workflow) return

    // Upsert comment — may already exist if created via application UI
    await Comment.updateOrCreate(
      { gitlabNoteId: note.id },
      {
        workflowInstanceId: workflow.id,
        body: note.note,
        gitlabCreatedAt: DateTime.fromISO(note.created_at),
        gitlabNoteId: note.id,
      }
    )
  }
}
```

### Always return 204

The webhook handler must always return a 2xx response promptly. If GitLab
receives a non-2xx or times out, it will retry — potentially processing the
same event multiple times. Make all event handling idempotent (upsert, not
insert) and return `204 No Content` even when the event is ignored.

---

## Rate Limiting

The GitLab API has rate limits (default: 300 requests/minute per user/token).
The service account token is shared across all requests.

Design patterns to stay within limits:
- **Cache branch content and diffs** — cache for 30 seconds, invalidated by new commits
- **Async webhook sync** — don't call GitLab API on every comment save; queue it
- **Avoid polling** — use webhooks for state changes, not repeated API calls
- **Batch where possible** — if loading MR details for a list, batch not per-item

```typescript
// In gitlab_service.ts — cache expensive reads
async getMrDiff(mrIid: number): Promise<GitlabDiff> {
  const cacheKey = `gitlab:mr:${mrIid}:diff`
  const cached = await redis.get(cacheKey)
  if (cached) return JSON.parse(cached)

  const diff = await this.api.get(`/merge_requests/${mrIid}/diffs`)
  await redis.setex(cacheKey, 30, JSON.stringify(diff))
  return diff
}

// Invalidate on new commit
async updateFile(params: UpdateFileParams): Promise<void> {
  await this.api.put(`/repository/files/${encodeURIComponent(params.filePath)}`, params)
  // Invalidate any cached diff for the active MR.
  // Avoid redis.del with a wildcard — it blocks the server while scanning.
  // Use SCAN + DEL instead so invalidation is non-blocking.
  if (params.mrIid) {
    await redis.del(`gitlab:mr:${params.mrIid}:diff`)
  } else {
    // mrIid not available: scan and delete in batches without blocking
    let cursor = '0'
    do {
      const [nextCursor, keys] = await redis.scan(cursor, 'MATCH', 'gitlab:mr:*:diff', 'COUNT', 100)
      if (keys.length) await redis.del(...keys)
      cursor = nextCursor
    } while (cursor !== '0')
  }
}
```

---

## Error Handling

GitLab API errors should be caught in the service layer and translated to
domain errors — controllers should not handle raw GitLab HTTP errors.

```typescript
// In gitlab_service.ts
async createBranch(params: CreateBranchParams): Promise<void> {
  try {
    await this.api.post('/repository/branches', params)
  } catch (err) {
    if (err.response?.status === 400 && err.response?.data?.message?.includes('Branch already exists')) {
      // Idempotent — branch already exists, that's fine
      return
    }
    throw new GitlabServiceException(`Failed to create branch: ${err.message}`, { cause: err })
  }
}
```

Common GitLab error scenarios to handle:
- `400 Branch already exists` — treat as success (idempotent)
- `404 File not found` — new policy, no file yet on branch (expected)
- `409 Conflict` — concurrent edit detected (surface to user as "someone else saved first")
- `429 Too Many Requests` — rate limited (queue the retry, don't fail the user request)

---

## File Path Conventions

```typescript
// Policy file path: category-slug/policy-slug.md
// Matches GitLab folder structure exactly
const filePath = `${category.gitlabPath}/${policy.slug}.md`
// e.g. 'hr/expense-policy.md'
//      'it/security/acceptable-use-policy.md'

// Stored in policies.gitlab_file_path
// Used in all GitLab file API calls
```

The file path is the stable identifier linking PostgreSQL to GitLab content.
It never changes after creation (renaming a policy does not rename the file —
that would break history). The `title` in PostgreSQL can change freely.

---

## Graceful Degradation

GitLab may be unreachable (maintenance, network issues, rate limits). The
application must degrade gracefully:

- **Read portal** always works — rendered HTML is cached in `policy_versions.rendered_html`,
  independent of GitLab availability
- **Editor saves** queue locally and sync when GitLab recovers (display "Saving…" state)
- **Workflow transitions** that require a GitLab API call should fail clearly with a
  user-facing message, not a 500 — the user can retry
- **Webhooks** are the reconciliation mechanism — any state that GitLab changes
  directly will be synced once webhooks resume
