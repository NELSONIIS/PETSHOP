import { useRef, useState } from 'react'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { AdminPayment, AdminSubscription, Refund } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, StatusBadge } from '@/components/ui/Feedback'
import { Field, Input, Select, Textarea } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { formatDate, formatMoney, fromMinor, toMinor, uuid } from '@/lib/utils'
import { AdminTable, FilterBar, shortId, usePagedList } from './common'

export function AdminSubscriptions() {
  const list = usePagedList<AdminSubscription>('/admin/subscriptions')
  return (
    <div className="space-y-3">
      <PageHeader title="Subscriptions" subtitle="Every buyer and seller subscription" />
      <FilterBar>
        <Field label="Audience"><Select value={list.filters.audience ?? ''} onChange={(e) => list.set('audience', e.target.value)}><option value="">All</option><option value="buyer">Buyer</option><option value="seller">Seller</option></Select></Field>
        <Field label="Status"><Select value={list.filters.status ?? ''} onChange={(e) => list.set('status', e.target.value)}><option value="">All</option>{['active', 'grace', 'expired', 'cancelled', 'superseded', 'refunded'].map((s) => <option key={s} value={s}>{s}</option>)}</Select></Field>
      </FilterBar>
      <AdminTable list={list} rowKey={(s) => s.id} empty="No subscriptions" columns={[
        { header: 'User', cell: (s) => <div><p className="font-medium">{s.user_name}</p><p className="text-xs text-muted">{s.user_email}</p></div> },
        { header: 'Audience', cell: (s) => <Badge tone={s.audience === 'seller' ? 'secondary' : 'primary'}>{s.audience}</Badge> }, { header: 'Plan', cell: (s) => s.plan_name },
        { header: 'Status', cell: (s) => <StatusBadge status={s.status} /> }, { header: 'Started', cell: (s) => formatDate(s.starts_at), hideOnMobile: true }, { header: 'Period end', cell: (s) => formatDate(s.current_period_end) }]} />
    </div>
  )
}

