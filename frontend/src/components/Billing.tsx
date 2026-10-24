import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Check, CheckCircle2, Clock, FlaskConical, ShieldCheck, XCircle } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { usePlans, useConfig } from '@/api/hooks'
import { useAuth } from '@/auth/AuthContext'
import type { Checkout, Payment, Plan } from '@/api/types'
import { cn, formatDate, formatMoney, uuid } from '@/lib/utils'
import { Button } from './ui/Button'
import { Dialog } from './ui/Dialog'
import { Alert, Badge, ErrorState, Skeleton } from './ui/Feedback'
import { Spinner } from './ui/Spinner'

const intervalLabel = (p: Plan) => {
  const n = p.interval_count
  const unit = { month: 'month', quarter: 'quarter', year: 'year' }[p.billing_interval]
  return n === 1 ? `/${unit}` : `/${n} ${unit}s`
}
const lim = (v: number | null | undefined, one: string, plural?: string) =>
  (v == null ? `Unlimited ${plural ?? `${one}s`}` : `${v} ${v === 1 ? one : (plural ?? `${one}s`)}`)

export function entitlementLines(p: Plan): string[] {
  const e = p.entitlements ?? {}
  const out: string[] = []
  if (p.audience === 'seller') {
    out.push(lim(e.listing_limit, 'active listing'))
    if (e.featured_slots) out.push(`${e.featured_slots} featured slot${e.featured_slots === 1 ? '' : 's'}`)
    out.push(e.analytics ? 'Listing analytics included' : 'No analytics')
  } else {
    out.push(lim(e.contact_unlocks, 'seller contact unlock'))
    out.push(lim(e.enquiries, 'enquiry', 'enquiries'))
  }
  return out
}

export function PlanCard({ plan, cta, highlight, current }: { plan: Plan; cta?: ReactNode; highlight?: boolean; current?: boolean }) {
  const promo = plan.promo_price_minor != null && plan.effective_price_minor < plan.price_minor
  const features = Array.from(new Set([
    ...entitlementLines(plan),
    ...(plan.features ?? []).filter((f) => {
      const lower = f.toLowerCase()
      return !lower.includes('contact unlock') && !lower.includes('enquir')
    }),
  ]))
  return (
    <article className={cn('card flex flex-col gap-3 p-4', highlight && 'border-primary-500 ring-1 ring-primary-500')} aria-label={`${plan.name} plan`}>
      <div className="flex items-start justify-between gap-2">
        <div><h2 className="text-lg">{plan.name}</h2>{plan.description && <p className="mt-0.5 text-sm text-muted">{plan.description}</p>}</div>
        {current ? <Badge tone="success">Current</Badge> : promo ? <Badge tone="accent">Offer</Badge> : null}
      </div>
      <div>
        <p className="flex items-baseline gap-1.5">
          <span className="text-3xl font-bold tnum">{formatMoney(plan.effective_price_minor, plan.currency)}</span>
          <span className="text-sm text-muted">{intervalLabel(plan)}</span>
          {promo && <s className="text-sm text-muted tnum">{formatMoney(plan.price_minor, plan.currency)}</s>}
        </p>
        <p className="text-xs text-muted tnum">{plan.tax_rate_bps > 0 ? `+ ${(plan.tax_rate_bps / 100).toString()}% tax · total ${formatMoney(plan.total_minor, plan.currency)}` : 'Taxes included'}{promo && plan.promo_ends_at ? ` · offer ends ${formatDate(plan.promo_ends_at)}` : ''}</p>
      </div>
      <ul className="flex-1 space-y-1.5 text-sm">
        {features.map((f) => (
          <li key={f} className="flex items-start gap-2"><Check className="mt-0.5 h-4 w-4 shrink-0 text-primary-600" aria-hidden />{f}</li>
        ))}
      </ul>
      {cta}
    </article>
  )
}

