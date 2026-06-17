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
