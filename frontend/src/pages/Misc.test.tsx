import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { MemoryRouter, Route, Routes } from 'react-router-dom'
import { axe } from 'vitest-axe'
import { afterEach, describe, expect, it, vi } from 'vitest'
import Home from '@/pages/public/Home'
import Pricing from '@/pages/public/Pricing'
import { FaqPage, SafetyPage } from '@/pages/public/Content'
import { api, ApiError, buildQuery, request } from '@/api/client'
import { Markdown } from '@/lib/markdown'
import { formatAge, formatMoney, toMinor } from '@/lib/utils'
import { card, mockApi, plan, renderWith, user } from '@/test/utils'

const cats = [{ id: 'c1', slug: 'dogs', name: 'Dogs', icon: 'dog', description: '', sort_order: 1, is_active: true, requires_verified_seller: false, listing_count: 4, breeds: [] }]
const cfg = { data: { brand_name: 'PETORA', currency: 'INR', maintenance: false, payment_provider: 'testmode', max_images_per_listing: 8, max_image_mb: 8 } }
const list = { data: [card()], meta: { page: 1, per_page: 8, total: 1, total_pages: 1 } }

afterEach(() => { document.cookie = 'petora_csrf=; Max-Age=0' })

describe('public pages', () => {
  it('home renders every required section and has no axe violations', async () => {
    mockApi({ 'GET /categories': { data: cats }, 'GET /pets': list, 'GET /sellers': { data: [], meta: { page: 1, per_page: 6, total: 0, total_pages: 0 } }, 'GET /content/home': { status: 404, error: { code: 'not_found', message: 'x' } }, 'GET /content/faq': { data: { items: [{ q: 'Q1?', a: 'A1' }] } }, 'GET /config': cfg })
    const { container } = renderWith(<Home />)
    for (const h of ['Browse by category', 'Featured pets', 'Recently listed', 'Pets near you', 'Verified sellers', 'How PETORA works', 'Safety & welfare first', 'Frequently asked questions']) {
      expect(await screen.findByRole('heading', { name: h })).toBeInTheDocument()
    }
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Find your pet, responsibly.')
    expect(await screen.findByText('Q1?')).toBeInTheDocument()
    expect(await axe(container)).toHaveNoViolations()
  })
  it('pricing shows API plans, offers sign-up to anonymous visitors, and has no axe violations', async () => {
    mockApi({ 'GET /subscription-plans': { data: [plan(), plan({ id: 'pl2', name: 'Buyer Plus', sort_order: 2 })] }, 'GET /config': cfg })
    const { container } = renderWith(<Pricing />, { route: '/pricing' })
    expect(await screen.findByText('Buyer Monthly')).toBeInTheDocument()
    expect(screen.getAllByRole('button', { name: 'Sign up to choose' }).length).toBe(2)
    expect(await axe(container)).toHaveNoViolations()
  })
  it('seller plans warn that purchase does not verify the account', async () => {
    mockApi({ 'GET /subscription-plans': { data: [plan({ audience: 'seller', name: 'Seller Pro' })] }, 'GET /subscriptions/current': { data: { audience: 'seller', active: false, subscription: null, entitlements: {} } }, 'GET /config': cfg })
    renderWith(<Pricing />, { route: '/pricing', user: user({ account_type: 'seller', roles: ['seller'] }) })
    await userEvent.click(await screen.findByRole('button', { name: 'For sellers' }))
    expect(await screen.findByText('Verification is separate')).toBeInTheDocument()
    expect(await screen.findByText('Seller Pro')).toBeInTheDocument()
  })
  it('safety and FAQ pages fall back gracefully when content is unpublished and are accessible', async () => {
    mockApi({ 'GET /legal/safety': { status: 404, error: { code: 'not_found', message: 'x' } }, 'GET /content/faq': { status: 404, error: { code: 'not_found', message: 'x' } } })
    const a = renderWith(<SafetyPage />)
    expect(await screen.findByText('Meet in person')).toBeInTheDocument()
    expect(await axe(a.container)).toHaveNoViolations()
    a.unmount()
    const b = renderWith(<FaqPage />)
    expect(await screen.findByText('Is browsing free?')).toBeInTheDocument()
    expect(await axe(b.container)).toHaveNoViolations()
  })
})

