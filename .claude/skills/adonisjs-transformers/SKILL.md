# AdonisJS v7 Transformers

Transformers are a **first-class v7 feature** — there is no v6 equivalent.
They are the canonical way to serialise Lucid models to JSON for API responses
and Inertia page props.

**Why transformers instead of model serialization:**
- Output types flow automatically to `.adonisjs/client/data.d.ts` for the frontend
- TypeScript catches prop mismatches in `inertia.render()` at compile time
- Explicit control over what fields are exposed — no accidental data leaks
- Consistent serialization regardless of where a model is used

---

## Generation

Always use the generator:

```bash
node ace make:transformer user
node ace make:transformer policy
node ace make:transformer policy_version
node ace make:transformer workflow_instance
node ace make:transformer bot_interaction
```

---

## Transformer Structure

```typescript
// app/transformers/policy_transformer.ts
import { BaseTransformer } from '@adonisjs/lucid/transformers'
import Policy from '#models/policy'

export default class PolicyTransformer extends BaseTransformer<Policy> {
  transform(policy: Policy) {
    return {
      id: policy.id,
      title: policy.title,
      slug: policy.slug,
      status: policy.status,
      purpose: policy.purpose,
      effectiveDate: policy.effectiveDate?.toISODate() ?? null,
      reviewDate: policy.reviewDate?.toISODate() ?? null,
      createdAt: policy.createdAt.toISO(),
      updatedAt: policy.updatedAt.toISO(),
    }
  }
}
```

---

## Using Transformers in Controllers

```typescript
import PolicyTransformer from '#transformers/policy_transformer'

// Single record
async show({ params, inertia }: HttpContext) {
  const policy = await Policy.findOrFail(params.id)

  return inertia.render('authoring/policies/edit', {
    policy: await PolicyTransformer.transform(policy),
  })
}

// Collection
async index({ inertia }: HttpContext) {
  const policies = await Policy.query().orderBy('updated_at', 'desc')

  return inertia.render('authoring/policies/index', {
    policies: await PolicyTransformer.collection(policies),
  })
}

// In a JSON API response
async show({ params, response }: HttpContext) {
  const policy = await Policy.findOrFail(params.id)
  return response.ok(await PolicyTransformer.transform(policy))
}
```

---

## Transformers with Relationships

Preload relationships before transforming, then nest transformers:

```typescript
// app/transformers/workflow_instance_transformer.ts
import { BaseTransformer } from '@adonisjs/lucid/transformers'
import WorkflowInstance from '#models/workflow_instance'
import UserTransformer from '#transformers/user_transformer'

export default class WorkflowInstanceTransformer extends BaseTransformer<WorkflowInstance> {
  async transform(instance: WorkflowInstance) {
    return {
      id: instance.id,
      status: instance.status,
      gitlabMrIid: instance.gitlabMrIid,
      gitlabMrUrl: instance.gitlabMrUrl,
      changeSummary: instance.changeSummary,
      createdAt: instance.createdAt.toISO(),

      // Nested transformer — relationship must be preloaded before calling
      reviewers: instance.reviewers
        ? await UserTransformer.collection(instance.reviewers)
        : [],
    }
  }
}
```

```typescript
// In the controller — always preload what the transformer needs
const instance = await WorkflowInstance.query()
  .where('id', params.id)
  .preload('reviewers')
  .firstOrFail()

return inertia.render('authoring/policies/review', {
  workflow: await WorkflowInstanceTransformer.transform(instance),
})
```

---

## Type Flow to Frontend

After `node ace build` (or `node ace serve --hmr` in development), the
framework writes transformer output types to `.adonisjs/client/data.d.ts`.

This means React components get full type safety on transformer output:

```typescript
// inertia/pages/authoring/policies/edit.tsx
import type { InferPageProps } from '@adonisjs/inertia/types'
import type PoliciesController from '#controllers/authoring/policies_controller'

// Props type is inferred from what the controller passes to inertia.render()
type Props = InferPageProps<typeof PoliciesController, 'show'>

export default function EditPolicy({ policy }: Props) {
  // policy.title, policy.status, policy.effectiveDate are all typed
  return <h1>{policy.title}</h1>
}
```

TypeScript will error at build time if the controller passes a prop the page
component doesn't declare, or if the transformer output changes shape.

---

## Transformer for Paginated Results

```typescript
async index({ request, inertia }: HttpContext) {
  const page = await Policy.query()
    .apply((s) => s.published())
    .paginate(request.input('page', 1), 20)

  return inertia.render('portal/index', {
    // Paginator wraps results — transform the data array
    policies: {
      data: await PolicyTransformer.collection(page.all()),
      meta: page.getMeta(),
    },
  })
}
```

---

## Shared Transformer Patterns for PolicyHub

### UserTransformer — never expose password or idpSubject

```typescript
export default class UserTransformer extends BaseTransformer<User> {
  transform(user: User) {
    return {
      id: user.id,
      email: user.email,
      displayName: user.displayName,
      avatarUrl: user.avatarUrl,
      // ✅ password and idpSubject are deliberately excluded
    }
  }
}
```

### PolicyTransformer with audience groups

```typescript
export default class PolicyTransformer extends BaseTransformer<Policy> {
  async transform(policy: Policy) {
    return {
      id: policy.id,
      title: policy.title,
      status: policy.status,
      // Only include audienceGroups if preloaded
      audienceGroups: policy.$preloaded.audienceGroups
        ? await AudienceGroupTransformer.collection(policy.audienceGroups)
        : undefined,
    }
  }
}
```

---

## Never Use These Serialisation Patterns

```typescript
// ❌ Ad-hoc object mapping in controllers — use a transformer
return response.ok({
  id: policy.id,
  title: policy.title,
  status: policy.status,
})

// ❌ model.toJSON() — bypasses transformer type guarantees
return response.ok(policy.toJSON())

// ❌ model.$hidden — v6 pattern, no longer the right tool in v7
Policy.$hidden = ['password']
```
