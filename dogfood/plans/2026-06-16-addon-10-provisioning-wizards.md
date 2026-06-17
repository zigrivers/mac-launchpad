# Add-on 10 — Guided provisioning wizards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three `launchpad add <supabase|stripe|vercel>` wizards that scaffold a working, tested Supabase auth / Stripe checkout / Vercel deploy onto the Next.js web template, with the interactive login handled by an agent recipe.

**Architecture:** A shared `scripts/provision-common.sh` library (pure, unit-tested helpers) sourced by three self-contained wrapper scripts. Each wrapper: confirm a Next.js project, install the SDK/CLI, scaffold app code **only if absent**, validate + write keys to `.env.local`. The interactive `*-login` is sign-in-gated (agent recipe + docs); scaffolds/keys/installs are VM-validated with mock CLIs + a `tsc --noEmit` compile check.

**Tech Stack:** bash 3.2, Next.js 16 App Router (`app/`, `--no-src-dir`, `@/*`→root, TypeScript), `@supabase/ssr`, `stripe`, the `supabase`/`stripe`/`vercel` CLIs, the `tests/lib.sh` harness.

**Spec:** `dogfood/specs/2026-06-16-addon-10-provisioning-wizards-design.md`.

## Build-time verified facts (Context7, 2026-06-17)

- **Supabase `@supabase/ssr`:** browser = `createBrowserClient(url, key)`; server = `createServerClient(url, key, { cookies: { getAll, setAll } })` with `const cookieStore = await cookies()` (cookies() is async in Next 15/16). Auth: `supabase.auth.signInWithPassword({email,password})`, `signUp({email,password})`, `signOut()`, `getUser()` (verified identity). Session refresh via `middleware.ts`.
- **Stripe:** `new Stripe(process.env.STRIPE_SECRET_KEY!)`; `stripe.checkout.sessions.create({ mode:'payment', line_items:[{price_data:{currency,product_data:{name},unit_amount},quantity}], success_url, cancel_url })` → use `session.url` for a hosted-redirect (no `@stripe/stripe-js` needed); webhook `stripe.webhooks.constructEvent(rawBody, sig, secret)` needs the **raw** body (`await req.text()` in a route handler; `req.headers.get('stripe-signature')`).
- **Web template:** `create-next-app --ts --app --tailwind --no-src-dir --import-alias "@/*"` → files in `app/`, root `middleware.ts`, `lib/…`, `@/lib/…` imports.
- **Vercel CLI** (stable; mocked in tests): `vercel link --yes`, `printf '%s' "$v" | vercel env add <NAME> production`, `vercel deploy --prod`.

## Conventions for the implementer

- `scripts/provision-common.sh` is a **library** (no `main`, no source-guard `main` call) — it only defines functions. The three wrappers `. "$HERE/provision-common.sh"`. `tests/test-provision.sh` sources it directly.
- Each wrapper ends with the source-guard `if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then set -uo pipefail; main "$@"; fi`.
- **Scaffold-if-absent:** `scaffold_if_absent <path> <<'EOF' … EOF` writes the heredoc to `<path>` only if it doesn't exist; logs "exists, skipped" otherwise. NEVER overwrite.
- Keys → `.env.local` via `env_upsert` (ENVIRON-safe, from `sentry-setup.sh`). When `op whoami` works, print the `launchpad secrets` tip.
- Commit per task with the given messages. `chmod +x` the wrappers (commit `100755`). Do NOT push.
- Heredocs that contain `$` (TS using `process.env`, template literals) MUST be quoted (`<<'EOF'`) so bash doesn't expand them.

---

### Task 1: `scripts/provision-common.sh` + unit tests

**Files:** Create `scripts/provision-common.sh`, `tests/test-provision.sh`.

- [ ] **Step 1: Write `tests/test-provision.sh` (failing)**