describe('markdown renderer', () => {
  it('renders structure and never injects HTML or javascript: links', () => {
    const { container } = render(<MemoryRouter><Markdown source={'# Title\n\nHello **bold** <script>alert(1)</script> [bad](javascript:alert(1)) [ok](https://example.com)\n\n- one\n- two'} /></MemoryRouter>)
    expect(container.querySelector('script')).toBeNull()
    expect(container.querySelector('h2')).toHaveTextContent('Title')
    expect(container.querySelectorAll('li')).toHaveLength(2)
    expect(container.querySelector('a[href^="javascript"]')).toBeNull()
    expect(container.querySelector('a[href="https://example.com"]')).not.toBeNull()
  })
})

describe('formatting helpers', () => {
  it('formats money from integer minor units and parses rupees without float error', () => {
    expect(formatMoney(1500000)).toBe('₹15,000')
    expect(formatMoney(15000000)).toBe('₹1,50,000')
    expect(formatMoney(1999950)).toBe('₹19,999.50')
    expect(formatMoney(0, 'INR', { free: true })).toBe('Free')
    expect(toMinor('19,999.50')).toBe(1999950)
    expect(toMinor('0.1') + toMinor('0.2')).toBe(30)
    expect(toMinor('₹ 12')).toBe(1200)
  })
  it('formats ages', () => { expect(formatAge(1)).toBe('1 month'); expect(formatAge(14)).toBe('14 months'); expect(formatAge(30)).toBe('2 yr 6 mo'); expect(formatAge(null)).toBe('Age not stated') })
})

describe('api client', () => {
  it('sends the CSRF header on unsafe methods only, with credentials', async () => {
    document.cookie = 'petora_csrf=tok123'
    const m = mockApi({ 'GET /x': { data: 1 }, 'POST /x': { data: 1 } })
    await api.get('/x'); await api.post('/x', { a: 1 })
    const [get, post] = m.fn.mock.calls
    expect((get[1]!.headers as Record<string, string>)['X-CSRF-Token']).toBeUndefined()
    expect((post[1]!.headers as Record<string, string>)['X-CSRF-Token']).toBe('tok123')
    expect(post[1]!.credentials).toBe('include')
  })
  it('refreshes once (single-flight) on 401 then retries, and gives up when refresh fails', async () => {
    document.cookie = 'petora_csrf=tok'
    let calls = 0
    const m = mockApi({ 'GET /me': () => (calls++ < 2 ? { status: 401, error: { code: 'unauthorized', message: 'expired' } } : { data: { id: 'u' } }), 'POST /auth/refresh': { status: 200, data: {} } })
    const [a, b] = await Promise.all([request('GET', '/me'), request('GET', '/me')])
    expect(a.data).toEqual({ id: 'u' }); expect(b.data).toEqual({ id: 'u' })
    expect(m.find('POST', '/auth/refresh')).toHaveLength(1)
    await new Promise((r) => setTimeout(r, 10)) // let the single-flight window close
    const lost = vi.fn()
    const { onAuthLost } = await import('@/api/client')
    onAuthLost(lost)
    mockApi({ 'GET /me': { status: 401, error: { code: 'unauthorized', message: 'expired' } }, 'POST /auth/refresh': { status: 401, error: { code: 'unauthorized', message: 'expired' } } })
    await expect(request('GET', '/me')).rejects.toBeInstanceOf(ApiError)
    expect(lost).toHaveBeenCalled()
    onAuthLost(null)
  })
  it('does not try to refresh failed logins and maps error envelopes', async () => {
    document.cookie = 'petora_csrf=tok'
    const m = mockApi({ 'POST /auth/login': { status: 401, error: { code: 'unauthorized', message: 'Incorrect email or password', details: [{ field: 'email', message: 'x' }] } } })
    await expect(api.post('/auth/login', {})).rejects.toMatchObject({ status: 401, code: 'unauthorized', message: 'Incorrect email or password', requestId: 't' })
    expect(m.find('POST', '/auth/refresh')).toHaveLength(0)
  })
  it('builds query strings without empty values', () => {
    expect(buildQuery({ a: 1, b: '', c: undefined, d: false, e: true, f: 'x y' })).toBe('?a=1&e=true&f=x+y')
  })
  it('never stores tokens in web storage', async () => {
    mockApi({ 'POST /auth/login': { data: { user: user(), access_token: 'SECRET' } } })
    await api.post('/auth/login', {})
    expect(JSON.stringify({ ...localStorage })).not.toMatch(/SECRET|token/i)
    expect(JSON.stringify({ ...sessionStorage })).not.toMatch(/SECRET|token/i)
  })
})

// keep Routes/Route imports used for future route tests
void [Routes, Route]
