import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { Printer } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useConfig, useGet, usePlans, useSend, useSubscription } from '@/api/hooks'
import type { Invoice, Payment, Plan } from '@/api/types'
import { BuyerTrustNote, CheckoutDialog, PlanCard } from '@/components/Billing'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/Dialog'
import { Alert, Badge, EmptyState, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Pagination } from '@/components/ui/Pagination'
import { DataTable } from '@/components/ui/Table'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatDate, formatMoney } from '@/lib/utils'

export const isTestInvoice = (number: string) => number.startsWith('TEST-')
const TestBadge = ({ number }: { number: string }) => (isTestInvoice(number) ? <Badge tone="warning" className="ml-1.5">TEST</Badge> : null)

function Meter({ label, used, limit }: { label: string; used: number; limit?: number | null }) {
  const pct = limit ? Math.min(100, (used / limit) * 100) : 0
  return (
    <div className="space-y-1"><div className="flex justify-between text-sm"><span>{label}</span><span className="tnum text-muted">{used} / {limit == null ? 'Unlimited' : limit}</span></div>
      <div className="h-2 overflow-hidden rounded-full bg-line" role="progressbar" aria-label={label} aria-valuenow={used} aria-valuemin={0} aria-valuemax={limit ?? undefined}><div className="h-full rounded-full bg-primary-500" style={{ width: limit == null ? '8%' : `${pct}%` }} /></div></div>
  )
}

