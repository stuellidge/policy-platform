# VineJS Validation (AdonisJS v7)

VineJS is a standalone package — its API is unchanged between AdonisJS v6 and v7.
The v7 difference is in file organisation: use `node ace make:validator <name>` to
generate into `app/validators/`. Never hand-write validator files.

---

## Generation

```bash
node ace make:validator policy
node ace make:validator workflow
node ace make:validator comment
node ace make:validator admin
```

---

## Basic Validator Structure

```typescript
// app/validators/policy_validator.ts
import vine from '@vinejs/vine'

// CREATE validator — use vine.compile() for validators without metadata
export const createPolicyValidator = vine.compile(
  vine.object({
    title: vine.string().trim().minLength(3).maxLength(500),
    purpose: vine.string().trim().optional(),
    categoryId: vine.string().uuid().optional().nullable(),
  })
)

// UPDATE validator — use vine.withMetaData<T>() when you need metadata
// (e.g. to exclude the current record from a uniqueness check)
export const updatePolicyValidator = vine.withMetaData<{ policyId: string }>().compile(
  vine.object({
    title: vine.string().trim().minLength(3).maxLength(500),
    purpose: vine.string().trim().optional(),
    categoryId: vine.string().uuid().optional().nullable(),
  })
)
```

---

## Controller Usage

```typescript
import {
  createPolicyValidator,
  updatePolicyValidator,
} from '#validators/policy'

// Throws 422 automatically on failure — no try/catch needed
const data = await request.validateUsing(createPolicyValidator)

// With metadata
const data = await request.validateUsing(updatePolicyValidator, {
  meta: { policyId: params.id },
})

// data is fully typed from the schema
await Policy.create(data)
```

---

## Schema Types

### String

```typescript
vine.string()
vine.string().trim()
vine.string().trim().minLength(3)
vine.string().trim().maxLength(500)
vine.string().email()
vine.string().url()
vine.string().uuid()
vine.string().regex(/^draft\/[a-z0-9-]+$/)
vine.string().optional()           // undefined allowed (field can be absent)
vine.string().nullable()           // null allowed
vine.string().optional().nullable() // both
```

### Number

```typescript
vine.number()
vine.number().positive()
vine.number().min(1).max(100)
vine.number().withoutDecimals()
vine.number().decimal(0, 2)   // 0–2 decimal places
```

### Boolean

```typescript
vine.boolean()
vine.boolean().accepted()    // for checkboxes — accepts truthy values
```

### Date

```typescript
vine.date()
vine.date({ formats: ['YYYY-MM-DD'] })
vine.date().after('today')
vine.date().before(vine.refs.date(cutoff))
```

### Enum

```typescript
// From literal array
vine.enum(['DRAFT', 'SUBMITTED', 'UNDER_REVIEW'] as const)

// From TypeScript enum
enum WorkflowStatus {
  DRAFT = 'DRAFT',
  SUBMITTED = 'SUBMITTED',
}
vine.enum(WorkflowStatus)
```

### Array

```typescript
vine.array(vine.string().uuid())            // array of UUIDs
vine.array(vine.string()).minLength(1)      // at least one item
vine.array(vine.string()).distinct()        // no duplicates
vine.array(vine.string()).compact()         // removes empty/null items

// Array of objects
vine.array(
  vine.object({
    id: vine.string().uuid(),
    role: vine.string(),
  })
)
```

### Object

```typescript
vine.object({
  title: vine.string().trim(),
  metadata: vine.object({
    owner: vine.string().email(),
    reviewDate: vine.date({ formats: ['YYYY-MM-DD'] }),
  }).optional(),
})
```

---

## Database Uniqueness

```typescript
import db from '@adonisjs/lucid/services/db'

// CREATE — check slug is unique across all rows
export const createPolicyValidator = vine.compile(
  vine.object({
    slug: vine.string().trim()
      .unique(async (db, value) => {
        const exists = await db.from('policies').where('slug', value).first()
        return !exists
      }),
  })
)

// UPDATE — exclude the current record from the uniqueness check
// Uses metadata to pass the current record's ID
export const updatePolicyValidator = vine.withMetaData<{ policyId: string }>().compile(
  vine.object({
    slug: vine.string().trim()
      .unique(async (db, value, field) => {
        const exists = await db
          .from('policies')
          .where('slug', value)
          .whereNot('id', field.meta.policyId)  // exclude current record
          .first()
        return !exists
      }),
  })
)
```

---

## Custom Rules

```typescript
import vine, { VineString } from '@vinejs/vine'

// Define a reusable rule
const isGitBranchName = vine.createRule(async (value, _options, field) => {
  if (typeof value !== 'string') return

  const valid = /^[a-z0-9][a-z0-9\-\/]*$/.test(value)
  if (!valid) {
    field.report(
      'The {{ field }} field must be a valid git branch name.',
      'gitBranchName',
      field
    )
  }
})

// Extend VineString
VineString.macro('gitBranchName', function (this: VineString) {
  return this.use(isGitBranchName())
})

// Usage
vine.string().gitBranchName()
```

---

## Password Confirmation

```typescript
vine.object({
  password: vine.string().minLength(12),
  // .confirmed() automatically validates that password_confirmation matches
  password_confirmation: vine.string().confirmed({ confirmationField: 'password' }),
})
```

---

## Custom Error Messages

```typescript
import vine, { SimpleMessagesProvider } from '@vinejs/vine'

vine.messagesProvider = new SimpleMessagesProvider({
  'required': 'The {{ field }} field is required.',
  'string': 'The {{ field }} field must be a string.',
  'string.minLength': 'The {{ field }} field must be at least {{ min }} characters long.',
  // Per-field messages override generic messages
  'title.required': 'Please enter a policy title.',
})
```

---

## Workflow Transition Validator

```typescript
// app/validators/workflow_validator.ts
import vine from '@vinejs/vine'

const workflowStatuses = [
  'DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED_L1',
  'APPROVED_FINAL', 'PUBLISHED', 'CHANGES_REQUESTED', 'REJECTED', 'WITHDRAWN',
] as const

export const submitForReviewValidator = vine.compile(
  vine.object({
    changeJustification: vine.string().trim().minLength(10).optional(),
    reviewerIds: vine.array(vine.string().uuid()).minLength(1),
  })
)

export const requestChangesValidator = vine.compile(
  vine.object({
    comment: vine.string().trim().minLength(10),
  })
)
```

---

## File Organisation

One validator file per domain entity in `app/validators/`. Export named
validators (not a default export) to make imports explicit:

```typescript
// app/validators/policy_validator.ts
export const createPolicyValidator = ...
export const updatePolicyValidator = ...

// app/validators/workflow_validator.ts
export const submitForReviewValidator = ...
export const requestChangesValidator = ...
export const approveValidator = ...

// app/validators/comment_validator.ts
export const createCommentValidator = ...
export const resolveCommentValidator = ...
```
