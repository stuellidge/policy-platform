# AdonisJS v7 Controllers

## Critical v7 API Changes from v6

```typescript
// ❌ v6 — removed in v7
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

---

## Controller Structure

Always generate with `node ace make:controller <name>`. Never hand-write.

```typescript
// app/controllers/authoring/policies_controller.ts
import type { HttpContext } from '@adonisjs/core/http'

export default class PoliciesController {
  async index({ auth, inertia }: HttpContext) {
    const user = auth.getUserOrFail()
    const policies = await Policy.query()
      .where('owner_id', user.id)
      .orderBy('updated_at', 'desc')

    return inertia.render('authoring/policies/index', { policies })
  }

  async store({ request, response, auth, session }: HttpContext) {
    const data = await request.validateUsing(createPolicyValidator)
    const user = auth.getUserOrFail()

    const policy = await Policy.create({ ...data, ownerId: user.id })

    session.flash('success', 'Policy draft created.')
    return response.redirect().toRoute('policies.edit', { id: policy.id })
  }

  async show({ params, inertia, bouncer }: HttpContext) {
    const policy = await Policy.findOrFail(params.id)
    await bouncer.with('PolicyPolicy').authorize('view', policy)

    return inertia.render('authoring/policies/edit', { policy })
  }

  async update({ params, request, response, bouncer, session }: HttpContext) {
    const policy = await Policy.findOrFail(params.id)
    await bouncer.with('PolicyPolicy').authorize('update', policy)

    const data = await request.validateUsing(updatePolicyValidator)
    policy.merge(data)
    await policy.save()

    session.flash('success', 'Policy updated.')
    return response.redirect().back()
  }

  async destroy({ params, response, bouncer, session }: HttpContext) {
    const policy = await Policy.findOrFail(params.id)
    await bouncer.with('PolicyPolicy').authorize('delete', policy)

    await policy.delete()

    session.flash('success', 'Policy deleted.')
    return response.redirect().toRoute('policies.index')
  }
}
```

---

## Route Registration

```typescript
// start/routes.ts
import router from '@adonisjs/core/services/router'
import { middleware } from '#start/kernel'

// Explicit lazy import pattern — used throughout this project
const PoliciesController = () => import('#controllers/authoring/policies_controller')
const WorkflowController = () => import('#controllers/authoring/workflow_controller')

// All routes get an .as() name — required for type-safe urlFor()
router.group(() => {
  router.resource('policies', PoliciesController).except(['show'])
    // generates: policies.index, policies.create, policies.store,
    //            policies.edit, policies.update, policies.destroy

  router.post('policies/:id/workflow/submit', [WorkflowController, 'submit'])
    .as('policies.workflow.submit')

  router.post('policies/:id/workflow/withdraw', [WorkflowController, 'withdraw'])
    .as('policies.workflow.withdraw')

}).prefix('/api/v1').middleware([middleware.auth()])
```

### Route naming conventions

Every route must have an `.as()` name so `urlFor()` can be used on server and client:

```typescript
// Server-side URL generation
import { urlFor } from '@adonisjs/core/services/url_builder'
const url = urlFor('policies.workflow.submit', { id: policyId })

// ❌ Removed in v7
router.makeUrl('policies.workflow.submit', { id: policyId })
```

---

## Middleware

### Named middleware definition (start/kernel.ts)

```typescript
// start/kernel.ts
import router from '@adonisjs/core/services/router'
import server from '@adonisjs/core/services/server'

server.use([
  () => import('@adonisjs/core/bodyparser_middleware'),
  () => import('@adonisjs/session/session_middleware'),
  () => import('@adonisjs/shield/shield_middleware'),
  () => import('#middleware/inertia_middleware'),   // runs on every request
])

export const middleware = router.named({
  auth: () => import('#middleware/auth_middleware'),
  requireRole: () => import('#middleware/require_role_middleware'),
  portalAccess: () => import('#middleware/portal_access_middleware'),
})
```

### Custom middleware

```typescript
// app/middleware/require_role_middleware.ts — node ace make:middleware require_role
import type { HttpContext } from '@adonisjs/core/http'
import type { NextFn } from '@adonisjs/core/types/http'