declare global {
  interface Window { Razorpay?: new (o: Record<string, unknown>) => { open: () => void; on: (e: string, cb: (r: unknown) => void) => void } }
}
let rzpLoading: Promise<void> | null = null
function loadRazorpay(): Promise<void> {
  if (window.Razorpay) return Promise.resolve()
  rzpLoading ??= new Promise<void>((resolve, reject) => {
    const s = document.createElement('script')
    s.src = 'https://checkout.razorpay.com/v1/checkout.js'
    s.async = true
    s.onload = () => resolve()
    s.onerror = () => { rzpLoading = null; reject(new Error('Could not load the payment window. Check your connection and try again.')) }
    document.head.appendChild(s)
  })
  return rzpLoading
}

type Phase = 'review' | 'creating' | 'awaiting' | 'verifying' | 'failed'
const POLL_MS = 2000
const MAX_POLLS = 30 // ≈ 60 s

/** Poll a payment until it reaches a terminal state or we give up (then the UI says "confirming"). */
function usePaymentPoll(paymentId: string | null, enabled: boolean) {
  const [polls, setPolls] = useState(0)
  const [base, setBase] = useState(0)
  const q = useQuery({
    queryKey: ['/payments', paymentId],
    queryFn: () => { setPolls((n) => n + 1); return api.get<Payment>(`/payments/${paymentId}`) },
    enabled: enabled && !!paymentId,
    refetchInterval: (query) => {
      const s = query.state.data?.data.status
      return s && s !== 'created' && s !== 'pending' ? false : polls - base >= MAX_POLLS ? false : POLL_MS
    },
  })
  const payment = q.data?.data
  const pending = !payment || payment.status === 'created' || payment.status === 'pending'
  const timedOut = enabled && pending && polls - base >= MAX_POLLS
  const retry = () => { setBase(polls); void q.refetch() }
  return { payment, timedOut, retry }
}

/**
 * Checkout flow. The client never decides that a payment succeeded: success is shown only when
 * GET /payments/{id} reports `succeeded` (set by server-side verification or a verified webhook).
 * The dialog body is remounted on every open so state and the idempotency key start fresh.
 */
export function CheckoutDialog(props: { plan: Plan | null; open: boolean; onOpenChange: (o: boolean) => void; onSuccess?: (p: Payment) => void }) {
  return props.open && props.plan ? <CheckoutInner {...props} plan={props.plan} /> : null
}

