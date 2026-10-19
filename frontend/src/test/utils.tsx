import type { ReactElement } from 'react'
import { render } from '@testing-library/react'
import { MemoryRouter, useLocation } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { vi } from 'vitest'
import { AuthProvider } from '@/auth/AuthContext'
import { ToastProvider } from '@/components/ui/Toast'
import { LocationProvider } from '@/lib/location'
import { ThemeProvider } from '@/lib/theme'
import type { ListingDetail, ListingCard, Meta, Plan, User } from '@/api/types'

export interface MockReq { url: URL; method: string; body: unknown; path: string }
export type MockRes = { status?: number; data?: unknown; meta?: Meta; error?: { code: string; message: string; details?: { field: string; message: string }[]; extra?: Record<string, unknown> } }
type Handler = MockRes | ((r: MockReq) => MockRes | Promise<MockRes>)

/** Replace global fetch with a router keyed by "METHOD /path" (path relative to /api/v1). */
export function mockApi(routes: Record<string, Handler>) {
  const calls: MockReq[] = []
  const fn = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input.toString(), 'http://localhost')
    const method = (init?.method ?? 'GET').toUpperCase()
    const path = url.pathname.replace(/^\/api\/v1/, '')
    let body: unknown
    if (init?.body && typeof init.body === 'string') { try { body = JSON.parse(init.body) } catch { body = init.body } }
    const req = { url, method, body, path }
    calls.push(req)
    const h = routes[`${method} ${path}`]
    if (!h) return new Response(JSON.stringify({ error: { code: 'not_found', message: `no mock for ${method} ${path}`, request_id: 't' } }), { status: 404 })
    const r = typeof h === 'function' ? await h(req) : h
    const status = r.status ?? (r.error ? 400 : 200)
    if (status === 204) return new Response(null, { status })
    return new Response(JSON.stringify(r.error ? { error: { request_id: 't', ...r.error } } : { data: r.data, meta: r.meta }), { status, headers: { 'Content-Type': 'application/json' } })
  })
  vi.stubGlobal('fetch', fn)
  return { fn, calls, find: (method: string, path: string) => calls.filter((c) => c.method === method && c.path === path) }
}

export const user = (o: Partial<User> = {}): User => ({
  id: 'u1', email: 'buyer@example.com', name: 'Asha Buyer', account_type: 'buyer', roles: ['buyer'], email_verified: true, mfa_enabled: false, mfa_verified: false, created_at: '2026-01-01T00:00:00Z', ...o,
})
export const staff = (perms: string[], o: Partial<User> = {}): User => user({ id: 's1', email: 'staff@petora.test', name: 'Sam Staff', account_type: 'staff', roles: ['support'], permissions: perms, mfa_enabled: true, mfa_verified: true, ...o })

export const seller = { id: 'sl1', slug: 'happy-paws', display_name: 'Happy Paws', seller_type: 'business' as const, verified: true, city: 'Pune', state: 'MH', logo_url: null }
export const card = (o: Partial<ListingCard> = {}): ListingCard => ({
  id: 'p1', slug: 'labrador-puppy', title: 'Labrador puppy', listing_type: 'sale', price_minor: 1500000, currency: 'INR', age_months: 3, gender: 'male', city: 'Pune', state: 'MH',
  category: { id: 'c1', slug: 'dogs', name: 'Dogs' }, breed: { id: 'b1', slug: 'labrador', name: 'Labrador' }, cover: null, seller, availability: 'available', vaccination_status: 'complete',
  featured: false, is_favourite: false, published_at: '2026-10-01T00:00:00Z', ...o,
})
export const detail = (o: Partial<ListingDetail> = {}): ListingDetail => ({
  ...card(), description: 'Friendly and playful.', colour: 'Golden', vaccination_notes: 'First two shots done', health_notes: '', dewormed: true, microchipped: false, images: [], attributes: {}, views_count: 10,
  seller_profile: { ...seller, bio: 'Kennel', member_since: '2025-01-01T00:00:00Z', active_listings: 3, verified_at: '2026-01-01T00:00:00Z' }, contact: { unlocked: false, requires_membership: true },
  disclaimer: 'Health details are declared by the seller and not verified by PETORA.', ...o,
})
export const plan = (o: Partial<Plan> = {}): Plan => ({
  id: 'pl1', code: 'buyer-monthly', audience: 'buyer', name: 'Buyer Monthly', description: 'Unlock contacts', price_minor: 49900, effective_price_minor: 49900, tax_rate_bps: 1800, tax_minor: 8982, total_minor: 58882, currency: 'INR',
  billing_interval: 'month', interval_count: 1, trial_days: 0, grace_days: 3, renewal_window_days: 7, auto_renew: false, cancellation_policy: 'end_of_period', refund_window_days: 0, refund_policy: '', is_active: true, sort_order: 1,
  features: ['Priority support'], entitlements: { contact_unlocks: 10, enquiries: 20 }, ...o,
})

function Loc() { const l = useLocation(); return <div data-testid="loc">{l.pathname + l.search}</div> }

export function renderWith(ui: ReactElement, opts: { route?: string; user?: User | null } = {}) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false, staleTime: 0, gcTime: 0 }, mutations: { retry: false } } })
  return render(
    <QueryClientProvider client={qc}>
      <ThemeProvider><LocationProvider><ToastProvider>
        <MemoryRouter initialEntries={[opts.route ?? '/']}>
          <AuthProvider initialUser={opts.user ?? null}>{ui}<Loc /></AuthProvider>
        </MemoryRouter>
      </ToastProvider></LocationProvider></ThemeProvider>
    </QueryClientProvider>,
  )
}