```bash
#!/usr/bin/env bash
# tests/test-provision.sh
cd "$(dirname "$0")/.." || exit 1
. tests/lib.sh
. scripts/provision-common.sh

# supabase_url_valid: https://<ref>.supabase.co
supabase_url_valid 'https://abcdefgh.supabase.co'; assert_eq "$?" "0" "supabase url ok"
supabase_url_valid 'https://abcdefgh.supabase.co/'; assert_eq "$?" "0" "supabase url trailing slash ok"
supabase_url_valid 'http://abcdefgh.supabase.co';  assert_eq "$?" "1" "supabase url http rejected"
supabase_url_valid 'https://evil.example.com';     assert_eq "$?" "1" "supabase url non-supabase rejected"
supabase_url_valid 'nope';                          assert_eq "$?" "1" "supabase url junk rejected"

# stripe key validators: test-mode only
stripe_test_secret_valid 'sk_test_51abcXYZ'; assert_eq "$?" "0" "sk_test ok"
stripe_test_secret_valid 'sk_live_51abcXYZ'; assert_eq "$?" "1" "sk_live rejected (use test mode)"
stripe_test_secret_valid 'pk_test_51abc';    assert_eq "$?" "1" "pk is not a secret key"
stripe_pub_valid 'pk_test_51abcXYZ';         assert_eq "$?" "0" "pk_test ok"
stripe_pub_valid 'pk_live_51abcXYZ';         assert_eq "$?" "1" "pk_live rejected"

# env_upsert: add + replace, no dupes, backslash-safe
d="$(mktemp -d)"; f="$d/.env.local"
env_upsert "$f" FOO bar; assert_eq "$(cat "$f")" "FOO=bar" "env_upsert creates"
env_upsert "$f" FOO baz; assert_eq "$(grep '^FOO=' "$f")" "FOO=baz" "env_upsert replaces"
assert_eq "$(grep -c '^FOO=' "$f")" "1" "env_upsert no dupe"

# env_keys: list KEY names, skip comments/blanks
g="$(mktemp -d)/.env.local"; printf '# a comment\nA=1\n\nB=two=parts\n' > "$g"
assert_eq "$(env_keys "$g" | paste -sd, -)" "A,B" "env_keys lists keys, skips comments/blanks"

# is_next_project: true only when package.json has a next dependency
p1="$(mktemp -d)"; printf '{ "dependencies": { "next": "16.0.0" } }' > "$p1/package.json"
( cd "$p1" && is_next_project ); assert_eq "$?" "0" "is_next_project true with next dep"
p2="$(mktemp -d)"; printf '{ "dependencies": {} }' > "$p2/package.json"
( cd "$p2" && is_next_project ); assert_eq "$?" "1" "is_next_project false without next"
p3="$(mktemp -d)"; ( cd "$p3" && is_next_project ); assert_eq "$?" "1" "is_next_project false with no package.json"

# scaffold_if_absent: writes once, never clobbers
s="$(mktemp -d)/app/x.tsx"
printf 'ORIGINAL' | scaffold_if_absent "$s" >/dev/null; assert_eq "$(cat "$s")" "ORIGINAL" "scaffold writes when absent"
printf 'SECOND'   | scaffold_if_absent "$s" >/dev/null; assert_eq "$(cat "$s")" "ORIGINAL" "scaffold never clobbers"

t_done
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-provision.sh` → FAIL (functions undefined).

- [ ] **Step 3: Write `scripts/provision-common.sh`**

```bash
#!/usr/bin/env bash
# scripts/provision-common.sh — shared, pure-ish helpers for the launchpad add
# wizards (supabase/stripe/vercel). A LIBRARY: defines functions only, no main.
# Sourced by scripts/add-*.sh and by tests/test-provision.sh.

# is_next_project -> 0 if the CWD is a Next.js project (package.json with a next dep)
is_next_project() {
  [ -f package.json ] || return 1
  grep -qE '"next"[[:space:]]*:' package.json
}

# supabase_url_valid <s> -> 0 if it looks like https://<ref>.supabase.co
supabase_url_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in
    https://*.supabase.co|https://*.supabase.co/) return 0 ;;
    *) return 1 ;;
  esac
}

# stripe_test_secret_valid <s> -> 0 only for a TEST-mode secret key
stripe_test_secret_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in sk_test_*) return 0 ;; *) return 1 ;; esac
}

# stripe_pub_valid <s> -> 0 only for a TEST-mode publishable key
stripe_pub_valid() {
  case "$1" in *[![:graph:]]*) return 1 ;; esac
  case "$1" in pk_test_*) return 0 ;; *) return 1 ;; esac
}

# env_upsert <file> <key> <val> — add/replace KEY=val (ENVIRON-safe, no escape processing)
env_upsert() {
  local file="$1" key="$2" val="$3" tmp
  [ -d "$(dirname "$file")" ] || mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  if [ -f "$file" ] && grep -qE "^${key}=" "$file"; then
    K="$key" V="$val" awk 'BEGIN{FS="="} $1==ENVIRON["K"]{print ENVIRON["K"]"="ENVIRON["V"]; next} {print}' "$file" >"$tmp"
  else
    [ -f "$file" ] && cat "$file" >"$tmp"
    printf '%s=%s\n' "$key" "$val" >>"$tmp"
  fi
  mv "$tmp" "$file"
}

# env_keys <file> -> list KEY names (skip comments/blanks)
env_keys() {
  [ -f "$1" ] || return 0
  awk -F= '/^[[:space:]]*#/ || /^[[:space:]]*$/ {next} /=/ {print $1}' "$1"
}

# scaffold_if_absent <path>  (content on stdin) — write only if the file is absent
scaffold_if_absent() {
  local path="$1"
  if [ -e "$path" ]; then
    cat >/dev/null   # drain stdin
    printf '  exists, skipped: %s\n' "$path"
    return 0
  fi
  [ -d "$(dirname "$path")" ] || mkdir -p "$(dirname "$path")"
  cat > "$path"
  printf '  wrote: %s\n' "$path"
}

# _op_tip — if 1Password is signed in, suggest storing keys there (Add-on 08)
_op_tip() {
  if command -v op >/dev/null 2>&1 && op whoami >/dev/null 2>&1; then
    printf 'tip: with 1Password set up, `launchpad secrets set <NAME>` keeps keys out of .env.local.\n'
  fi
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-provision.sh` → all `ok`, `PASS`.