export default class RequireRoleMiddleware {
  async handle(
    { auth, response }: HttpContext,
    next: NextFn,
    options: { roles: string[] }
  ) {
    const user = auth.getUserOrFail()
    await user.load('roles')

    const userRoles = user.roles.map((r) => r.name)
    const hasRole = options.roles.some((r) => userRoles.includes(r))

    if (!hasRole) {
      return response.forbidden('Insufficient role.')
    }

    await next()
  }
}
```

### Applying middleware

```typescript
// Applying named middleware with options
router.get('/admin/users', [UsersController, 'index'])
  .as('admin.users.index')
  .use(middleware.requireRole({ roles: ['policy:admin'] }))

// Applying to a group
router.group(() => {
  // all admin routes
}).prefix('/admin').use(middleware.auth()).use(middleware.requireRole({ roles: ['policy:admin'] }))
```

---

## Inertia Responses

This project uses React + Inertia instead of Edge.js templates.

```typescript
// Render an Inertia page — TypeScript will validate the props against
// the page component's Props type (from .adonisjs/server/pages.d.ts)
return inertia.render('authoring/policies/index', {
  policies: await PolicyTransformer.collection(policies),
})

// The page name maps to inertia/pages/authoring/policies/index.tsx
```

### Redirects

```typescript
// Named route redirect (type-safe)
return response.redirect().toRoute('policies.index')

// Redirect back to previous page
return response.redirect().back()

// With status code
return response.redirect(301).toRoute('policies.index')
```

---

## Error Handling

```typescript
// findOrFail automatically returns 404 — prefer over manual not-found checks
const policy = await Policy.findOrFail(params.id)

// Structured logging — object FIRST, message string SECOND (Pino convention)
const logger = ctx.logger
logger.error({ err, policyId: params.id }, 'Failed to update policy')

// Custom exception for domain errors
import WorkflowException from '#exceptions/workflow_exception'
throw new WorkflowException('Cannot submit a policy that is already under review.')
```

---

## VineJS Validation in Controllers

```typescript
import { createPolicyValidator, updatePolicyValidator } from '#validators/policy'

// Throws 422 automatically on failure — no try/catch needed
const data = await request.validateUsing(createPolicyValidator)

// With metadata (e.g. for uniqueness exclusion on update)
const data = await request.validateUsing(updatePolicyValidator, {
  meta: { policyId: params.id },
})
```

---

## Flash Messages

Flash messages persist across one redirect. Reading them in an Inertia page
is handled via shared data in `InertiaMiddleware`.

```typescript
// Writing flash messages (server)
session.flash('success', 'Policy submitted for review.')
session.flash('error', 'Workflow transition is not permitted.')

// Reading validation errors (v7 key — NOT 'errors.email')
const emailError = flashMessages.get('inputErrorsBag.email')
// ❌ flashMessages.get('errors.email')  — removed in v7
```

---

## Bouncer Authorization

```typescript
// Single resource check — throws 403 on denial
await bouncer.with('PolicyPolicy').authorize('update', policy)

// Checking without throwing (for conditional UI)
const canEdit = await bouncer.with('PolicyPolicy').allows('update', policy)
const cannotEdit = await bouncer.with('PolicyPolicy').denies('update', policy)
```

---

## API JSON Controllers

For API endpoints that return JSON (not Inertia pages):

```typescript
async show({ params, response }: HttpContext) {
  const policy = await Policy.findOrFail(params.id)

  // Use transformer for typed, consistent serialization
  return response.ok(await PolicyTransformer.transform(policy))
}

async store({ request, response }: HttpContext) {
  const data = await request.validateUsing(createPolicyValidator)
  const policy = await Policy.create(data)

  return response.created(await PolicyTransformer.transform(policy))
}
```
