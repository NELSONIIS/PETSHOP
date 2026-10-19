import { useState } from 'react'
import { api, isApiError } from '@/api/client'
import { useSend } from '@/api/hooks'
import type { AbuseEnquiry, Dispute, Report } from '@/api/types'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, StatusBadge } from '@/components/ui/Feedback'
import { Checkbox, Field, Select, Textarea } from '@/components/ui/Form'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatDate, timeAgo, titleCase } from '@/lib/utils'
import { AdminTable, FilterBar, shortId, usePagedList } from './common'
import { useAuth } from '@/auth/AuthContext'

function ReportsTab() {
  const toast = useToast()
  const { can } = useAuth()
  const list = usePagedList<Report>('/admin/reports', { status: 'open' })
  const [sel, setSel] = useState<Report | null>(null)
  const [outcome, setOutcome] = useState('resolved')
  const [res, setRes] = useState('')
  const [suspend, setSuspend] = useState(false)
  const [err, setErr] = useState('')
  const m = useSend(() => api.post(`/admin/reports/${sel?.id}/resolve`, { outcome, resolution: res.trim(), suspend_target: suspend }), { onSuccess: () => { toast.success('Report updated'); setSel(null); setRes(''); list.q.refetch() } })
  return (
    <div className="space-y-3">
      <FilterBar><div className="min-w-0 flex-1"><TabBar label="Report status" value={list.filters.status ?? ''} onChange={(v) => list.set('status', v)} items={[{ value: 'open', label: 'Open' }, { value: 'reviewing', label: 'Reviewing' }, { value: 'resolved', label: 'Resolved' }, { value: 'dismissed', label: 'Dismissed' }, { value: 'all', label: 'All' }]} /></div>
        <Field label="Target"><Select value={list.filters.target_type ?? ''} onChange={(e) => list.set('target_type', e.target.value)}><option value="">All</option>{['listing', 'seller', 'user', 'enquiry'].map((t) => <option key={t} value={t}>{t}</option>)}</Select></Field></FilterBar>
      <AdminTable list={list} rowKey={(r) => r.id} onRowClick={(r) => { setSel(r); setErr('') }} empty="No reports" columns={[
        { header: 'Target', cell: (r) => <div><p className="font-medium">{r.target_label || shortId(r.target_id)}</p><p className="text-xs text-muted">{r.target_type}</p></div> }, { header: 'Reason', cell: (r) => titleCase(r.reason) },
        { header: 'Reporter', cell: (r) => r.reporter, hideOnMobile: true }, { header: 'Status', cell: (r) => <StatusBadge status={r.status} /> }, { header: 'Reported', cell: (r) => timeAgo(r.created_at) }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} title="Report" description={sel ? `${sel.target_type} · ${titleCase(sel.reason)}` : undefined}
        footer={sel && (sel.status === 'open' || sel.status === 'reviewing') && can('reports.manage') ? <><Button variant="outline" onClick={() => setSel(null)}>Cancel</Button><Button loading={m.isPending} onClick={() => { if (res.trim().length < 3) return setErr('Add a resolution note'); setErr(''); m.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Failed') }) }}>Save decision</Button></> : undefined}>
        {sel && <div className="space-y-3 text-sm">
          <dl className="grid grid-cols-2 gap-2"><div><dt className="text-xs text-muted">Reporter</dt><dd>{sel.reporter}</dd></div><div><dt className="text-xs text-muted">Reported</dt><dd>{formatDate(sel.created_at, true)}</dd></div><div className="col-span-2"><dt className="text-xs text-muted">Target</dt><dd>{sel.target_label || sel.target_id} <code className="text-xs text-muted">({sel.target_type} {shortId(sel.target_id)})</code></dd></div></dl>
          {sel.details && <p className="rounded-ctl bg-warm p-2">{sel.details}</p>}
          {sel.resolution && <Alert tone="info" title="Resolution">{sel.resolution}</Alert>}
          {(sel.status === 'open' || sel.status === 'reviewing') && can('reports.manage') && <>{err && <Alert tone="danger">{err}</Alert>}
            <Field label="Outcome"><Select value={outcome} onChange={(e) => setOutcome(e.target.value)}><option value="resolved">Resolved — action taken</option><option value="dismissed">Dismissed — no violation</option></Select></Field>
            <Field label="Resolution note" required><Textarea rows={3} value={res} onChange={(e) => setRes(e.target.value)} /></Field>
            {outcome === 'resolved' && <Checkbox label={`Also suspend the reported ${sel.target_type}`} checked={suspend} onChange={(e) => setSuspend(e.target.checked)} />}</>}
        </div>}
      </Dialog>
    </div>
  )
}

function DisputesTab() {
  const toast = useToast()
  const list = usePagedList<Dispute>('/admin/disputes', { status: 'open' })
  const [sel, setSel] = useState<Dispute | null>(null)
  const [outcome, setOutcome] = useState('resolved')
  const [res, setRes] = useState('')
  const [err, setErr] = useState('')
  const m = useSend(() => api.post(`/admin/disputes/${sel?.id}/resolve`, { outcome, resolution: res.trim() }), { onSuccess: () => { toast.success('Dispute updated'); setSel(null); setRes(''); list.q.refetch() } })
  const open = sel && (sel.status === 'open' || sel.status === 'under_review')
  return (
    <div className="space-y-3">
      <TabBar label="Dispute status" value={list.filters.status ?? ''} onChange={(v) => list.set('status', v)} items={[{ value: 'open', label: 'Open' }, { value: 'under_review', label: 'Under review' }, { value: 'resolved', label: 'Resolved' }, { value: 'rejected', label: 'Rejected' }, { value: 'all', label: 'All' }]} />
      <AdminTable list={list} rowKey={(d) => d.id} onRowClick={(d) => { setSel(d); setErr('') }} empty="No disputes" columns={[
        { header: 'Subject', cell: (d) => <div><p className="font-medium">{d.subject}</p><p className="text-xs text-muted">{titleCase(d.kind)}</p></div> }, { header: 'Opened by', cell: (d) => d.opened_by, hideOnMobile: true },
        { header: 'Status', cell: (d) => <StatusBadge status={d.status} /> }, { header: 'Opened', cell: (d) => timeAgo(d.created_at) }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} title={sel?.subject ?? 'Dispute'} description={sel ? `${titleCase(sel.kind)} · ${sel.opened_by}` : undefined}
        footer={open ? <><Button variant="outline" onClick={() => setSel(null)}>Cancel</Button><Button loading={m.isPending} onClick={() => { if (res.trim().length < 3) return setErr('Add a note for the user'); setErr(''); m.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Failed') }) }}>Save</Button></> : undefined}>
        {sel && <div className="space-y-3 text-sm"><p className="whitespace-pre-line rounded-ctl bg-warm p-2">{sel.message}</p>
          {sel.resolution && <Alert tone="info" title="Resolution">{sel.resolution}</Alert>}
          {open && <>{err && <Alert tone="danger">{err}</Alert>}<Field label="Decision"><Select value={outcome} onChange={(e) => setOutcome(e.target.value)}><option value="under_review">Mark under review</option><option value="resolved">Resolved in user’s favour / settled</option><option value="rejected">Rejected</option></Select></Field>
            <Field label="Note to the user" required><Textarea rows={3} value={res} onChange={(e) => setRes(e.target.value)} /></Field></>}</div>}
      </Dialog>
    </div>
  )
}

export function AdminReports() {
  const [tab, setTab] = useState('reports')
  return (
    <div className="space-y-3">
      <PageHeader title="Reports & disputes" subtitle="Trust & safety queue" />
      <TabBar label="Section" value={tab} onChange={setTab} items={[{ value: 'reports', label: 'Reports' }, { value: 'disputes', label: 'Disputes & appeals' }]} />
      {tab === 'reports' ? <ReportsTab /> : <DisputesTab />}
    </div>
  )
}

export function AdminEnquiries() {
  const list = usePagedList<AbuseEnquiry>('/admin/enquiries', { status: 'reported' })
  const [sel, setSel] = useState<AbuseEnquiry | null>(null)
  return (
    <div className="space-y-3">
      <PageHeader title="Enquiry abuse review" subtitle="Reported conversations. Act on them from the matching report." />
      <TabBar label="Status" value={list.filters.status ?? ''} onChange={(v) => list.set('status', v)} items={[{ value: 'reported', label: 'Reported' }, { value: 'closed', label: 'Closed' }, { value: 'all', label: 'All' }]} />
      <AdminTable list={list} rowKey={(r) => r.id} onRowClick={setSel} empty="No enquiries to review" columns={[
        { header: 'Listing', cell: (r) => r.listing_title }, { header: 'Buyer', cell: (r) => r.buyer_email, hideOnMobile: true }, { header: 'Seller', cell: (r) => r.seller_email, hideOnMobile: true },
        { header: 'Messages', cell: (r) => r.messages?.length ?? 0 }, { header: 'Status', cell: (r) => <StatusBadge status={r.status} /> }, { header: 'Started', cell: (r) => timeAgo(r.created_at) }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} size="lg" title="Conversation" description={sel ? `${sel.listing_title} · ${sel.buyer_email} ↔ ${sel.seller_email}` : undefined}>
        {sel && (sel.messages?.length ? <ol className="space-y-2" aria-label="Messages">{sel.messages.map((m, i) => (
          <li key={i} className={`rounded-ctl p-2 text-sm ${m.sender === 'buyer' ? 'bg-warm' : 'bg-secondary-50'}`}><p className="text-xs font-semibold">{m.sender === 'buyer' ? `Buyer · ${sel.buyer_email}` : `Seller · ${sel.seller_email}`}</p>
            <p className="whitespace-pre-wrap">{m.body}</p><p className="text-xs text-muted">{formatDate(m.created_at, true)}</p></li>))}</ol> : <Alert tone="info">No messages in this conversation.</Alert>)}
      </Dialog>
    </div>
  )
}