- [ ] **Step 5: Shellcheck + commit**

Run: `shellcheck -S warning scripts/provision-common.sh` (clean; info SC2016 ok).
```bash
git add scripts/provision-common.sh tests/test-provision.sh
git commit -m "feat(add): provision-common.sh — shared validators/env helpers + tests"
```

---

### Task 2: `scripts/add-supabase.sh` (Supabase auth wizard)

**Files:** Create `scripts/add-supabase.sh`.

- [ ] **Step 1: Write `scripts/add-supabase.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/add-supabase.sh — `launchpad add supabase [--url <u>] [--anon-key <k>]`
#
# Scaffold email/password auth (Supabase, @supabase/ssr) onto the Next.js web
# template: a browser + server client, session-refresh middleware, a login page,
# and a logged-in-only dashboard. Writes NEXT_PUBLIC_SUPABASE_URL / _ANON_KEY to
# .env.local. The interactive `supabase login` + project creation is a human step
# (see the AGENTS.md "add login" recipe); this wrapper does the deterministic rest.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./provision-common.sh
. "$HERE/provision-common.sh"

main() {
  local url="" anon=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --url) url="${2:-}"; shift 2 ;;
      --url=*) url="${1#*=}"; shift ;;
      --anon-key) anon="${2:-}"; shift 2 ;;
      --anon-key=*) anon="${1#*=}"; shift ;;
      -h|--help) echo "usage: launchpad add supabase [--url <project-url>] [--anon-key <anon-key>]"; return 0 ;;
      *) shift ;;
    esac
  done

  if ! is_next_project; then
    echo "run this inside a Next.js project (no package.json with a 'next' dependency here)." >&2
    return 1
  fi

  echo "Installing @supabase/ssr + @supabase/supabase-js…"
  npm install @supabase/ssr @supabase/supabase-js >/dev/null 2>&1 || { echo "npm install failed" >&2; return 1; }

  scaffold_if_absent lib/supabase/client.ts <<'EOF'
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  )
}
EOF

  scaffold_if_absent lib/supabase/server.ts <<'EOF'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll: (cookiesToSet) => {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            )
          } catch {
            // called from a Server Component — middleware refreshes the session
          }
        },
      },
    },
  )
}
EOF

  scaffold_if_absent middleware.ts <<'EOF'
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request })
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => request.cookies.getAll(),
        setAll: (cookiesToSet) => {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          )
        },
      },
    },
  )
  await supabase.auth.getUser()
  return response
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
EOF

  scaffold_if_absent app/login/page.tsx <<'EOF'
'use client'
import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export default function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [msg, setMsg] = useState('')
  const router = useRouter()
  const supabase = createClient()

  async function signIn() {
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setMsg(error.message)
    else router.push('/dashboard')
  }
  async function signUp() {
    const { error } = await supabase.auth.signUp({ email, password })
    setMsg(error ? error.message : 'Account created — check your email to confirm, then sign in.')
  }

  return (
    <main style={{ maxWidth: 360, margin: '4rem auto', display: 'grid', gap: 8 }}>
      <h1>Sign in</h1>
      <input placeholder="email" value={email} onChange={(e) => setEmail(e.target.value)} />
      <input placeholder="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} />
      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={signIn}>Sign in</button>
        <button onClick={signUp}>Create account</button>
      </div>
      {msg && <p>{msg}</p>}
    </main>
  )
}
EOF

  scaffold_if_absent app/dashboard/page.tsx <<'EOF'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function Dashboard() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')

  async function signOut() {
    'use server'
    const supabase = await createClient()
    await supabase.auth.signOut()
    redirect('/login')
  }

  return (
    <main style={{ maxWidth: 480, margin: '4rem auto' }}>
      <h1>Dashboard</h1>
      <p>Signed in as {user.email}.</p>
      <form action={signOut}><button>Sign out</button></form>
    </main>
  )
}
EOF

  if [ -n "$url" ]; then
    if supabase_url_valid "$url"; then env_upsert .env.local NEXT_PUBLIC_SUPABASE_URL "$url"
    else echo "warning: --url doesn't look like https://<ref>.supabase.co; not written." >&2; fi
  fi
  [ -n "$anon" ] && env_upsert .env.local NEXT_PUBLIC_SUPABASE_ANON_KEY "$anon"

  echo "Supabase auth scaffolded. Visit /login, then /dashboard (guarded)."
  [ -n "$url" ] && [ -n "$anon" ] || echo "Add NEXT_PUBLIC_SUPABASE_URL + NEXT_PUBLIC_SUPABASE_ANON_KEY to .env.local (the assistant can fetch them via 'supabase login')."
  _op_tip
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 2: Static checks**

Run: `bash -n scripts/add-supabase.sh && shellcheck -S warning scripts/add-supabase.sh` → clean.
(Functional scaffolding + `tsc` compile are exercised by the VM probe, Task 7 — do NOT run `npm install` on the host.)

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/add-supabase.sh
git add scripts/add-supabase.sh
git commit -m "feat(add): launchpad add supabase — email/password auth scaffold (@supabase/ssr)"
```

