import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { PortalLayout } from '@/layouts/PortalLayout'
import { AdminPayments } from './Finance'
import { AdminPlans, draftToInput, planToDraft, validatePlan } from './Catalog'
import { mockApi, plan, renderWith, staff } from '@/test/utils'
import type { AdminPayment } from '@/api/types'

const admin = <Routes><Route path="/admin/*" element={<PortalLayout kind="admin" />}><Route index element={<p>overview</p>} /><Route path="payments" element={<AdminPayments />} /><Route path="plans" element={<AdminPlans />} /></Route></Routes>
const navLinks = () => within(screen.getAllByRole('navigation', { name: 'Admin navigation' })[0]).getAllByRole('link').map((a) => a.textContent)

describe('admin permission hiding (UI convenience; API is authoritative)', () => {
  it('support agents see only the sections their permissions allow', () => {
    mockApi({ 'GET /notifications/unread-count': { data: { count: 0 } } })
    renderWith(admin, { route: '/admin', user: staff(['dashboard.view', 'users.view', 'reports.manage', 'payments.view', 'subscriptions.view']) })
    const links = navLinks()
    expect(links).toEqual(expect.arrayContaining(['Overview', 'Users', 'Reports & disputes', 'Payments & refunds', 'Subscriptions', 'Security & permissions']))
    for (const hidden of ['Subscription plans', 'Platform settings', 'Audit logs', 'Categories & breeds', 'Seller verification', 'Listing moderation']) expect(links).not.toContain(hidden)
  })
  it('super admin sees everything', () => {
    mockApi({ 'GET /notifications/unread-count': { data: { count: 0 } } })
    const all = ['dashboard.view', 'users.view', 'users.manage', 'roles.manage', 'sellers.verify', 'listings.moderate', 'catalog.manage', 'plans.manage', 'subscriptions.view', 'payments.view', 'refunds.create', 'reports.manage', 'content.manage', 'settings.manage', 'audit.view']
    renderWith(admin, { route: '/admin', user: staff(all, { roles: ['super_admin'] }) })
    expect(navLinks()).toHaveLength(16)
  })
})

const payment: AdminPayment = { id: 'bed16a1c-06d4-461f-bd7f-5d5ec31625a7', status: 'succeeded', plan: { id: 'pl', name: 'Seller Pro', audience: 'seller' }, subtotal_minor: 149900, tax_minor: 26982, amount_minor: 176882, refunded_minor: 0, currency: 'INR', provider: 'testmode', created_at: '2026-10-18T00:00:00Z', user_email: 'seller@x.test', user_name: 'Sally', refunds: [] }
const payRoutes = () => ({ 'GET /admin/payments': { data: [payment], meta: { page: 1, per_page: 20, total: 1, total_pages: 1 } }, [`GET /admin/payments/${payment.id}`]: { data: payment } })

describe('refund controls', () => {
  it('are hidden without refunds.create (support role)', async () => {
    mockApi(payRoutes())
    renderWith(<AdminPayments />, { user: staff(['payments.view']) })
    await userEvent.click((await screen.findAllByText('seller@x.test'))[0])
    expect(await screen.findByText(/Your role cannot issue refunds/)).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Issue refund' })).not.toBeInTheDocument()
  })
  it('finance can refund: validates the amount, sends an idempotency key, and cannot exceed the balance', async () => {
    const api = mockApi({ ...payRoutes(), [`POST /admin/payments/${payment.id}/refunds`]: { status: 201, data: { id: 'r1', payment_id: payment.id, amount_minor: 10000, reason: 'x', status: 'succeeded', created_at: '' } } })
    renderWith(<AdminPayments />, { user: staff(['payments.view', 'refunds.create'], { roles: ['finance'] }) })
    await userEvent.click((await screen.findAllByText('seller@x.test'))[0])
    await userEvent.click(await screen.findByRole('button', { name: 'Issue refund' }))
    const amount = await screen.findByLabelText(/Amount/)
    await userEvent.clear(amount); await userEvent.type(amount, '5000')
    await userEvent.type(screen.getByLabelText(/Reason/), 'Duplicate purchase')
    await userEvent.click(screen.getByRole('button', { name: 'Confirm refund' }))
    expect(await screen.findByText(/Cannot exceed the unrefunded balance/)).toBeInTheDocument()
    expect(api.find('POST', `/admin/payments/${payment.id}/refunds`)).toHaveLength(0)
    await userEvent.clear(amount); await userEvent.type(amount, '100.50')
    await userEvent.click(screen.getByRole('button', { name: 'Confirm refund' }))
    await screen.findByText('Payments & refunds')
    const body = api.find('POST', `/admin/payments/${payment.id}/refunds`)[0].body as { amount_minor: number; idempotency_key: string; reason: string }
    expect(body.amount_minor).toBe(10050)
    expect(body.idempotency_key.length).toBeGreaterThan(16)
    expect(body.reason).toBe('Duplicate purchase')
  })
})

describe('plan configuration', () => {
  it('round-trips a plan through the editor model and converts ₹/% to minor units / bps', () => {
    const d = planToDraft(plan({ promo_price_minor: 29900, tax_rate_bps: 1800, entitlements: { contact_unlocks: null, enquiries: 20 } }))
    expect(d.unlock_unl).toBe(true)
    const input = draftToInput({ ...d, price: '599.50', tax_pct: '12.5' })
    expect(input).toMatchObject({ price_minor: 59950, tax_rate_bps: 1250, promo_price_minor: 29900, entitlements: { contact_unlocks: null, enquiries: 20 } })
  })
  it('validates codes, prices and promotions', () => {
    const d = planToDraft(plan())
    expect(validatePlan(d)).toBeNull()
    expect(validatePlan({ ...d, code: 'Bad Code' })).toMatch(/Code/)
    expect(validatePlan({ ...d, price: 'abc' })).toMatch(/price/i)
    expect(validatePlan({ ...d, promo_price: '999' })).toMatch(/lower/)
  })
})
