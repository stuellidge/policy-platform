# Inertia + React (AdonisJS v7)

This project uses **React + Inertia** as the frontend layer. There are no
Edge.js templates except the single `resources/views/inertia_layout.edge`
server shell — you never edit that file directly.

All frontend work happens in:
- `inertia/pages/` — page components (one per route)
- `inertia/components/` — shared UI components
- `inertia/layouts/` — layout wrappers (admin, portal)

---

## How Inertia Works in AdonisJS v7

1. Controller calls `inertia.render('page/name', { props })` — server sends a JSON blob
2. React receives props and renders the page component — no full page reload
3. Subsequent navigations: Inertia intercepts links, fetches JSON diff, updates only changed props
4. SSR: first request is server-rendered HTML; client hydrates on load

The page name (`'authoring/policies/index'`) maps to
`inertia/pages/authoring/policies/index.tsx`.

---

## Rendering from a Controller

```typescript
// app/controllers/authoring/policies_controller.ts
import PolicyTransformer from '#transformers/policy_transformer'

async index({ inertia, auth }: HttpContext) {
  const user = auth.getUserOrFail()
  const policies = await Policy.query()
    .where('owner_id', user.id)
    .orderBy('updated_at', 'desc')

  return inertia.render('authoring/policies/index', {
    policies: await PolicyTransformer.collection(policies),
  })
}
```

---

## Page Component Structure

```tsx
// inertia/pages/authoring/policies/index.tsx
import type { InferPageProps } from '@adonisjs/inertia/types'
import type PoliciesController from '#controllers/authoring/policies_controller'
import AdminLayout from '~/layouts/admin_layout'

// Props are inferred from what the controller passes to inertia.render()
// TypeScript errors if props don't match — this is v7's type-safe page system
type Props = InferPageProps<typeof PoliciesController, 'index'>

export default function PoliciesIndex({ policies }: Props) {
  return (
    <AdminLayout title="My Policies">
      <ul>
        {policies.map((policy) => (
          <li key={policy.id}>
            <Link href={route('policies.edit', { id: policy.id })}>{policy.title}</Link>
            <span>{policy.status}</span>
          </li>
        ))}
      </ul>
    </AdminLayout>
  )
}
```

---

## Shared Data via InertiaMiddleware

Shared data (auth user, flash messages, roles) is injected into **every**
Inertia response via `app/middleware/inertia_middleware.ts`.

**Do not** add shared data in `config/inertia.ts` — that was v6 behaviour.

```typescript
// app/middleware/inertia_middleware.ts
import type { HttpContext } from '@adonisjs/core/http'
import type { NextFn } from '@adonisjs/core/types/http'
import { InertiaMiddlewareContract } from '@adonisjs/inertia/types'
import UserTransformer from '#transformers/user_transformer'

export default class InertiaMiddleware implements InertiaMiddlewareContract {
  async handle({ auth, inertia, session }: HttpContext, next: NextFn) {
    inertia.share({
      // Auth user — available on every page as usePage().props.auth
      auth: async () => {
        const user = await auth.user
        if (!user) return null
        await user.load('roles')
        return {
          user: await UserTransformer.transform(user),
          roles: user.roles.map((r) => r.name),
        }
      },

      // Flash messages — survives one redirect
      flash: session.flashMessages.all(),

      // Validation errors (v7 key)
      errors: session.flashMessages.get('inputErrorsBag'),
    })

    await next()
  }
}
```

### Consuming shared data in React

```tsx
import { usePage } from '@inertiajs/react'
import type { SharedData } from '~/types'   // define your shared data type here

export default function AdminLayout({ children, title }: { children: React.ReactNode; title: string }) {
  const { auth, flash, errors } = usePage<SharedData>().props

  return (
    <div>
      <nav>
        {auth?.user && <span>Welcome, {auth.user.displayName}</span>}
        {auth?.roles.includes('policy:admin') && <a href="/admin">Admin</a>}
      </nav>

      {flash?.success && <div className="alert success">{flash.success}</div>}
      {flash?.error && <div className="alert error">{flash.error}</div>}

      <main>{children}</main>
    </div>
  )
}
```

---

## Type-Safe Navigation

```tsx
import { Link } from '@inertiajs/react'
import { urlFor } from '@adonisjs/core/services/url_builder'  // server-side
// For client-side: the route() helper from @tuyau/client (configured in inertia/client.ts)
import { route } from '~/client'

// Link component — Inertia handles navigation without full page reload
<Link href={route('policies.edit', { id: policy.id })}>
  Edit
</Link>

// Programmatic navigation
import { router } from '@inertiajs/react'
router.visit(route('policies.index'))
router.post(route('policies.workflow.submit', { id: policy.id }), data)
```

---

## Form Submissions

```tsx
import { useForm } from '@inertiajs/react'
import { route } from '~/client'

export default function CreatePolicy() {
  const { data, setData, post, processing, errors } = useForm({
    title: '',
    purpose: '',
  })

  function submit(e: React.FormEvent) {
    e.preventDefault()
    post(route('policies.store'))
  }

  return (
    <form onSubmit={submit}>
      <label>
        Title
        <input
          value={data.title}
          onChange={(e) => setData('title', e.target.value)}
        />
        {errors.title && <span className="error">{errors.title}</span>}
      </label>

      <button disabled={processing}>
        {processing ? 'Saving…' : 'Save Draft'}
      </button>
    </form>
  )
}
```

---

## Layouts

Two layouts — `admin_layout.tsx` (authoring/admin surface) and
`portal_layout.tsx` (reader portal). Both receive shared data from
`InertiaMiddleware`.

```tsx
// inertia/layouts/admin_layout.tsx
import { usePage } from '@inertiajs/react'

interface Props {
  children: React.ReactNode
  title?: string
}

export default function AdminLayout({ children, title = 'PolicyHub' }: Props) {
  const { auth } = usePage<SharedData>().props

  return (
    <html>
      <head><title>{title} — PolicyHub</title></head>
      <body>
        <nav>PolicyHub nav here</nav>
        <main>{children}</main>
      </body>
    </html>
  )
}
```

---

## SSR Considerations

SSR is enabled by default in v7. A few rules:

- **No `window` or `document` in SSR** — guard browser-only APIs with `typeof window !== 'undefined'` or use `useEffect`
- **Monaco Editor and TipTap are client-only** — import them with dynamic imports:

```tsx
import React from 'react'  // or use conditional rendering

// Monaco diff viewer — client-only
const MonacoDiffViewer = React.lazy(() =>
  import('~/components/diff/monaco_diff_viewer')
)

// Wrap in Suspense with a fallback
<React.Suspense fallback={<div>Loading diff viewer…</div>}>
  <MonacoDiffViewer original={published} modified={draft} />
</React.Suspense>
```

---

## v7 Entry Points (Changed from v6)

```
v6: inertia/app/app.tsx      → v7: inertia/app.tsx
v6: inertia/app/ssr.tsx      → v7: inertia/ssr.tsx
```

Never create `inertia/app/` subdirectory — the entry files live at the
root of `inertia/`.

---

## Inertia Config (v7)

```typescript
// config/inertia.ts — v7 shape
import { defineConfig } from '@adonisjs/inertia'

export default defineConfig({
  // ✅ v7 key
  encryptHistory: true,

  // ❌ v6 keys — removed in v7
  // history: { encrypt: true }
  // sharedData: {}        → moved to InertiaMiddleware
  // entrypoint: '...'    → removed, inferred from inertia/app.tsx
})
```
