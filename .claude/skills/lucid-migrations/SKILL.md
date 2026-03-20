# Lucid Migrations (AdonisJS v7)

## Key v7 Note: Migrations Trigger Model Schema Generation

Running `node ace migration:run` does two things in v7:
1. Applies the migration to the database (same as v6)
2. **Auto-generates `@column()` decorators into the corresponding model files**

This means migration column definitions are the single source of truth for the
model schema. Define columns accurately in migrations — do not also write them
in the model.

---

## Migration Generation

Always use the generator:

```bash
node ace make:migration create_policies_table
node ace make:migration add_current_version_fk_to_policies_table
node ace make:migration create_pgvector_extension    # for AI embeddings
```

Files are timestamp-prefixed automatically and must run in dependency order.

---

## Migration Structure

```typescript
// database/migrations/1700000000001_create_policies_table.ts
import { BaseSchema } from '@adonisjs/lucid/schema'

export default class extends BaseSchema {
  protected tableName = 'policies'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.uuid('id').primary().defaultTo(this.db.rawQuery('gen_random_uuid()').knexQuery)
      table.string('title', 500).notNullable()
      table.string('slug', 500).notNullable().unique()
      table.text('purpose').nullable()
      table.string('status', 50).notNullable().defaultTo('DRAFT')
      table.uuid('owner_id').notNullable().unsigned().references('id').inTable('users').onDelete('RESTRICT')
      table.uuid('category_id').nullable().unsigned().references('id').inTable('categories').onDelete('SET NULL')
      table.string('gitlab_file_path', 1000).nullable()
      table.string('gitlab_branch_name', 255).nullable()
      table.timestamp('effective_date', { useTz: true }).nullable()
      table.timestamp('review_date', { useTz: true }).nullable()

      // Standard timestamp columns — always use { useTz: true }
      table.timestamp('created_at', { useTz: true }).notNullable()
      table.timestamp('updated_at', { useTz: true }).notNullable()
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
```

### Critical rules