---

### Task 3: `scripts/add-stripe.sh` (Stripe payments wizard)

**Files:** Create `scripts/add-stripe.sh`.

- [ ] **Step 1: Write `scripts/add-stripe.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/add-stripe.sh — `launchpad add stripe [--secret <sk_test_…>] [--pub <pk_test_…>]`
#
# Scaffold a TEST-MODE Stripe Checkout flow onto the Next.js template: a pricing
# page with a Subscribe button, a Checkout API route, a webhook verifier, and a
# premium page. Writes STRIPE_SECRET_KEY / NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY to
# .env.local (test keys only). `stripe login` + `stripe listen` are human steps
# (see the AGENTS.md "add payments" recipe).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./provision-common.sh
. "$HERE/provision-common.sh"

main() {
  local secret="" pub=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --secret) secret="${2:-}"; shift 2 ;;
      --secret=*) secret="${1#*=}"; shift ;;
      --pub) pub="${2:-}"; shift 2 ;;
      --pub=*) pub="${1#*=}"; shift ;;
      -h|--help) echo "usage: launchpad add stripe [--secret <sk_test_…>] [--pub <pk_test_…>]"; return 0 ;;
      *) shift ;;
    esac
  done

  if ! is_next_project; then
    echo "run this inside a Next.js project (no package.json with a 'next' dependency here)." >&2
    return 1
  fi

  command -v stripe >/dev/null 2>&1 || { echo "installing the Stripe CLI…"; brew install stripe >/dev/null 2>&1 || echo "  (couldn't install the Stripe CLI — 'brew install stripe' later)"; }

  echo "Installing stripe (server SDK)…"
  npm install stripe >/dev/null 2>&1 || { echo "npm install failed" >&2; return 1; }

  scaffold_if_absent app/pricing/page.tsx <<'EOF'
'use client'
import { useState } from 'react'

export default function Pricing() {
  const [msg, setMsg] = useState('')
  async function subscribe() {
    setMsg('Redirecting to checkout…')
    const res = await fetch('/api/checkout', { method: 'POST' })
    const { url, error } = await res.json()
    if (url) window.location.href = url
    else setMsg(error || 'Could not start checkout.')
  }
  return (
    <main style={{ maxWidth: 420, margin: '4rem auto' }}>
      <h1>Premium — $5.00</h1>
      <button onClick={subscribe}>Subscribe</button>
      {msg && <p>{msg}</p>}
    </main>
  )
}
EOF

  scaffold_if_absent app/api/checkout/route.ts <<'EOF'
import Stripe from 'stripe'
import { NextResponse } from 'next/server'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

export async function POST() {
  const base = process.env.NEXT_PUBLIC_BASE_URL ?? 'http://localhost:3000'
  try {
    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      line_items: [
        {
          price_data: {
            currency: 'usd',
            product_data: { name: 'Premium' },
            unit_amount: 500,
          },
          quantity: 1,
        },
      ],
      success_url: `${base}/premium?paid=1`,
      cancel_url: `${base}/pricing`,
    })
    return NextResponse.json({ url: session.url })
  } catch (err) {
    return NextResponse.json({ error: (err as Error).message }, { status: 500 })
  }
}
EOF

  scaffold_if_absent app/api/webhook/route.ts <<'EOF'
import Stripe from 'stripe'
import { NextResponse } from 'next/server'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

export async function POST(req: Request) {
  const body = await req.text()
  const sig = req.headers.get('stripe-signature') ?? ''
  try {
    const event = stripe.webhooks.constructEvent(body, sig, process.env.STRIPE_WEBHOOK_SECRET!)
    if (event.type === 'checkout.session.completed') {
      // Payment confirmed. Persist the paid state for the customer here
      // (e.g. in Supabase) to gate /premium for real.
    }
    return NextResponse.json({ received: true })
  } catch {
    return new NextResponse('invalid signature', { status: 400 })
  }
}
EOF

  scaffold_if_absent app/premium/page.tsx <<'EOF'
export default async function Premium({
  searchParams,
}: {
  searchParams: Promise<{ paid?: string }>
}) {
  const { paid } = await searchParams
  if (paid !== '1') {
    return (
      <main style={{ maxWidth: 480, margin: '4rem auto' }}>
        <h1>Premium</h1>
        <p>This page is for paying customers. <a href="/pricing">Subscribe</a>.</p>
        <p style={{ opacity: 0.6 }}>(Demo gate via ?paid=1 — persist the webhook&apos;s
          paid state to gate this for real.)</p>
      </main>
    )
  }
  return (
    <main style={{ maxWidth: 480, margin: '4rem auto' }}>
      <h1>Premium unlocked 🎉</h1>
      <p>Thanks for subscribing.</p>
    </main>
  )
}
EOF

  if [ -n "$secret" ]; then
    if stripe_test_secret_valid "$secret"; then env_upsert .env.local STRIPE_SECRET_KEY "$secret"
    elif case "$secret" in sk_live_*) true ;; *) false ;; esac; then echo "refusing a LIVE secret key — use Stripe TEST mode (sk_test_…). Not written." >&2
    else echo "warning: --secret isn't an sk_test_ key; not written." >&2; fi
  fi
  if [ -n "$pub" ]; then
    if stripe_pub_valid "$pub"; then env_upsert .env.local NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY "$pub"
    else echo "warning: --pub isn't a pk_test_ key; not written." >&2; fi
  fi

  echo "Stripe test-mode checkout scaffolded: /pricing → Checkout → /premium; webhook at /api/webhook."
  echo "Run the webhook locally: stripe listen --forward-to localhost:3000/api/webhook (copy the whsec_ into STRIPE_WEBHOOK_SECRET)."
  _op_tip
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 2: Static checks**

Run: `bash -n scripts/add-stripe.sh && shellcheck -S warning scripts/add-stripe.sh` → clean.

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/add-stripe.sh
git add scripts/add-stripe.sh
git commit -m "feat(add): launchpad add stripe — test-mode Checkout + webhook scaffold"
```

