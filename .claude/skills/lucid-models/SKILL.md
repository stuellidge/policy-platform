# Lucid ORM Models (AdonisJS v7)

## Critical v7 Change: Auto-Generated Column Definitions

**In v7, `@column()` decorators for schema columns are auto-generated into the model
after running `node ace migration:run`. Do NOT write them manually.**

```typescript
// ❌ WRONG in v7 — never hand-write @column() decorators for schema columns
export default class Policy extends BaseModel {
  @column({ isPrimary: true })
  declare id: string

  @column()
  declare title: string

  @column()
  declare ownerId: string

  @column.dateTime({ autoCreate: true })
  declare createdAt: DateTime
}

// ✅ CORRECT in v7 — only define relationships, computed props, hooks, and scopes
// Run `node ace migration:run` to auto-generate the @column() definitions
export default class Policy extends BaseModel {
  @belongsTo(() => User, { foreignKey: 'ownerId' })
  declare owner: BelongsTo<typeof User>

  @hasMany(() => PolicyVersion)
  declare versions: HasMany<typeof PolicyVersion>

  @manyToMany(() => AudienceGroup, {
    pivotTable: 'policy_audience_groups',
  })
  declare audienceGroups: ManyToMany<typeof AudienceGroup>

  // Computed property — not a DB column
  get isPublished() {
    return this.status === 'PUBLISHED'
  }
}
```

When you run `node ace migration:run`, the framework reads the migration schema
and writes the `@column()` decorators automatically into the model file. After that
command, the model will contain the complete column definitions — you never need to
type them.

---

## Model Generation

Always use the generator. Never hand-write a model file:

```bash
node ace make:model policy
node ace make:model policy_version
node ace make:model workflow_instance
```

---

## What TO Define in Models

After the generator runs and after `migration:run` populates columns, manually add:

### Relationships

```typescript
import {
  BaseModel,
  belongsTo,
  hasMany,
  hasOne,
  manyToMany,
  hasManyThrough,
} from '@adonisjs/lucid/orm'
import type {
  BelongsTo,
  HasMany,
  HasOne,
  ManyToMany,
  HasManyThrough,
} from '@adonisjs/lucid/types/relations'

export default class Policy extends BaseModel {
  // BelongsTo — this model holds the foreign key (owner_id)
  @belongsTo(() => User, { foreignKey: 'ownerId' })
  declare owner: BelongsTo<typeof User>

  // HasMany — related model holds the foreign key
  @hasMany(() => PolicyVersion)
  declare versions: HasMany<typeof PolicyVersion>

  // HasOne — same as hasMany but returns single record
  @hasOne(() => WorkflowInstance)
  declare workflowInstance: HasOne<typeof WorkflowInstance>

  // ManyToMany — pivot table joins the two models
  @manyToMany(() => AudienceGroup, {
    pivotTable: 'policy_audience_groups',
    pivotTimestamps: true,
  })
  declare audienceGroups: ManyToMany<typeof AudienceGroup>

  // HasManyThrough — cross two relationships
  @hasManyThrough([() => PolicyChunk, () => PolicyVersion])
  declare chunks: HasManyThrough<typeof PolicyChunk>
}
```

### Query Scopes

```typescript
import { scope } from '@adonisjs/lucid/orm'

export default class Policy extends BaseModel {
  // Reusable filter — call as Policy.query().apply((s) => s.published())
  static published = scope((query) => {
    query.where('status', 'PUBLISHED')
  })

  // Scope with parameter
  static forAudience = scope((query, groupIds: string[]) => {
    query.whereHas('audienceGroups', (q) => {
      q.whereIn('audience_groups.id', groupIds)
    })
  })
}

// Usage
const policies = await Policy.query()
  .apply((s) => s.published())
  .apply((s) => s.forAudience(user.audienceGroupIds))
```

### Hooks

```typescript
import { beforeCreate, afterCreate, beforeSave } from '@adonisjs/lucid/orm'
import { cuid } from '@adonisjs/core/helpers'

export default class Policy extends BaseModel {
  @beforeCreate()
  static assignId(policy: Policy) {
    if (!policy.id) {
      policy.id = cuid()
    }
  }

  @afterCreate()
  static async createInitialVersion(policy: Policy) {
    await PolicyVersion.create({
      policyId: policy.id,
      versionNumber: 1,
    })
  }

  // $dirty tracks which fields have changed since last load/save
  @beforeSave()
  static trackChanges(policy: Policy) {
    if (policy.$dirty.status) {
      policy.lastStatusChangedAt = DateTime.now()
    }
  }
}
```

### Computed Properties

