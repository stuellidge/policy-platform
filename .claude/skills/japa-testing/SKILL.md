# Japa Testing (AdonisJS v7)

## Critical Rules

- **No nested test groups** — Japa does not support nesting `test.group()` inside another group
- **Never use `--grep`** — it does not work; use `--groups` and `--tests` flags instead
- **Glob syntax changed in v7** — use `{ts,js}` not `(.ts|.js)` in `adonisrc.ts` file patterns
- **Flash message key changed in v7** — `inputErrorsBag.email` not `errors.email`
- **Always use `loginAs()`** — never mock auth middleware or call live IdPs
- **Two suites** — `unit` (no HTTP, prefer no DB) and `functional` (HTTP + DB, no live IdP or GitLab)

---

## v7 Glob Syntax (adonisrc.ts)

```typescript
// ✅ v7 — Node.js built-in glob syntax
suites: [
  {
    name: 'unit',
    files: ['tests/unit/**/*.spec.{ts,js}'],
  },
  {
    name: 'functional',
    files: ['tests/functional/**/*.spec.{ts,js}'],
  },
]

// ❌ v6 — fails in v7
files: ['tests/unit/**/*.spec(.ts|.js)']
```

---

## Bootstrap Setup (tests/bootstrap.ts)

```typescript
import { assert } from '@japa/assert'
import { apiClient } from '@japa/api-client'
import { pluginAdonisJS } from '@japa/plugin-adonisjs'
import testUtils from '@adonisjs/core/services/test_utils'
import app from '@adonisjs/core/services/app'

export const plugins = [
  assert(),
  apiClient(),
  pluginAdonisJS(app),
]

export const runnerHooks = {
  setup: [() => testUtils.db().migrate()],
  teardown: [],
}
```

---

## Test Structure

```typescript
// node ace make:test policies/create --suite=functional
import { test } from '@japa/runner'
import testUtils from '@adonisjs/core/services/test_utils'
import { UserFactory } from '#database/factories/user_factory'
import { PolicyFactory } from '#database/factories/policy_factory'

test.group('Policies — create', (group) => {
  // Wrap each test in a transaction — rolled back automatically
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('author can create a draft policy', async ({ client, assert }) => {
    const author = await UserFactory
      .with('roles', 1, (r) => r.merge({ name: 'policy:author' }))
      .create()

    const response = await client
      .post('/api/v1/policies')
      .loginAs(author)
      .json({ title: 'Expense Policy', categoryId: null })

    response.assertStatus(201)
    response.assertBodyContains({ title: 'Expense Policy', status: 'DRAFT' })
  })

  test('unauthenticated request is rejected', async ({ client }) => {
    const response = await client
      .post('/api/v1/policies')
      .json({ title: 'Test' })

    response.assertStatus(401)
  })

  test('reviewer cannot create a policy', async ({ client }) => {
    const reviewer = await UserFactory
      .with('roles', 1, (r) => r.merge({ name: 'policy:reviewer' }))
      .create()

    const response = await client
      .post('/api/v1/policies')
      .loginAs(reviewer)
      .json({ title: 'Expense Policy' })

    response.assertStatus(403)
  })
})
```

---

## Authentication in Tests

**Always use `loginAs()`** — it sets up the session without touching any IdP.

```typescript
// Session-based auth
const user = await UserFactory.create()
await client.get('/authoring/dashboard').loginAs(user)

// With roles (factory approach)
const admin = await UserFactory
  .with('roles', 1, (r) => r.merge({ name: 'policy:admin' }))
  .create()

// Unauthenticated — just don't call loginAs()
await client.get('/authoring/dashboard')  // will redirect or 401
```

---

## HTTP Testing

```typescript
// GET
const response = await client.get('/api/v1/policies')

// POST with JSON body
const response = await client
  .post('/api/v1/policies')
  .loginAs(user)
  .json({ title: 'New Policy', categoryId: 'uuid-here' })

// PUT / PATCH
const response = await client
  .put(`/api/v1/policies/${policy.id}`)
  .loginAs(author)
  .json({ title: 'Updated Title' })

// DELETE
const response = await client
  .delete(`/api/v1/policies/${policy.id}`)
  .loginAs(admin)

// With query params
const response = await client
  .get('/api/v1/portal/policies')
  .loginAs(user)
  .qs({ status: 'PUBLISHED', page: 1 })
```

---

## Assertions

```typescript
// Status codes
response.assertStatus(200)
response.assertStatus(201)
response.assertStatus(401)
response.assertStatus(403)
response.assertStatus(404)
response.assertStatus(422)  // VineJS validation failure

// Body assertions
response.assertBodyContains({ title: 'Expense Policy' })
response.assertBody({ id: policy.id, title: 'Expense Policy', status: 'DRAFT' })

// JSON field exists
response.assertBodyContains({ data: [] })

// Redirect
response.assertRedirectsTo('/authoring/dashboard')

// Headers
response.assertHeader('content-type', /json/)

// Japa assert (Chai-compatible)
assert.equal(response.body().status, 'DRAFT')
assert.isTrue(response.body().isPublished)
assert.deepEqual(response.body().roles, ['policy:author'])
assert.isNull(response.body().deletedAt)
```