---

### Task 4: `scripts/add-vercel.sh` (Vercel deploy wizard)

**Files:** Create `scripts/add-vercel.sh`.

- [ ] **Step 1: Write `scripts/add-vercel.sh`**

```bash
#!/usr/bin/env bash
#
# scripts/add-vercel.sh — `launchpad add vercel`
#
# Link the project to Vercel, push every key from .env.local into the project's
# Production environment, and deploy. `vercel login` is a human step (see the
# AGENTS.md "deploy" recipe). The env-push reads .env.local via env_keys; the
# vercel CLI calls are mocked in tests.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=./provision-common.sh
. "$HERE/provision-common.sh"

main() {
  case "${1:-}" in -h|--help) echo "usage: launchpad add vercel   (run inside your project; deploys to Vercel)"; return 0 ;; esac

  if ! is_next_project; then
    echo "run this inside a Next.js project." >&2; return 1
  fi
  command -v vercel >/dev/null 2>&1 || { echo "the Vercel CLI isn't installed (expected from the web stack)." >&2; return 1; }

  echo "Linking this project to Vercel…"
  vercel link --yes || { echo "vercel link failed (run 'vercel login' first?)." >&2; return 1; }

  if [ -f .env.local ]; then
    echo "Pushing .env.local keys to Vercel (production)…"
    local k v
    while IFS= read -r k; do
      [ -n "$k" ] || continue
      v="$(grep -E "^${k}=" .env.local | head -1 | cut -d= -f2-)"
      printf '%s' "$v" | vercel env add "$k" production >/dev/null 2>&1 \
        && echo "  pushed $k" || echo "  (skipped $k — may already exist)"
    done <<EOF
$(env_keys .env.local)
EOF
  fi

  echo "Deploying to production…"
  vercel deploy --prod
}

if [ "${BASH_SOURCE[0]:-}" = "${0}" ]; then
  set -uo pipefail
  main "$@"
fi
```

- [ ] **Step 2: Static checks**

Run: `bash -n scripts/add-vercel.sh && shellcheck -S warning scripts/add-vercel.sh` → clean (info SC2016 ok).

- [ ] **Step 3: Commit**

```bash
chmod +x scripts/add-vercel.sh
git add scripts/add-vercel.sh
git commit -m "feat(add): launchpad add vercel — link + push env + deploy"
```

---

### Task 5: Dispatcher + module + doctor

**Files:** Modify `scripts/launchpad`, `modules/10-web.sh`, `lib/doctor.sh`.

- [ ] **Step 1: Add the `add)` dispatcher to `scripts/launchpad`**

After the `sentry-setup)` case, add:

```bash
  add)
    case "${1:-}" in
      supabase|stripe|vercel) exec bash "$ROOT/scripts/add-$1.sh" "${@:2}" ;;
      *) echo "usage: launchpad add <supabase|stripe|vercel>" ;;
    esac ;;
```