- `down()` must exactly reverse `up()` — if `up()` creates a table, `down()` drops it
- Always `{ useTz: true }` on every timestamp — never omit this
- Always `.unsigned()` on foreign key integer/bigint columns (uuid FKs don't need it)
- Never drop or rename columns in production without a coordinated deploy

---

## Column Types

### Numeric
```typescript
table.increments('id')                    // auto-increment integer PK
table.bigIncrements('id')                 // auto-increment bigint PK
table.uuid('id').primary()               // UUID PK (use gen_random_uuid())
table.integer('version_number').notNullable()
table.bigInteger('gitlab_mr_iid').nullable()
table.decimal('score', 8, 2).nullable()
table.float('confidence').nullable()
table.boolean('is_active').notNullable().defaultTo(true)
```

### String / Text
```typescript
table.string('title', 500).notNullable()
table.string('slug', 255).notNullable().unique()
table.text('body_html').nullable()
table.uuid('idp_subject').notNullable()
table.enum('status', ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED_L1', 'APPROVED_FINAL', 'PUBLISHED', 'CHANGES_REQUESTED', 'REJECTED', 'WITHDRAWN'])
table.json('metadata').nullable()
table.jsonb('settings').nullable()
table.specificType('embedding', 'vector(1536)').nullable()  // pgvector
```

### Date / Time
```typescript
table.timestamp('created_at', { useTz: true }).notNullable()
table.timestamp('review_date', { useTz: true }).nullable()
table.date('effective_date').nullable()
```

---

## Column Modifiers

```typescript
table.string('title').notNullable()           // NOT NULL
table.string('avatar_url').nullable()         // NULL allowed
table.string('slug').unique()                 // unique constraint
table.integer('count').defaultTo(0)           // default value
table.string('slug').index()                  // btree index
```

---

## Foreign Keys

```typescript
// Inline (preferred for simple cases)
table.uuid('owner_id')
  .notNullable()
  .references('id')
  .inTable('users')
  .onDelete('CASCADE')      // or 'RESTRICT', 'SET NULL'

// Separate constraint (useful when both tables are new in the same migration)
table.uuid('owner_id').notNullable()
// ... other columns ...
table.foreign('owner_id').references('users.id').onDelete('CASCADE')
```

---

## Indexes

```typescript
// Single-column index
table.index('owner_id')
table.index('email')

// Composite index
table.index(['owner_id', 'status'])

// Named index (useful for later dropping)
table.index('created_at', 'idx_policies_created_at')

// Unique index via constraint
table.unique(['idp_subject', 'idp_provider'])
```

---

## Altering Tables

```typescript
async up() {
  this.schema.alterTable('policies', (table) => {
    table.uuid('current_version_id').nullable().references('id').inTable('policy_versions').onDelete('SET NULL')
    table.string('gitlab_mr_iid', 50).nullable()
  })
}

async down() {
  this.schema.alterTable('policies', (table) => {
    table.dropColumn('current_version_id')
    table.dropColumn('gitlab_mr_iid')
  })
}
```

---

## Raw SQL — pgvector Extension

This project requires pgvector. The extension must be enabled before any table
that uses `vector` columns is created.

```typescript
// database/migrations/1700000000000_create_pgvector_extension.ts
import { BaseSchema } from '@adonisjs/lucid/schema'

export default class extends BaseSchema {
  async up() {
    await this.db.rawQuery('CREATE EXTENSION IF NOT EXISTS vector')
  }

  async down() {
    // Do not drop in production — other tables depend on it
    // await this.db.rawQuery('DROP EXTENSION IF EXISTS vector')
  }
}
```

The pgvector extension migration must run **before** any migration that creates
a `vector` column. Run it as the first or second migration (after `users`).

### Using pgvector in a table migration

```typescript
// database/migrations/.../create_policy_chunks_table.ts
export default class extends BaseSchema {
  protected tableName = 'policy_chunks'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.uuid('id').primary().defaultTo(this.db.rawQuery('gen_random_uuid()').knexQuery)
      table.uuid('policy_version_id').notNullable().references('id').inTable('policy_versions').onDelete('CASCADE')
      table.text('content').notNullable()
      table.integer('chunk_index').notNullable()
      table.string('section_heading', 500).nullable()
      table.specificType('embedding', 'vector(1536)').nullable()  // pgvector column
      table.timestamp('created_at', { useTz: true }).notNullable()
      table.timestamp('updated_at', { useTz: true }).notNullable()
    })

    // HNSW index for fast approximate nearest-neighbour search
    await this.db.rawQuery(`
      CREATE INDEX ON policy_chunks
      USING hnsw (embedding vector_cosine_ops)
    `)
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
```

---

## Pivot Tables

Many-to-many pivot tables have no model — just a migration:

```typescript
// database/migrations/.../create_policy_audience_groups_table.ts
export default class extends BaseSchema {
  protected tableName = 'policy_audience_groups'

  async up() {
    this.schema.createTable(this.tableName, (table) => {
      table.uuid('policy_id').notNullable().references('id').inTable('policies').onDelete('CASCADE')
      table.uuid('audience_group_id').notNullable().references('id').inTable('audience_groups').onDelete('CASCADE')
      table.timestamp('created_at', { useTz: true }).notNullable()

      table.primary(['policy_id', 'audience_group_id'])
    })
  }

  async down() {
    this.schema.dropTable(this.tableName)
  }
}
```

---

## CLI Commands

```bash
# Create a new migration
node ace make:migration create_policies_table

# Run all pending migrations (also triggers model schema generation in v7)
node ace migration:run

# Roll back last batch
node ace migration:rollback

# Roll back specific number of steps
node ace migration:rollback --step=3

# Check migration status
node ace migration:status

# Wipe and re-run (development only — destroys all data)
node ace migration:fresh

# Wipe, re-run, and re-seed
node ace migration:fresh --seed
```

---

## Soft Deletes

```typescript
table.timestamp('deleted_at', { useTz: true }).nullable()

// Query — filter out soft-deleted rows in model scope
static notDeleted = scope((query) => {
  query.whereNull('deleted_at')
})
```

---

## Common Patterns

### UUID primary key with gen_random_uuid()
```typescript
table.uuid('id').primary().defaultTo(
  this.db.rawQuery('gen_random_uuid()').knexQuery
)
```

### Standard timestamps
```typescript
// Always the last two columns
table.timestamp('created_at', { useTz: true }).notNullable()
table.timestamp('updated_at', { useTz: true }).notNullable()
```

### Composite unique constraint
```typescript
table.unique(['idp_subject', 'idp_provider'])
table.unique(['policy_id', 'version_number'])
```