export function MembershipPage({ audience }: { audience: 'buyer' | 'seller' }) {
  const toast = useToast()
  const { items: cfg } = useConfig()
  const sub = useSubscription()
  const plans = usePlans(audience)
  const [chosen, setChosen] = useState<Plan | null>(null)
  const [cancelOpen, setCancelOpen] = useState(false)
  const s = sub.items
  const cur = s?.subscription
  const cancel = useSend(() => api.post(`/subscriptions/${cur?.id}/cancel`), { invalidate: ['/subscriptions'], onSuccess: () => { setCancelOpen(false); toast.success('Cancellation recorded') } })
  const notice = typeof cfg?.settings?.['subscription.expiry_notice'] === 'string' ? (cfg.settings['subscription.expiry_notice'] as string) : null
  return (
    <div className="space-y-4">
      <PageHeader title="Membership" subtitle={audience === 'buyer' ? 'Unlock seller contacts and enquiries.' : 'Publish and manage your pet listings.'} />
      {sub.isLoading ? <Skeleton className="h-32 w-full" /> : sub.error ? <ErrorState error={sub.error} onRetry={() => sub.refetch()} /> : (
        <section className="card space-y-3 p-4" aria-label="Current plan">
          {cur && s?.active ? (
            <>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <div><p className="text-xs text-muted">Current plan</p><h2 className="text-xl">{cur.plan.name}</h2></div>
                <StatusBadge status={cur.status} />
              </div>
              <p className="text-sm text-muted">{cur.cancel_at_period_end ? 'Ends' : 'Renews or ends'} on <strong className="text-ink">{formatDate(cur.current_period_end)}</strong>{cur.status === 'grace' && <> · grace period until {formatDate(cur.grace_ends_at)}</>}</p>
              {cur.status === 'grace' && <Alert tone="warning" title="Your plan has expired">You’re in a grace period. Renew now to avoid losing access.</Alert>}
              <div className="grid gap-3 sm:grid-cols-2">
                {audience === 'seller' ? <Meter label="Active listings" used={s.entitlements.listings_used ?? 0} limit={s.entitlements.listing_limit} /> : <>
                  <Meter label="Contact unlocks" used={s.entitlements.contact_unlocks_used ?? 0} limit={s.entitlements.contact_unlocks} />
                  <Meter label="Enquiries" used={s.entitlements.enquiries_used ?? 0} limit={s.entitlements.enquiries} /></>}
              </div>
              {audience === 'seller' && <p className="text-xs text-muted">Analytics: {s.entitlements.analytics ? 'included' : 'not included in this plan'}</p>}
              <div className="flex flex-wrap gap-2">
                {cur.can_renew && <span className="text-sm text-primary-600">You’re in the renewal window — choose a plan below to extend.</span>}
                {!cur.cancel_at_period_end && <Button variant="outline" size="sm" onClick={() => setCancelOpen(true)}>Cancel plan</Button>}
              </div>
            </>
          ) : (
            <>
              <h2 className="text-lg">{cur ? 'Your plan has ended' : 'No active plan'}</h2>
              <p className="text-sm text-muted">{cur ? `${cur.plan.name} ended ${formatDate(cur.current_period_end)}. ` : ''}
                {notice ?? (audience === 'seller' ? 'Without an active plan your listings are not shown to buyers and you cannot publish new ones.' : 'Without a membership seller contact details stay locked. Browsing remains free.')}</p>
            </>
          )}
        </section>
      )}
      <h2 className="text-lg">{s?.active ? 'Change or extend your plan' : 'Choose a plan'}</h2>
      {plans.isLoading ? <Skeleton className="h-56 w-full" /> : plans.error ? <ErrorState error={plans.error} onRetry={() => plans.refetch()} /> : (
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
            {plans.items?.map((p) => <PlanCard key={p.id} plan={p} current={cur?.plan.id === p.id && s?.active} cta={<Button variant="accent" onClick={() => setChosen(p)}>{cur?.plan.id === p.id && s?.active ? 'Renew / extend' : `Choose ${p.name}`}</Button>} />)}
            {plans.items?.length === 0 && <EmptyState title="No plans available" />}
          </div>
          {audience === 'buyer' && <BuyerTrustNote />}
        </div>
      )}
      <p className="text-xs text-muted">Membership gives access to features only; it does not guarantee a pet is available or that a transaction will succeed. See the <Link to="/refund-policy" className="underline">refund policy</Link>.</p>
      <CheckoutDialog plan={chosen} open={!!chosen} onOpenChange={(o) => { if (!o) setChosen(null) }} />
      <ConfirmDialog open={cancelOpen} onOpenChange={setCancelOpen} title="Cancel your plan?" destructive confirmLabel="Cancel plan" loading={cancel.isPending}
        body="Cancellation follows the plan’s cancellation policy. It is not an automatic refund." onConfirm={() => cancel.mutate(undefined, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Could not cancel') })} />
    </div>
  )
}

export function BillingPage({ base }: { base: '/buyer' | '/seller' }) {
  const [tab, setTab] = useState('payments')
  const [page, setPage] = useState(1)
  const pays = useGet<Payment[]>(tab === 'payments' ? '/billing/payments' : null, { page, per_page: 15 }, { keepPrevious: true })
  const invs = useGet<Invoice[]>(tab === 'invoices' ? '/billing/invoices' : null, { page, per_page: 15 }, { keepPrevious: true })
  return (
    <div className="space-y-3">
      <PageHeader title="Billing" subtitle="Payments and invoices" />
      <TabBar label="Billing sections" value={tab} onChange={(v) => { setTab(v); setPage(1) }} items={[{ value: 'payments', label: 'Payments' }, { value: 'invoices', label: 'Invoices' }]} />
      {tab === 'payments' ? <>
        <DataTable rows={pays.items} loading={pays.isLoading} error={pays.error} onRetry={() => pays.refetch()} rowKey={(p) => p.id} empty="No payments yet" columns={[
          { header: 'Date', cell: (p) => formatDate(p.created_at) }, { header: 'Plan', cell: (p) => p.plan.name },
          { header: 'Amount', cell: (p) => <span className="tnum">{formatMoney(p.amount_minor, p.currency)}</span> }, { header: 'Status', cell: (p) => <StatusBadge status={p.status} /> },
          { header: 'Invoice', cell: (p) => p.invoice_id ? <Link className="text-primary-600 underline" to={`${base}/billing/invoices/${p.invoice_id}`}>View</Link> : <span className="text-muted">—</span> }]} />
        <Pagination meta={pays.meta} onPage={setPage} /></> : <>
        <DataTable rows={invs.items} loading={invs.isLoading} error={invs.error} onRetry={() => invs.refetch()} rowKey={(i) => i.id} empty="No invoices yet" columns={[
          { header: 'Number', cell: (i) => <><Link className="font-semibold text-primary-600 underline" to={`${base}/billing/invoices/${i.id}`}>{i.number}</Link><TestBadge number={i.number} /></> }, { header: 'Issued', cell: (i) => formatDate(i.issued_at) },
          { header: 'Total', cell: (i) => <span className="tnum">{formatMoney(i.total_minor, i.currency)}</span> }]} />
        <Pagination meta={invs.meta} onPage={setPage} /></>}
    </div>
  )
}

export function InvoicePage({ base }: { base: '/buyer' | '/seller' }) {
  const { id = '' } = useParams()
  const q = useGet<Invoice>(`/billing/invoices/${id}`, undefined, { retry: false })
  if (q.isLoading) return <Skeleton className="h-64 w-full" />
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  const i = q.items
  if (!i) return null
  return (
    <div className="mx-auto max-w-2xl space-y-3">
      <div className="flex items-center justify-between print:hidden"><Link to={`${base}/billing`} className="text-sm text-primary-600 underline">← Billing</Link><Button variant="outline" size="sm" onClick={() => window.print()}><Printer className="h-4 w-4" aria-hidden />Print / save PDF</Button></div>
      <article className="card space-y-4 p-5 print:border-0 print:shadow-none" aria-label={`Invoice ${i.number}`}>
        <div className="flex flex-wrap items-start justify-between gap-2"><div><h1 className="text-2xl">Invoice<TestBadge number={i.number} /></h1><p className="text-sm text-muted">{i.number}</p>{isTestInvoice(i.number) && <p className="text-xs text-warning">Test-mode invoice — no money was charged.</p>}</div><p className="text-sm text-muted">Issued {formatDate(i.issued_at)}</p></div>
        <div className="text-sm"><p className="text-xs text-muted">Billed to</p><p className="font-semibold">{i.bill_to_name}</p><p>{i.bill_to_email}</p></div>
        <table className="w-full text-sm"><thead><tr className="border-b border-line text-left text-xs text-muted"><th className="py-1.5 font-medium">Description</th><th className="py-1.5 text-right font-medium">Amount</th></tr></thead>
          <tbody>{i.lines.map((l, k) => <tr key={k} className="border-b border-line"><td className="py-2">{l.description}</td><td className="py-2 text-right tnum">{formatMoney(l.amount_minor, i.currency)}</td></tr>)}</tbody></table>
        <dl className="ml-auto w-full max-w-[240px] space-y-1 text-sm"><div className="flex justify-between"><dt className="text-muted">Subtotal</dt><dd className="tnum">{formatMoney(i.subtotal_minor, i.currency)}</dd></div>
          <div className="flex justify-between"><dt className="text-muted">Tax</dt><dd className="tnum">{formatMoney(i.tax_minor, i.currency)}</dd></div>
          <div className="flex justify-between border-t border-line pt-1 text-base font-bold"><dt>Total</dt><dd className="tnum">{formatMoney(i.total_minor, i.currency)}</dd></div></dl>
      </article>
    </div>
  )
}