And a usage line after the `sentry-setup` one:

```
  launchpad add       Add login (supabase) / payments (stripe) / deploy (vercel)
```

- [ ] **Step 2: Install the Stripe CLI + chmod the wrappers in `modules/10-web.sh`**

Change the existing `brew_install supabase postgresql@16 cloudflared` line to add `stripe`:

```bash
brew_install supabase stripe postgresql@16 cloudflared
```

And after the vercel-install block, add:

```bash
chmod +x "$LP_ROOT/scripts/add-supabase.sh" "$LP_ROOT/scripts/add-stripe.sh" "$LP_ROOT/scripts/add-vercel.sh" 2>/dev/null || true
```

- [ ] **Step 3: Add doctor checks (Web stack section) in `lib/doctor.sh`**

In the `if area_active web; then hdr "Web stack"` block, after the existing checks, add:

```bash
  check  "Stripe CLI"                  'command -v stripe'
  check  "provisioning wizards"        'test -x "$LP_ROOT/scripts/add-supabase.sh" && test -x "$LP_ROOT/scripts/add-stripe.sh" && test -x "$LP_ROOT/scripts/add-vercel.sh"'
```

- [ ] **Step 4: Verify**

Run: `bash scripts/launchpad add` (prints the usage line); `bash scripts/launchpad help` (shows the `add` line); `bash -n modules/10-web.sh`; `bash lib/doctor.sh web 2>&1 | grep -iE 'stripe cli|provisioning wizards'` (both lines appear — green once installed/executable); `shellcheck -S warning scripts/launchpad lib/doctor.sh modules/10-web.sh` → clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/launchpad modules/10-web.sh lib/doctor.sh
git commit -m "feat(add): launchpad add dispatcher; 10-web installs Stripe CLI + chmods wizards; doctor checks"
```

---

### Task 6: Agent recipes + docs

**Files:** Modify `config/agents/AGENTS.md`, `docs/recipes.html`, `README.md`.

- [ ] **Step 1: AGENTS.md recipes**

In `config/agents/AGENTS.md`, after the "turn on error tracking" bullet (from Add-on 09), add:

```markdown
- **Provisioning is guided, then automated.** For login/payments/deploy, walk the
  user through the one interactive login, then run the wrapper:
  - **Login (Supabase):** `supabase login` → create/link a project → copy the
    Project URL + anon key → `launchpad add supabase --url <u> --anon-key <k>`.
  - **Payments (Stripe, TEST mode):** `stripe login` → copy the test keys →
    `launchpad add stripe --secret <sk_test_…> --pub <pk_test_…>`, then
    `stripe listen --forward-to localhost:3000/api/webhook` and put the `whsec_`
    into `STRIPE_WEBHOOK_SECRET`. Never use live keys.
  - **Deploy (Vercel):** `vercel login` → `launchpad add vercel` (links, pushes
    .env.local keys to production, deploys). Hand back the URL.
```

- [ ] **Step 2: `docs/recipes.html` — note the wizards**

In the "Add a feature" section, in the **User login** entry, after the codeblock add:

```html
    <p class="muted">Shortcut: the assistant can run <code>launchpad add supabase</code> to scaffold this for you after you sign in.</p>
```

In the **Take payments** entry, after the codeblock add:

```html
    <p class="muted">Shortcut: <code>launchpad add stripe</code> scaffolds the test-mode Checkout + webhook once you've signed in to Stripe.</p>
```

In the "Put it online" section, after the deploy codeblock add:

```html
    <p class="muted">Shortcut: <code>launchpad add vercel</code> links the project, pushes your keys, and deploys.</p>
```

> ⚠️ Straight quotes only in HTML attributes/code. After editing run `grep -nP '=[\x{201C}\x{201D}]' docs/recipes.html` → must be empty.

- [ ] **Step 3: README audit row**

After the Add-on 09 row, add:

```
| **Add-on 10** | guided provisioning wizards: `launchpad add supabase` (email/password auth via @supabase/ssr), `launchpad add stripe` (test-mode Checkout + webhook), `launchpad add vercel` (link + push env + deploy) — testable shell wrappers scaffold-if-absent + write keys; the interactive logins are AGENTS.md recipes (sign-in-gated). APIs verified vs live docs 2026-06-17 |
```

- [ ] **Step 4: Verify + commit**

Run: `grep -nP '=[\x{201C}\x{201D}]' docs/recipes.html` → empty; `grep -c 'launchpad add' config/agents/AGENTS.md docs/recipes.html README.md`.
```bash
git add config/agents/AGENTS.md docs/recipes.html README.md
git commit -m "docs(addon-10): AGENTS.md provisioning recipes + recipes/README notes"
```

---

### Task 7: VM integration probe

**Files:** Create `dogfood/remote-addon10.sh`.

- [ ] **Step 1: Write the probe**

```bash
#!/usr/bin/env bash
# dogfood/remote-addon10.sh — VM integration probe for Add-on 10 (provisioning
# wizards). Scaffolds into a throwaway Next.js project with MOCK supabase/stripe/
# vercel CLIs (no real accounts), asserts files + keys are written idempotently,
# and typechecks the generated code with `tsc --noEmit`.
set -o pipefail
HERE="$(cd "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
ROOT="$(cd "$HERE/.." >/dev/null 2>&1 && pwd)"
export LAUNCHPAD_NONINTERACTIVE=1 LAUNCHPAD_SKIP_CLONE=1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"