```typescript
export default class Policy extends BaseModel {
  // Getter — not stored in DB, not serialized by default
  get isPublished() {
    return this.status === 'PUBLISHED'
  }

  get displayTitle() {
    return this.title ?? 'Untitled Policy'
  }
}
```

---

## CRUD Operations

```typescript
// Create
const policy = await Policy.create({
  title: 'Expense Policy',
  ownerId: user.id,
  status: 'DRAFT',
})

// Find — returns null if not found
const policy = await Policy.find(params.id)

// FindOrFail — throws 404 ModelNotFoundException if not found
const policy = await Policy.findOrFail(params.id)

// Find by other column
const policy = await Policy.findByOrFail('slug', params.slug)

// Update — merge then save
const policy = await Policy.findOrFail(params.id)
policy.merge({ title: data.title, status: data.status })
await policy.save()

// Delete
await policy.delete()
```

---

## Query Builder

```typescript
// Basic query
const policies = await Policy.query()
  .where('owner_id', user.id)
  .whereIn('status', ['DRAFT', 'SUBMITTED'])
  .orderBy('updated_at', 'desc')
  .limit(20)

// Preload relationships — always preload, never lazy-load in loops
const policies = await Policy.query()
  .preload('owner')
  .preload('audienceGroups')
  .preload('workflowInstance', (q) => {
    q.preload('reviewers')
  })

// Pagination
const page = await Policy.query()
  .apply((s) => s.published())
  .paginate(request.input('page', 1), 20)

// Count
const total = await Policy.query().count('* as count').first()

// Exists check
const exists = await Policy.query()
  .where('slug', slug)
  .whereNot('id', params.id)
  .first()
if (exists) {
  // handle duplicate
}
```

---

## DateTime Handling

DateTime columns use Luxon `DateTime` objects — never strings.

```typescript
import { DateTime } from 'luxon'

// ✅ Pass DateTime objects
policy.reviewDate = DateTime.now().plus({ months: 12 })
policy.effectiveDate = DateTime.fromISO('2025-01-01')

// ❌ Never pass strings to DateTime columns
policy.reviewDate = '2025-01-01'  // will fail or store incorrectly

// Comparing dates
if (policy.reviewDate < DateTime.now()) {
  // policy is overdue for review
}

// Formatting for display (do in transformer or frontend, not in model)
policy.reviewDate.toISODate()           // '2025-01-01'
policy.reviewDate.toFormat('dd MMM yyyy')  // '01 Jan 2025'
```

---

## Many-to-Many Operations

```typescript
// ATTACH — adds to pivot without touching existing rows (use for CREATE)
await policy.$attach('audienceGroups', [groupId1, groupId2])

// With pivot data
await policy.$attach('audienceGroups', {
  [groupId1]: { assigned_by: user.id },
})

// SYNC — replaces all pivot rows (use for UPDATE)
await policy.$sync('audienceGroups', [groupId1, groupId2])

// DETACH — removes specific entries
await policy.$detach('audienceGroups', [groupId1])

// ❌ Common mistake: using attach on update (accumulates duplicates)
// Always use sync when replacing an audience group assignment
```

---

## Serialization: Use Transformers (v7)

In v7, model serialization uses the transformer layer, not `$visible`/`$hidden` on the model.
See the `adonisjs-transformers` skill for the full pattern.

```typescript
// ❌ v6 pattern — don't do this in v7
export default class User extends BaseModel {
  static readonly $hidden = ['password', 'idpSubject']
}

// ✅ v7 pattern — use a transformer
// app/transformers/user_transformer.ts (node ace make:transformer user)
// Controls exactly what goes to the frontend, with types flowing to the client
```

---

## Raw Queries

When you need SQL that the query builder can't express:

```typescript
import db from '@adonisjs/lucid/services/db'

// Raw query — always use snake_case column names in raw SQL
const results = await db.rawQuery(
  'SELECT * FROM policies WHERE owner_id = ? AND status = ANY(?)',
  [userId, ['DRAFT', 'SUBMITTED']]
)

// Inserting with raw for pgvector
await db.rawQuery(
  'UPDATE policy_chunks SET embedding = ?::vector WHERE id = ?',
  [JSON.stringify(embedding), chunkId]
)
```

---

## N+1 Prevention

```typescript
// ❌ N+1 — executes one query per policy
const policies = await Policy.all()
for (const policy of policies) {
  const owner = await policy.related('owner').query().first()  // N queries!
}

// ✅ Preload — two queries total (policies + owners)
const policies = await Policy.query().preload('owner')
for (const policy of policies) {
  console.log(policy.owner.displayName)  // already loaded
}

// Nested preload
const policies = await Policy.query()
  .preload('workflowInstance', (q) => {
    q.preload('reviewers')
     .preload('approvals')
  })
```
