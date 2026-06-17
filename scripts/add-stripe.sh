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