echo "##### BOOTSTRAP #####"; /bin/bash "$ROOT/bootstrap.sh"
echo "##### LEAN INSTALL (00,01,10-web) #####"
for m in 00-foundation 01-shell 10-web; do echo "-- $m --"; /bin/bash "$ROOT/modules/$m.sh"; done
command -v fnm >/dev/null 2>&1 && eval "$(fnm env 2>/dev/null)" && fnm use default >/dev/null 2>&1

# Mock CLIs (login/deploy need accounts; the npm packages are installed for real).
MOCKBIN="$(mktemp -d)"
for c in supabase stripe vercel; do printf '#!/bin/sh\necho "mock %s $*"\nexit 0\n' "$c" > "$MOCKBIN/$c"; chmod +x "$MOCKBIN/$c"; done
export PATH="$MOCKBIN:$PATH"

echo "##### PROBES #####"
( cd "$ROOT" && bash tests/test-provision.sh >/tmp/tp.out 2>&1 ) && echo "PROBE:provision_unit=PASS" || { echo "PROBE:provision_unit=FAIL"; tail -5 /tmp/tp.out; }

# A throwaway Next.js project to scaffold into
APP="$(mktemp -d)/app1"
npx --yes create-next-app@latest "$APP" --ts --app --tailwind --no-linter --no-src-dir --no-agents-md --import-alias "@/*" --use-npm --yes >/tmp/cna.out 2>&1 && echo "PROBE:next_app=PASS" || { echo "PROBE:next_app=FAIL"; tail -15 /tmp/cna.out; echo "##### ADDON10 PROBE DONE #####"; exit 0; }

# Supabase wizard: scaffolds + writes keys; idempotent re-run
( cd "$APP" && bash "$ROOT/scripts/add-supabase.sh" --url 'https://abcd.supabase.co' --anon-key 'anon123' >/dev/null 2>&1
  test -f lib/supabase/client.ts && test -f lib/supabase/server.ts && test -f middleware.ts && test -f app/login/page.tsx && test -f app/dashboard/page.tsx \
  && grep -q '^NEXT_PUBLIC_SUPABASE_URL=https://abcd.supabase.co' .env.local && grep -q '^NEXT_PUBLIC_SUPABASE_ANON_KEY=anon123' .env.local ) \
  && echo "PROBE:supabase_scaffold=PASS" || echo "PROBE:supabase_scaffold=FAIL"
( cd "$APP" && printf 'EDITED' > lib/supabase/client.ts && bash "$ROOT/scripts/add-supabase.sh" >/dev/null 2>&1 && [ "$(cat lib/supabase/client.ts)" = EDITED ] ) \
  && echo "PROBE:supabase_idempotent=PASS" || echo "PROBE:supabase_idempotent=FAIL"

# Stripe wizard: scaffolds; rejects a live secret; accepts test keys
( cd "$APP" && bash "$ROOT/scripts/add-stripe.sh" --secret 'sk_test_abc' --pub 'pk_test_abc' >/dev/null 2>&1
  test -f app/pricing/page.tsx && test -f app/api/checkout/route.ts && test -f app/api/webhook/route.ts && test -f app/premium/page.tsx \
  && grep -q '^STRIPE_SECRET_KEY=sk_test_abc' .env.local ) && echo "PROBE:stripe_scaffold=PASS" || echo "PROBE:stripe_scaffold=FAIL"
( cd "$APP" && bash "$ROOT/scripts/add-stripe.sh" --secret 'sk_live_NOPE' >/dev/null 2>&1; ! grep -q 'sk_live_' .env.local ) \
  && echo "PROBE:stripe_rejects_live=PASS" || echo "PROBE:stripe_rejects_live=FAIL"

# Vercel wizard: runs with the mock CLI, pushes keys, "deploys"
( cd "$APP" && bash "$ROOT/scripts/add-vercel.sh" >/tmp/vc.out 2>&1 && grep -qi 'deploy' /tmp/vc.out ) \
  && echo "PROBE:vercel_run=PASS" || echo "PROBE:vercel_run=FAIL"