function CheckoutInner({ plan, onOpenChange, onSuccess }: { plan: Plan; onOpenChange: (o: boolean) => void; onSuccess?: (p: Payment) => void }) {
  const qc = useQueryClient()
  const { items: cfg } = useConfig()
  const { user } = useAuth()
  const [phase, setPhase] = useState<Phase>('review')
  const [checkout, setCheckout] = useState<Checkout | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const idem = useRef<string>(uuid())
  const notified = useRef(false)

  const { payment, timedOut, retry } = usePaymentPoll(checkout?.payment.id ?? null, phase === 'verifying')
  // Terminal states come from the server's payment record, never from client callbacks.
  const view: Phase | 'success' | 'confirming' =
    payment?.status === 'succeeded' ? 'success'
      : payment?.status === 'failed' || payment?.status === 'cancelled' ? 'failed'
        : timedOut ? 'confirming' : phase
  const failMsg = payment && (payment.status === 'failed' || payment.status === 'cancelled') ? payment.failure_reason || 'The payment was not completed.' : error

  useEffect(() => {
    if (view !== 'success' || !payment || notified.current) return
    notified.current = true
    qc.invalidateQueries({ predicate: (q) => ['/subscriptions', '/billing', '/me', '/buyer', '/seller', '/pets'].some((p) => typeof q.queryKey[0] === 'string' && (q.queryKey[0] as string).startsWith(p)) })
    onSuccess?.(payment)
  }, [view, payment, onSuccess, qc])

  const verify = useCallback(async (body: Record<string, string>) => {
    if (!checkout) return
    setPhase('verifying')
    try { await api.post<Payment>(`/payments/${checkout.payment.id}/verify`, body) } catch (e) {
      // Ambiguous outcome (network/5xx): keep polling; the webhook may still confirm it.
      if (isApiError(e) && e.status >= 400 && e.status < 500 && e.code !== 'rate_limited') { setPhase('failed'); setError(e.message) }
    }
  }, [checkout])

  const openRazorpay = async (c: Checkout) => {
    await loadRazorpay()
    if (!window.Razorpay) throw new Error('Payment window unavailable.')
    const rz = new window.Razorpay({
      key: c.provider_key_id, order_id: c.provider_order_id, amount: c.amount_minor, currency: c.currency, name: 'PETORA', description: plan.name,
      handler: (r: { razorpay_payment_id: string; razorpay_order_id: string; razorpay_signature: string }) =>
        verify({ provider_payment_id: r.razorpay_payment_id, provider_order_id: r.razorpay_order_id, signature: r.razorpay_signature }),
      prefill: { name: user?.name, email: user?.email, contact: user?.phone ?? undefined },
      notes: { petora_payment_id: c.payment.id },
      theme: { color: '#1E6B44' },
      // Closing the window is not a failure: the order stays open and can be reopened or settled by webhook.
      modal: { ondismiss: () => setPhase('awaiting') },
    })
    rz.on('payment.failed', (r: unknown) => {
      const d = (r as { error?: { description?: string } })?.error?.description
      setPhase('failed'); setError(d || 'The payment failed. You have not been charged for an active plan.')
    })
    rz.open()
  }

  const start = async () => {
    setBusy(true); setError(null); setPhase('creating')
    try {
      const r = await api.post<Checkout>('/subscriptions/checkout', { plan_id: plan.id, idempotency_key: idem.current })
      setCheckout(r.data)
      setPhase('awaiting')
      if (r.data.provider === 'razorpay') await openRazorpay(r.data)
    } catch (e) {
      setPhase(checkout ? 'awaiting' : 'review')
      setError(isApiError(e) ? e.message : (e as Error).message)
    } finally { setBusy(false) }
  }

  const simulate = async (outcome: 'success' | 'failure') => {
    if (!checkout) return
    setBusy(true)
    try { await api.post(`/payments/${checkout.payment.id}/test-complete`, { outcome }); setPhase('verifying') } catch (e) { setError(isApiError(e) ? e.message : 'Test payment failed') } finally { setBusy(false) }
  }

  const tryAgain = () => { idem.current = uuid(); notified.current = false; setCheckout(null); setError(null); setPhase('review') }
  const test = checkout?.test_mode || cfg?.payment_provider === 'testmode'

  return (
    <Dialog open onOpenChange={onOpenChange} title={view === 'success' ? 'Payment confirmed' : 'Checkout'} description={`${plan.name} plan`}
      footer={view === 'review' ? <>
        <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
        <Button variant="accent" loading={busy} onClick={start}>Pay {formatMoney(plan.total_minor, plan.currency)}</Button>
      </> : view === 'failed' ? <><Button variant="outline" onClick={() => onOpenChange(false)}>Close</Button><Button onClick={tryAgain}>Try again</Button></>
        : view === 'success' ? <Button onClick={() => onOpenChange(false)}>Continue</Button> : undefined}>
      {test && <Alert tone="warning" className="mb-3" title="TEST MODE – no real charge">Payments here are simulated. No money moves; invoices are marked TEST.</Alert>}
      {view === 'review' && (
        <div className="space-y-3">
          <dl className="card divide-y divide-line text-sm">
            <Row k="Plan" v={plan.name} />
            <Row k="Price" v={formatMoney(plan.effective_price_minor, plan.currency)} />
            <Row k={`Tax${plan.tax_rate_bps ? ` (${plan.tax_rate_bps / 100}%)` : ''}`} v={formatMoney(plan.tax_minor, plan.currency)} />
            <Row k="Total today" v={<strong>{formatMoney(plan.total_minor, plan.currency)}</strong>} />
          </dl>
          <p className="text-xs text-muted">One-time payment for the period shown. {plan.auto_renew ? 'Renews automatically.' : 'It does not renew automatically — we will remind you before it ends.'}{plan.refund_policy ? ` Refunds: ${plan.refund_policy}` : ''}</p>
          <p className="text-xs text-muted">A membership unlocks access features only. It does not guarantee that any pet is available or that a transaction will succeed.</p>
          {error && <Alert tone="danger">{error}</Alert>}
        </div>
      )}
      {view === 'creating' && <div className="grid place-items-center py-8"><Spinner label="Creating your order" /></div>}
      {view === 'awaiting' && checkout && (
        <div className="space-y-3">
          {checkout.provider === 'testmode' ? (
            <>
              <p className="text-sm">Choose a simulated outcome for payment <code className="text-xs">{checkout.payment.id.slice(0, 8)}</code>.</p>
              <div className="grid grid-cols-2 gap-2">
                <Button variant="primary" loading={busy} onClick={() => simulate('success')}><FlaskConical className="h-4 w-4" aria-hidden />Simulate success</Button>
                <Button variant="outline" disabled={busy} onClick={() => simulate('failure')}>Simulate failure</Button>
              </div>
            </>
          ) : (
            <>
              <p className="text-sm text-muted">Complete the payment in the secure window. If it did not open or you closed it, you can reopen it below.</p>
              <Button className="w-full" loading={busy} onClick={() => openRazorpay(checkout).catch((e) => setError((e as Error).message))}>Open payment window</Button>
            </>
          )}
          {error && <Alert tone="danger">{error}</Alert>}
        </div>
      )}
      {view === 'verifying' && <div className="grid place-items-center gap-2 py-8 text-center"><Spinner label="Confirming payment" /><p className="text-sm font-medium">Confirming your payment…</p><p className="text-xs text-muted">Please keep this window open. We confirm with the payment provider before activating anything.</p></div>}
      {view === 'confirming' && (
        <div className="space-y-3 py-2 text-center">
          <Clock className="mx-auto h-8 w-8 text-warning" aria-hidden />
          <p className="font-semibold">We’re still confirming your payment</p>
          <p className="text-sm text-muted">This can take a few minutes. You will not be charged twice. Your plan activates automatically once the provider confirms it, and you’ll get a notification.</p>
          <div className="flex justify-center gap-2"><Button variant="outline" onClick={retry}>Check again</Button><Button variant="ghost" onClick={() => onOpenChange(false)}>Close</Button></div>
        </div>
      )}
      {view === 'success' && (
        <div className="space-y-2 py-3 text-center"><CheckCircle2 className="mx-auto h-10 w-10 text-success" aria-hidden /><p className="text-lg font-semibold">You’re all set</p>
          <p className="text-sm text-muted">Your {plan.name} plan is active. An invoice is available in Billing.</p></div>
      )}
      {view === 'failed' && (
        <div className="space-y-2 py-3 text-center"><XCircle className="mx-auto h-10 w-10 text-danger" aria-hidden /><p className="text-lg font-semibold">Payment not completed</p>
          <p className="text-sm text-muted">{failMsg ?? 'Something went wrong.'}</p></div>
      )}
    </Dialog>
  )
}
const Row = ({ k, v }: { k: string; v: ReactNode }) => <div className="flex items-center justify-between px-3 py-2"><dt className="text-muted">{k}</dt><dd className="tnum">{v}</dd></div>

