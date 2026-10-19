import { useState } from 'react'
import { ExternalLink } from 'lucide-react'
import { api, isApiError, API_BASE } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { AdminVerification, ListingOwner } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { Gallery } from '@/components/Gallery'
import { Price } from '@/components/Pet'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Field, Input, Textarea } from '@/components/ui/Form'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatAge, formatDate, titleCase } from '@/lib/utils'
import { AdminTable, FilterBar, ReasonDialog, usePagedList } from './common'

export function AdminVerifications() {
  const { can } = useAuth()
  const toast = useToast()
  const list = usePagedList<AdminVerification>('/admin/sellers/verifications', { status: 'pending' })
  const [sel, setSel] = useState<AdminVerification | null>(null)
  const [reject, setReject] = useState(false)
  const [notes, setNotes] = useState('')
  const detail = useGet<AdminVerification>(sel ? `/admin/sellers/verifications/${sel.id}` : null)
  const v = detail.items ?? sel
  const fail = (e: unknown) => toast.error(isApiError(e) ? e.message : 'Action failed')
  const finish = (msg: string) => { toast.success(msg); setSel(null); setReject(false); list.q.refetch() }
  const approve = useSend(() => api.post(`/admin/sellers/verifications/${sel?.id}/approve`, notes ? { notes } : {}), { onSuccess: () => finish('Seller verified') })
  const rejectM = useSend((reason: string) => api.post(`/admin/sellers/verifications/${sel?.id}/reject`, { reason }), { onSuccess: () => finish('Verification rejected') })
  return (
    <div className="space-y-3">
      <PageHeader title="Seller verification" subtitle="Review identity and business documents" />
      <TabBar label="Status" value={list.filters.status ?? ''} onChange={(s) => list.set('status', s)} items={[{ value: 'pending', label: 'Pending' }, { value: 'approved', label: 'Approved' }, { value: 'rejected', label: 'Rejected' }]} />
      <AdminTable list={list} rowKey={(x) => x.id} onRowClick={setSel} empty="Nothing to review" columns={[
        { header: 'Seller', cell: (x) => <div><p className="font-medium">{x.seller?.display_name}</p><p className="text-xs text-muted">{x.user_email}</p></div> },
        { header: 'Type', cell: (x) => titleCase(x.seller?.seller_type ?? ''), hideOnMobile: true }, { header: 'State', cell: (x) => x.jurisdiction_state || x.seller?.state || '—' },
        { header: 'Submitted', cell: (x) => formatDate(x.submitted_at) }, { header: 'Status', cell: (x) => <StatusBadge status={x.status} /> }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} size="lg" title={v?.seller?.display_name ?? 'Verification'} description={v?.user_email}
        footer={v?.status === 'pending' && can('sellers.verify') ? <><Button variant="destructive" onClick={() => setReject(true)}>Reject</Button><Button loading={approve.isPending} onClick={() => approve.mutate(undefined, { onError: fail })}>Approve & verify</Button></> : undefined}>
        {detail.isLoading && !v ? <Skeleton className="h-40 w-full" /> : v && (
          <div className="space-y-3 text-sm">
            <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">{[['Seller type', titleCase(v.seller.seller_type)], ['Business', v.seller.business_name || '—'], ['GST', v.seller.gst_number || '—'], ['City', v.seller.city || '—'], ['State', v.seller.state || '—'], ['Operating state', v.jurisdiction_state || '—'], ['Phone', v.seller.contact_phone || '—'], ['Contact email', v.seller.contact_email || '—'], ['Submitted', formatDate(v.submitted_at, true)]].map(([k, x]) => <div key={k}><dt className="text-xs text-muted">{k}</dt><dd className="break-words">{x}</dd></div>)}</dl>
            {v.seller.bio && <p className="rounded-ctl bg-warm p-2">{v.seller.bio}</p>}
            <section aria-label="Documents"><h3 className="mb-1 text-base">Documents ({v.documents.length})</h3>
              {v.documents.length === 0 ? <Alert tone="warning">No documents uploaded.</Alert> : <ul className="divide-y divide-line rounded-ctl border border-line">{v.documents.map((d) => (
                <li key={d.id} className="flex items-center gap-2 p-2"><div className="min-w-0 flex-1"><p className="truncate font-medium">{d.original_name}</p><p className="text-xs text-muted">{titleCase(d.kind)} · {d.mime_type}</p></div>
                  <a href={`${API_BASE}/admin/sellers/documents/${d.id}/file`} target="_blank" rel="noopener noreferrer" className="inline-flex h-9 items-center gap-1 rounded-ctl border border-line px-3 font-semibold text-primary-600 hover:bg-warm">Open<ExternalLink className="h-3.5 w-3.5" aria-hidden /></a></li>))}</ul>}
              <p className="mt-1 text-xs text-muted">Opening a document is recorded in the audit log.</p></section>
            {v.reason && <Alert tone="info" title="Previous decision">{v.reason}</Alert>}
            {v.status === 'pending' && <Field label="Internal notes (optional)"><Textarea rows={2} value={notes} onChange={(e) => setNotes(e.target.value)} /></Field>}
          </div>)}
      </Dialog>
      <ReasonDialog open={reject} onOpenChange={setReject} title="Reject verification" confirmLabel="Reject" destructive loading={rejectM.isPending} help="The seller sees this reason and can resubmit." onConfirm={(r) => rejectM.mutate(r, { onError: fail })} />
    </div>
  )
}

export function AdminListings() {
  const { can } = useAuth()
  const toast = useToast()
  const list = usePagedList<ListingOwner>('/admin/listings', { status: 'pending' })
  const [sel, setSel] = useState<ListingOwner | null>(null)
  const [reason, setReason] = useState<null | 'reject' | 'suspend'>(null)
  const detail = useGet<ListingOwner>(sel ? `/admin/listings/${sel.id}` : null)
  const l = detail.items ?? sel
  const fail = (e: unknown) => toast.error(isApiError(e) ? e.message : 'Action failed')
  const finish = (m: string) => { toast.success(m); setSel(null); setReason(null); list.q.refetch() }
  const act = useSend((a: string) => api.post(`/admin/listings/${sel?.id}/${a}`), { onSuccess: (_d, a) => finish(`Listing ${a === 'approve' ? 'approved' : 'reinstated'}`) })
  const withReason = useSend((r: string) => api.post(`/admin/listings/${sel?.id}/${reason}`, { reason: r }), { onSuccess: () => finish(reason === 'reject' ? 'Listing rejected' : 'Listing suspended') })
  const can_ = can('listings.moderate')
  return (
    <div className="space-y-3">
      <PageHeader title="Listing moderation" subtitle="Approve, reject or suspend pet listings" />
      <FilterBar>
        <div className="min-w-0 flex-1"><TabBar label="Status" value={list.filters.status ?? ''} onChange={(s) => list.set('status', s)} items={[{ value: 'pending', label: 'Pending' }, { value: 'approved', label: 'Approved' }, { value: 'rejected', label: 'Rejected' }, { value: 'suspended', label: 'Suspended' }, { value: 'all', label: 'All' }]} /></div>
        <Field label="Search" className="w-full sm:w-56"><Input placeholder="Title" onChange={(e) => list.set('q', e.target.value)} /></Field>
      </FilterBar>
      <AdminTable list={list} rowKey={(x) => x.id} onRowClick={setSel} empty="No listings in this queue" columns={[
        { header: 'Listing', cell: (x) => <div className="flex items-center gap-2"><div className="h-10 w-14 shrink-0 overflow-hidden rounded bg-warm">{x.cover && <img src={x.cover.thumb} alt="" className="h-full w-full object-cover" loading="lazy" />}</div><div className="min-w-0"><p className="truncate font-medium">{x.title}</p><p className="text-xs text-muted">{x.seller?.display_name}</p></div></div> },
        { header: 'Category', cell: (x) => x.category.name, hideOnMobile: true }, { header: 'Price', cell: (x) => <Price minor={x.price_minor} currency={x.currency} type={x.listing_type} className="text-sm" /> },
        { header: 'Updated', cell: (x) => formatDate(x.updated_at), hideOnMobile: true }, { header: 'Status', cell: (x) => <StatusBadge status={x.status} /> }]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} size="xl" title={l?.title ?? 'Listing'} description={l ? `${l.seller?.display_name} · ${l.category.name}` : undefined}
        footer={l && can_ ? <>
          {(l.status === 'pending' || l.status === 'rejected') && <><Button variant="destructive" onClick={() => setReason('reject')}>Reject</Button><Button loading={act.isPending} onClick={() => act.mutate('approve', { onError: fail })}>Approve</Button></>}
          {l.status === 'approved' && <Button variant="destructive" onClick={() => setReason('suspend')}>Suspend</Button>}
          {l.status === 'suspended' && <Button loading={act.isPending} onClick={() => act.mutate('reinstate', { onError: fail })}>Reinstate</Button>}</> : undefined}>
        {detail.isLoading && !l ? <Skeleton className="h-60 w-full" /> : detail.error ? <ErrorState error={detail.error} onRetry={() => detail.refetch()} /> : l && (
          <div className="grid gap-4 md:grid-cols-2">
            <Gallery images={l.images ?? []} title={l.title} icon={l.category.slug} />
            <div className="space-y-2 text-sm">
              <p className="flex flex-wrap items-center gap-2"><StatusBadge status={l.status} /><Price minor={l.price_minor} currency={l.currency} type={l.listing_type} className="text-lg" /></p>
              <p className="text-muted">{[l.breed?.name ?? l.category.name, formatAge(l.age_months), titleCase(l.gender), [l.city, l.state].filter(Boolean).join(', ')].join(' · ')}</p>
              <p className="whitespace-pre-line">{l.description}</p>
              <p><strong>Vaccination:</strong> {titleCase(l.vaccination_status)} {l.vaccination_notes && `— ${l.vaccination_notes}`}</p>
              {l.health_notes && <p><strong>Health:</strong> {l.health_notes}</p>}
              <p className="text-xs text-muted">Seller: {l.seller?.display_name} {l.seller?.verified ? '(verified)' : '(not verified)'}</p>
              {l.moderation && l.moderation.length > 0 && (
                <section aria-label="Moderation history"><h3 className="text-base">History</h3><ol className="space-y-1.5">{l.moderation.map((m, i) => (
                  <li key={i} className="rounded-ctl bg-warm p-2 text-xs"><p className="font-semibold">{titleCase(m.action)} <span className="font-normal text-muted">· {formatDate(m.created_at, true)}{m.moderator ? ` · ${m.moderator}` : ''}</span></p>
                    {m.reason && <p>{m.reason}</p>}{m.flags?.length > 0 && <p className="text-warning">Flags: {m.flags.join(', ')}</p>}</li>))}</ol></section>)}
            </div>
          </div>)}
      </Dialog>
      <ReasonDialog open={!!reason} onOpenChange={(o) => !o && setReason(null)} title={reason === 'reject' ? 'Reject listing' : 'Suspend listing'} confirmLabel={reason === 'reject' ? 'Reject' : 'Suspend'} destructive loading={withReason.isPending}
        help={reason === 'reject' ? 'The seller sees this and can edit and resubmit.' : 'A suspended listing is hidden from buyers immediately.'} onConfirm={(r) => withReason.mutate(r, { onError: fail })} />
    </div>
  )
}