# The generated TypeScript must typecheck (proves the scaffolds compile against the real SDKs)
( cd "$APP" && npx --yes tsc --noEmit >/tmp/tsc.out 2>&1 ) && echo "PROBE:tsc_compiles=PASS" || { echo "PROBE:tsc_compiles=FAIL"; tail -20 /tmp/tsc.out; }

# Stripe CLI really installed by 10-web — check brew, NOT `command -v stripe`
# (the MOCKBIN mock shadows `stripe` on PATH, so command -v would false-pass).
brew list stripe >/dev/null 2>&1 && echo "PROBE:stripe_cli=PASS" || echo "PROBE:stripe_cli=FAIL"
bash "$ROOT/scripts/launchpad" add 2>&1 | grep -qi 'supabase' && echo "PROBE:dispatch=PASS" || echo "PROBE:dispatch=FAIL"

echo "##### ADDON10 PROBE DONE #####"
```

> Note: `MOCKBIN` deliberately shadows the real `supabase`/`stripe`/`vercel` so the wizards' interactive *login/deploy* calls succeed without accounts. Because of that shadow, the `stripe_cli` probe verifies the **real** install via `brew list stripe` (not `command -v`), and the npm packages (`@supabase/ssr`, `stripe`) are installed for real so `tsc` can typecheck the scaffolds.

- [ ] **Step 2: Static checks (do NOT run on host)**

Run: `bash -n dogfood/remote-addon10.sh && shellcheck dogfood/remote-addon10.sh` (info-level only). Do NOT execute it (it bootstraps + installs + runs create-next-app).

- [ ] **Step 3: Commit**

```bash
chmod +x dogfood/remote-addon10.sh
git add dogfood/remote-addon10.sh
git commit -m "test(addon-10): VM probe — scaffold into a Next app w/ mock CLIs + tsc --noEmit"
```

---

### Task 8: Final validation (controller)

- [ ] **Step 1:** Host unit suites: `bash tests/test-provision.sh` + the other suites (`test-secrets/status/signin/sentry/doctorfix/spend`) — all PASS.
- [ ] **Step 2:** `shellcheck -S warning scripts/provision-common.sh scripts/add-supabase.sh scripts/add-stripe.sh scripts/add-vercel.sh scripts/launchpad lib/doctor.sh modules/10-web.sh` + `shellcheck dogfood/remote-addon10.sh` (info-level ok).
- [ ] **Step 3:** `grep -nP '=[\x{2018}\x{2019}\x{201C}\x{201D}]' docs/*.html` — empty.
- [ ] **Step 4:** VM probe: `TART_VM=launchpad-addon10 bash dogfood/vm-probes.sh dogfood/remote-addon10.sh` — every `PROBE:*=PASS` (especially `tsc_compiles`), exit 0.
- [ ] **Step 5:** Final code review over `main..HEAD`; on READY TO MERGE, superpowers:finishing-a-development-branch (squash-merge to `main`, push, verify Pages).

---

## Self-Review

**1. Spec coverage:** `launchpad add supabase/stripe/vercel` wrappers → Tasks 2–4; shared helpers → Task 1; dispatcher + Stripe-CLI install + chmod + doctor → Task 5; AGENTS.md recipes + docs → Task 6; unit tests (mock CLIs) + VM probe + `tsc` compile → Tasks 1,7; scaffold-if-absent / .env.local-or-1Password / test-mode-only / Next-project guard → in the wrappers; build-time API verification → done in the header. ✓

**2. Placeholder scan:** Every code step has complete code (verified APIs); tests have real assertions; no TBD/TODO. The only intentional "fill later" is in the scaffolded app code's comments (e.g. "persist paid state") — that's guidance inside generated user code, not a plan gap.

**3. Type/name consistency:** `is_next_project`, `supabase_url_valid`, `stripe_test_secret_valid`, `stripe_pub_valid`, `env_upsert`, `env_keys`, `scaffold_if_absent`, `_op_tip` defined once in `provision-common.sh` (Task 1) and used by the wrappers (Tasks 2–4) + tests (Task 1) + probe (Task 7). `.env.local` key names match the web template's `.env.example` (`NEXT_PUBLIC_SUPABASE_URL/_ANON_KEY`, `STRIPE_SECRET_KEY`, `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`). The `@/lib/supabase/*` import paths match the scaffold file paths under `lib/supabase/` (with `@/*`→root, `--no-src-dir`).

**Residual risks (documented):** (a) the scaffolds are real Next 16 / `@supabase/ssr` / `stripe` code — the `tsc --noEmit` probe is the compile gate; if an API drifted, that probe fails loudly (fix the heredoc). (b) The interactive `supabase/stripe/vercel login` + real deploy can't be VM-tested (sign-in-gated; covered by the agent recipe + mock CLIs for the wrapper's call path). (c) `add-vercel` pushes every `.env.local` key to Vercel production — intended (the app's config), and the keys are the user's own.