/** A reassuring explanation of why buyer membership fees are charged. */
export function BuyerTrustNote({ className }: { className?: string }) {
  return (
    <section aria-label="Why contact details require membership" className={cn('rounded-card border border-primary-200/80 bg-warm/80 p-4 text-xs dark:border-primary-900/40 dark:bg-warm/30', className)}>
      <div className="flex items-center gap-2 text-sm font-semibold text-ink">
        <ShieldCheck className="h-4 w-4 shrink-0 text-primary-600" aria-hidden />
        <span>Why is there a small fee to unlock seller contacts?</span>
      </div>
      <p className="mt-1 text-muted leading-relaxed">
        Browsing and searching pets is 100% free. We charge a nominal membership fee (from just ₹50) to protect pets and keep our community safe and spam-free:
      </p>
      <div className="mt-3 grid gap-3 sm:grid-cols-3">
        <div className="flex items-start gap-2">
          <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary-600" aria-hidden />
          <div>
            <strong className="block font-semibold text-ink">Protects Pets &amp; Prevents Scams</strong>
            <span className="text-muted">Prevents puppy mills, commercial flippers, and automated bots from harvesting phone numbers.</span>
          </div>
        </div>
        <div className="flex items-start gap-2">
          <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary-600" aria-hidden />
          <div>
            <strong className="block font-semibold text-ink">Serious Adopters Only</strong>
            <span className="text-muted">Sellers know callers are genuine pet lovers, eliminating spam calls and time-wasters.</span>
          </div>
        </div>
        <div className="flex items-start gap-2">
          <CheckCircle2 className="mt-0.5 h-3.5 w-3.5 shrink-0 text-primary-600" aria-hidden />
          <div>
            <strong className="block font-semibold text-ink">Direct, Zero Brokerage</strong>
            <span className="text-muted">Talk directly via phone &amp; WhatsApp with verified pet parents — no middlemen or hidden commissions.</span>
          </div>
        </div>
      </div>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-2 border-t border-line/60 pt-2 text-[11px] text-muted">
        <span>🔒 Safe &amp; verified direct communication</span>
        <span>One-time access · No recurring auto-debit</span>
      </div>
    </section>
  )
}