---

## Validation Error Testing (v7 flash key)

When a form submission fails VineJS validation, the error key in flash messages
changed in v7:

```typescript
// v7: validation errors are at 'inputErrorsBag.fieldName'
response.assertFlashMessage('inputErrorsBag.title', 'The title field is required.')

// ❌ v6 key — removed in v7
response.assertFlashMessage('errors.title', ...)
```

For API routes returning 422 JSON:

```typescript
response.assertStatus(422)
response.assertBodyContains({
  errors: [{ field: 'title', message: 'The title field is required.' }],
})
```

---

## Unit Tests

Unit tests target services and validators without HTTP or database.

```typescript
// node ace make:test services/workflow_service --suite=unit
import { test } from '@japa/runner'
import WorkflowService from '#services/workflow/workflow_service'

test.group('WorkflowService — state transitions', () => {
  test('DRAFT can transition to SUBMITTED', ({ assert }) => {
    const service = new WorkflowService()
    assert.isTrue(service.canTransition('DRAFT', 'SUBMITTED'))
  })

  test('PUBLISHED cannot transition to SUBMITTED', ({ assert }) => {
    const service = new WorkflowService()
    assert.isFalse(service.canTransition('PUBLISHED', 'SUBMITTED'))
  })
})
```

---

## Lifecycle Hooks

```typescript
test.group('My group', (group) => {
  // Runs once before all tests in the group
  group.setup(async () => {
    await seedRoles()
  })

  // Runs once after all tests
  group.teardown(async () => {
    // cleanup
  })

  // Runs before EACH test
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  // Runs after EACH test
  group.each.teardown(async () => {
    // per-test cleanup
  })
})
```

---

## Datasets

```typescript
test('validates status transitions')
  .with([
    { from: 'DRAFT', to: 'SUBMITTED', allowed: true },
    { from: 'DRAFT', to: 'PUBLISHED', allowed: false },
    { from: 'SUBMITTED', to: 'UNDER_REVIEW', allowed: true },
    { from: 'PUBLISHED', to: 'DRAFT', allowed: false },
  ])
  .run(async ({ assert }, { from, to, allowed }) => {
    const service = new WorkflowService()
    assert.equal(service.canTransition(from, to), allowed)
  })
```

---

## Running Tests

```bash
# All tests
node ace test

# Single suite
node ace test --suite=unit
node ace test --suite=functional

# Specific file
node ace test --files=tests/functional/policies/workflow.spec.ts

# Specific group (use --groups not --grep)
node ace test --groups='Policies — workflow'

# Specific test name (use --tests not --grep)
node ace test --tests='author can submit a policy for review'

# With coverage
node ace test --coverage
```

---

## Factory Pattern

Factories define how to create model instances for tests. Always generate them:

```bash
node ace make:factory user --model=user
node ace make:factory policy --model=policy
```

```typescript
// database/factories/user_factory.ts
import factory from '@adonisjs/lucid/factories'
import User from '#models/user'

export const UserFactory = factory
  .define(User, ({ faker }) => ({
    email: faker.internet.email(),
    displayName: faker.person.fullName(),
    idpSubject: faker.string.uuid(),
    idpProvider: 'entra',
    isActive: true,
  }))
  .relation('roles', () => RoleFactory)
  .build()
```

```typescript
// Usage in tests
const user = await UserFactory.create()

// With traits
const author = await UserFactory
  .with('roles', 1, (r) => r.merge({ name: 'policy:author' }))
  .create()

// Create many
const policies = await PolicyFactory.createMany(5)

// Make (in-memory only, not saved)
const user = await UserFactory.make()
```

---

## Environment

`.env.test` (or `.env` when `NODE_ENV=test`) must have:

```bash
SESSION_DRIVER=memory    # required for loginAs() to work in tests
DB_DATABASE=policyhub_test
```

---

## Portal Access / RBAC Testing

```typescript
test.group('Portal — audience filtering', (group) => {
  group.each.setup(() => testUtils.db().withGlobalTransaction())

  test('user only sees policies for their audience groups', async ({ client, assert }) => {
    const financeGroup = await AudienceGroup.findByOrFail('slug', 'finance-team')
    const allStaffGroup = await AudienceGroup.findByOrFail('slug', 'all-staff')

    const financeUser = await UserFactory.create()
    await financeUser.related('audienceGroups').attach([financeGroup.id])

    const financePolicy = await PolicyFactory.merge({ status: 'PUBLISHED' })
      .with('audienceGroups', 1, (g) => g.merge({ id: financeGroup.id }))
      .create()

    const hrPolicy = await PolicyFactory.merge({ status: 'PUBLISHED' })
      .with('audienceGroups', 1, (g) => g.merge({ id: allStaffGroup.id }))
      .create()

    const response = await client
      .get('/api/v1/portal/policies')
      .loginAs(financeUser)

    response.assertStatus(200)
    const ids = response.body().data.map((p: any) => p.id)
    assert.notInclude(ids, hrPolicy.id)
    // financePolicy should be visible because the user is in the correct audience group, but hrPolicy should not.
  })
})
```
