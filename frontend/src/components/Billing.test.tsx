import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { axe } from 'vitest-axe'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { CheckoutDialog, PlanCard, PlanPicker } from './Billing'
import { mockApi, plan, renderWith, user } from '@/test/utils'
import type { Payment } from '@/api/types'

const pay = (status: Payment['status'], extra: Partial<Payment> = {}): Payment => ({ id: 'pay1', status, plan: { id: 'pl1', name: 'Buyer Monthly', audience: 'buyer' }, subtotal_minor: 49900, tax_minor: 8982, amount_minor: 58882, refunded_minor: 0, currency: 'INR', provider: 'testmode', created_at: '2026-10-18T00:00:00Z', ...extra })
const checkout = { payment: pay('created'), provider: 'testmode', provider_order_id: 'order_test_1', amount_minor: 58882, currency: 'INR', test_mode: true }
const cfg = { data: { brand_name: 'PETORA', currency: 'INR', maintenance: false, payment_provider: 'testmode', max_images_per_listing: 8, max_image_mb: 8 } }
const open = () => renderWith(<CheckoutDialog plan={plan()} open onOpenChange={() => {}} />, { user: user() })

afterEach(() => { vi.useRealTimers() })

describe('checkout UI', () => {
  it('review step shows the server-computed total, tax and a TEST MODE banner', async () => {
    mockApi({ 'GET /config': cfg })
    open()
    expect(await screen.findByText(/TEST MODE – no real charge/)).toBeInTheDocument()
    expect(screen.getByText('Total today')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Pay ₹588\.82/ })).toBeInTheDocument()
    expect(screen.getByText(/does not guarantee/i)).toBeInTheDocument()
  })

  it('test mode: simulate success → polls server state → shows confirmed only when succeeded', async () => {
    let status: Payment['status'] = 'pending'
    const api = mockApi({
      'GET /config': cfg,
      'POST /subscriptions/checkout': { status: 201, data: checkout },
      'POST /payments/pay1/test-complete': () => { status = 'succeeded'; return { data: pay('succeeded') } },
      'GET /payments/pay1': () => ({ data: pay(status) }),
    })
    open()
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    const body = api.find('POST', '/subscriptions/checkout')[0].body as { plan_id: string; idempotency_key: string }
    expect(body.plan_id).toBe('pl1')
    expect(body.idempotency_key.length).toBeGreaterThanOrEqual(16)
    expect(screen.queryByText('Payment confirmed')).not.toBeInTheDocument()
    await userEvent.click(await screen.findByRole('button', { name: /Simulate success/ }))
    expect(await screen.findByText('You’re all set')).toBeInTheDocument()
    expect(api.find('POST', '/payments/pay1/test-complete')[0].body).toEqual({ outcome: 'success' })
  })

  it('test mode: simulated failure shows a failed state with retry using a fresh idempotency key', async () => {
    const api = mockApi({
      'GET /config': cfg,
      'POST /subscriptions/checkout': { status: 201, data: checkout },
      'POST /payments/pay1/test-complete': { data: pay('failed') },
      'GET /payments/pay1': { data: pay('failed', { failure_reason: 'Simulated failure' }) },
    })
    open()
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    await userEvent.click(await screen.findByRole('button', { name: /Simulate failure/ }))
    expect(await screen.findByText('Payment not completed')).toBeInTheDocument()
    expect(screen.getByText('Simulated failure')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Try again' }))
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    const keys = api.find('POST', '/subscriptions/checkout').map((c) => (c.body as { idempotency_key: string }).idempotency_key)
    expect(keys).toHaveLength(2)
    expect(keys[0]).not.toBe(keys[1])
  })

  it('never claims success while the server still reports pending: shows "still confirming" after the poll window', async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true })
    mockApi({
      'GET /config': cfg,
      'POST /subscriptions/checkout': { status: 201, data: checkout },
      'POST /payments/pay1/test-complete': { data: pay('pending') },
      'GET /payments/pay1': { data: pay('pending') },
    })
    open()
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    await userEvent.click(await screen.findByRole('button', { name: /Simulate success/ }))
    await screen.findByText('Confirming your payment…')
    await act(async () => { await vi.advanceTimersByTimeAsync(70_000) })
    await waitFor(() => expect(screen.getByText('We’re still confirming your payment')).toBeInTheDocument())
    expect(screen.queryByText('You’re all set')).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Check again' })).toBeInTheDocument()
  })

  it('surfaces already-subscribed conflicts from checkout without leaving the review step', async () => {
    mockApi({ 'GET /config': cfg, 'POST /subscriptions/checkout': { status: 409, error: { code: 'conflict', message: 'You already have an active plan' } } })
    open()
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    expect(await screen.findByText('You already have an active plan')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Pay ₹588/ })).toBeInTheDocument()
  })
})

describe('plan card', () => {
  it('shows promo pricing, tax and entitlements from the API only', async () => {
    const { container } = renderWith(<PlanCard plan={plan({ promo_price_minor: 29900, effective_price_minor: 29900 })} />)
    expect(screen.getByText('₹299')).toBeInTheDocument()
    expect(screen.getByText('₹499')).toBeInTheDocument()
    expect(screen.getByText('10 seller contact unlocks')).toBeInTheDocument()
    expect(screen.getByText('Offer')).toBeInTheDocument()
    expect(await axe(container)).toHaveNoViolations()
  })
  it('renders unlimited entitlements for null limits', () => {
    renderWith(<PlanCard plan={plan({ entitlements: { contact_unlocks: null, enquiries: null } })} />)
    expect(screen.getByText('Unlimited seller contact unlocks')).toBeInTheDocument()
  })
})

describe('plan picker', () => {
  it('shows the payment confirmation first and only then runs the follow-up action', async () => {
    let status: Payment['status'] = 'pending'
    mockApi({
      'GET /config': cfg, 'GET /subscription-plans': { data: [plan()] }, 'POST /subscriptions/checkout': { status: 201, data: checkout },
      'POST /payments/pay1/test-complete': () => { status = 'succeeded'; return { data: pay('succeeded') } }, 'GET /payments/pay1': () => ({ data: pay(status) }),
    })
    const done = vi.fn()
    renderWith(<PlanPicker audience="buyer" open onOpenChange={() => {}} onPurchased={done} />, { user: user() })
    await userEvent.click(await screen.findByRole('button', { name: /Choose Buyer Monthly/ }))
    await userEvent.click(await screen.findByRole('button', { name: /Pay ₹588/ }))
    await userEvent.click(await screen.findByRole('button', { name: /Simulate success/ }))
    expect(await screen.findByText('You’re all set')).toBeInTheDocument()
    expect(done).not.toHaveBeenCalled()
    await userEvent.click(screen.getByRole('button', { name: 'Continue' }))
    await waitFor(() => expect(done).toHaveBeenCalledTimes(1))
  })

  it('renders a trust note explaining why contact details require a small fee', async () => {
    mockApi({ 'GET /config': cfg, 'GET /subscription-plans': { data: [plan()] } })
    renderWith(<PlanPicker audience="buyer" open onOpenChange={() => {}} />, { user: user() })
    expect(await screen.findByText(/Why is there a small fee to unlock seller contacts\?/i)).toBeInTheDocument()
    expect(screen.getByText(/Protects Pets & Prevents Scams/i)).toBeInTheDocument()
    expect(screen.getByText(/Serious Adopters Only/i)).toBeInTheDocument()
    expect(screen.getByText(/Direct, Zero Brokerage/i)).toBeInTheDocument()
  })
})