export function AdminPayments() {
  const { can } = useAuth()
  const toast = useToast()
  const list = usePagedList<AdminPayment>('/admin/payments')
  const [sel, setSel] = useState<AdminPayment | null>(null)
  const detail = useGet<AdminPayment>(sel ? `/admin/payments/${sel.id}` : null)
  const p = detail.items ?? sel
  const [refundOpen, setRefundOpen] = useState(false)
  const [amount, setAmount] = useState('')
  const [reason, setReason] = useState('')
  const [err, setErr] = useState('')
  const idem = useRef(uuid())
  const remaining = p ? p.amount_minor - p.refunded_minor : 0
  const openRefund = () => { idem.current = uuid(); setAmount(fromMinor(remaining)); setReason(''); setErr(''); setRefundOpen(true) }
  const refund = useSend(() => api.post<Refund>(`/admin/payments/${p?.id}/refunds`, { amount_minor: toMinor(amount), reason: reason.trim(), idempotency_key: idem.current }), {
    onSuccess: () => { toast.success('Refund recorded'); setRefundOpen(false); detail.refetch(); list.q.refetch() },
  })
  const submit = () => {
    const m = toMinor(amount)
    if (!/^\d+(\.\d{1,2})?$/.test(amount) || m <= 0) return setErr('Enter a valid amount')
    if (m > remaining) return setErr(`Cannot exceed the unrefunded balance of ${formatMoney(remaining, p?.currency)}`)
    if (reason.trim().length < 5) return setErr('Reason is required (at least 5 characters)')
    setErr('')
    refund.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Refund failed') })
  }
  return (
    <div className="space-y-3">
      <PageHeader title="Payments & refunds" subtitle="Provider-verified payments only" />
      <FilterBar>
        <Field label="Search" className="min-w-[220px] flex-1"><Input placeholder="Email, payment or provider id" onChange={(e) => list.set('q', e.target.value)} /></Field>
        <Field label="Status"><Select value={list.filters.status ?? ''} onChange={(e) => list.set('status', e.target.value)}><option value="">All</option>{['created', 'pending', 'succeeded', 'failed', 'cancelled', 'refunded', 'partially_refunded'].map((s) => <option key={s} value={s}>{s.replace('_', ' ')}</option>)}</Select></Field>
      </FilterBar>
      <AdminTable list={list} rowKey={(x) => x.id} onRowClick={setSel} empty="No payments" columns={[
        { header: 'ID', cell: (x) => <code className="text-xs">{shortId(x.id)}</code>, hideOnMobile: true }, { header: 'Customer', cell: (x) => <div><p className="font-medium">{x.user_name}</p><p className="text-xs text-muted">{x.user_email}</p></div> },
        { header: 'Plan', cell: (x) => x.plan.name, hideOnMobile: true }, { header: 'Amount', cell: (x) => <span className="tnum">{formatMoney(x.amount_minor, x.currency)}</span> },
        { header: 'Provider', cell: (x) => x.provider, hideOnMobile: true }, { header: 'Status', cell: (x) => <StatusBadge status={x.status} /> }, { header: 'Date', cell: (x) => formatDate(x.created_at) }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} size="lg" title={`Payment ${p ? shortId(p.id) : ''}`} description={p ? `${p.user_name} · ${p.user_email}` : undefined}
        footer={p && can('refunds.create') && (p.status === 'succeeded' || p.status === 'partially_refunded') && remaining > 0 ? <Button variant="destructive" onClick={openRefund}>Issue refund</Button> : undefined}>
        {p && (
          <div className="space-y-3 text-sm">
            <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">{[['Status', <StatusBadge key="s" status={p.status} />], ['Plan', p.plan.name], ['Provider', p.provider], ['Subtotal', formatMoney(p.subtotal_minor, p.currency)], ['Tax', formatMoney(p.tax_minor, p.currency)], ['Total', <strong key="t">{formatMoney(p.amount_minor, p.currency)}</strong>],
              ['Refunded', formatMoney(p.refunded_minor, p.currency)], ['Created', formatDate(p.created_at, true)], ['Paid', formatDate(p.paid_at, true)], ['Provider order', p.provider_order_id ?? '—'], ['Provider payment', p.provider_payment_id ?? '—']].map(([k, v]) => <div key={String(k)} className="min-w-0"><dt className="text-xs text-muted">{k}</dt><dd className="break-all">{v}</dd></div>)}</dl>
            {p.failure_reason && <Alert tone="danger">{p.failure_reason}</Alert>}
            <section aria-label="Refunds"><h3 className="mb-1 text-base">Refunds</h3>{p.refunds?.length ? <ul className="divide-y divide-line rounded-ctl border border-line">{p.refunds.map((r) => <li key={r.id} className="flex items-center justify-between gap-2 p-2"><span><strong className="tnum">{formatMoney(r.amount_minor, p.currency)}</strong> — {r.reason}</span><span className="flex items-center gap-2 text-xs text-muted"><StatusBadge status={r.status} />{formatDate(r.created_at)}</span></li>)}</ul> : <p className="text-muted">No refunds.</p>}</section>
            {!can('refunds.create') && <p className="text-xs text-muted">Your role cannot issue refunds.</p>}
          </div>)}
      </Dialog>
      <Dialog open={refundOpen} onOpenChange={setRefundOpen} size="sm" title="Issue a refund" description="This is recorded in the audit log and cannot be undone."
        footer={<><Button variant="outline" onClick={() => setRefundOpen(false)}>Cancel</Button><Button variant="destructive" loading={refund.isPending} onClick={submit}>Confirm refund</Button></>}>
        <div className="space-y-3">{err && <Alert tone="danger">{err}</Alert>}
          <Field label={`Amount (₹) — up to ${formatMoney(remaining, p?.currency)}`} required><Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^\d.]/g, ''))} /></Field>
          <Field label="Reason" required><Textarea rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} /></Field>
          <p className="text-xs text-muted">Submitting twice cannot double-refund: each attempt carries a unique idempotency key.</p></div>
      </Dialog>
    </div>
  )
}