/** Lists plans for an audience and launches checkout. */
export function PlanPicker({ audience, open, onOpenChange, onPurchased, suggestedIds }: {
  audience: 'buyer' | 'seller'; open: boolean; onOpenChange: (o: boolean) => void; onPurchased?: () => void; suggestedIds?: string[]
}) {
  const q = usePlans(audience)
  const [chosen, setChosen] = useState<Plan | null>(null)
  // Follow-up (e.g. unlocking the contact) runs only after the buyer has seen the confirmation and closed the dialog.
  const [paid, setPaid] = useState(false)
  // The API's `suggested_plans` hint is a slim summary; always render the full plan records from /subscription-plans.
  const hinted = suggestedIds?.length ? q.items?.filter((p) => suggestedIds.includes(p.id)) : undefined
  const plans = hinted?.length ? hinted : q.items
  return (
    <>
      <Dialog open={open && !chosen} onOpenChange={onOpenChange} title="Choose a membership" description="Unlock seller contact details and enquiries." size="lg">
        {q.isLoading ? <Skeleton className="h-40 w-full" /> : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : (
          <div className="space-y-4">
            <div className="grid gap-3 sm:grid-cols-2">
              {plans?.map((p) => <PlanCard key={p.id} plan={p} cta={<Button variant="accent" onClick={() => setChosen(p)}>Choose {p.name}</Button>} />)}
              {plans?.length === 0 && <p className="text-sm text-muted">No plans are available right now.</p>}
            </div>
            {audience === 'buyer' && <BuyerTrustNote />}
          </div>
        )}
      </Dialog>
      <CheckoutDialog plan={chosen} open={!!chosen && open} onSuccess={() => setPaid(true)}
        onOpenChange={(o) => { if (!o) { setChosen(null); onOpenChange(false); if (paid) { setPaid(false); onPurchased?.() } } }} />
    </>
  )
}
