import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { Archive, BarChart3, Eye, Heart, MessageSquare, Pencil, Send } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { ListingOwner, ListingStatus, SellerDashboard } from '@/api/types'
import { PlaceholderImage, Price } from '@/components/Pet'
import { PageHeader, Stat } from '@/components/Section'
import { Button, LinkButton } from '@/components/ui/Button'
import { ConfirmDialog } from '@/components/ui/Dialog'
import { Alert, EmptyState, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Select } from '@/components/ui/Form'
import { Pagination } from '@/components/ui/Pagination'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatDate, titleCase } from '@/lib/utils'
import { EnquiryCard } from '../shared/Enquiries'

export function SellerDashboardPage() {
  const q = useGet<SellerDashboard>('/seller/dashboard')
  const d = q.items
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  if (q.isLoading || !d) return <div className="grid grid-cols-2 gap-3 md:grid-cols-4">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-20" />)}</div>
  const sub = d.subscription
  const l = d.listings
  return (
    <div className="space-y-4">
      <PageHeader title="Seller dashboard" actions={<LinkButton to="/seller/listings/new" variant="accent" size="sm">Add a pet</LinkButton>} />
      {d.verification_status !== 'approved' && (
        <Alert tone={d.verification_status === 'rejected' || d.verification_status === 'suspended' ? 'danger' : 'warning'} title={`Verification: ${titleCase(d.verification_status)}`}
          action={<LinkButton to="/seller/verification" size="sm" variant="outline">{d.verification_status === 'pending' ? 'View status' : 'Complete verification'}</LinkButton>}>
          {d.verification_status === 'pending' ? 'Our team is reviewing your documents.' : 'Listings can’t be published until your seller account is verified. Buying a plan does not verify you.'}
        </Alert>)}
      {!sub.active && <Alert tone="warning" title="No active seller plan" action={<LinkButton to="/seller/membership" size="sm" variant="accent">See plans</LinkButton>}>You need an active plan to publish listings.</Alert>}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Stat label="Live listings" value={l.approved} to="/seller/listings?status=approved" hint={sub.entitlements.listing_limit != null ? `of ${sub.entitlements.listing_limit} allowed` : 'Unlimited plan'} />
        <Stat label="Awaiting review" value={l.pending} to="/seller/listings?status=pending" /><Stat label="Views (30 days)" value={d.views_30d} />
        <Stat label="Unread enquiries" value={d.unread_enquiries} to="/seller/enquiries" tone={d.unread_enquiries ? 'warn' : undefined} hint={`${d.enquiries_total} total`} />
      </div>
      <div className="grid grid-cols-3 gap-3 md:grid-cols-5">
        <Stat label="Drafts" value={l.draft} to="/seller/listings?status=draft" /><Stat label="Rejected" value={l.rejected} to="/seller/listings?status=rejected" tone={l.rejected ? 'warn' : undefined} />
        <Stat label="Suspended" value={l.suspended} to="/seller/listings?status=suspended" /><Stat label="Expired" value={l.expired} to="/seller/listings?status=expired" /><Stat label="Sold / unavailable" value={l.sold} to="/seller/listings?status=sold" />
      </div>
      <section aria-labelledby="re-h" className="space-y-2"><div className="flex items-center justify-between"><h2 id="re-h" className="text-lg">Recent enquiries</h2><Link to="/seller/enquiries" className="text-sm font-semibold text-primary-600">Open inbox</Link></div>
        {d.recent_enquiries.length ? <ul className="space-y-2">{d.recent_enquiries.slice(0, 4).map((e) => <EnquiryCard key={e.id} e={e} role="seller" />)}</ul> : <EmptyState title="No enquiries yet" body="Enquiries from buyers appear here." />}</section>
    </div>
  )
}

const TABS = [{ value: '', label: 'All' }, { value: 'draft', label: 'Drafts' }, { value: 'pending', label: 'Pending' }, { value: 'approved', label: 'Active' }, { value: 'rejected', label: 'Rejected' },
  { value: 'suspended', label: 'Suspended' }, { value: 'expired', label: 'Expired' }, { value: 'sold', label: 'Sold / unavailable' }]

function ListingRow({ l }: { l: ListingOwner }) {
  const toast = useToast()
  const nav = useNavigate()
  const [archive, setArchive] = useState(false)
  const submit = useSend(() => api.post(`/seller/listings/${l.id}/submit`), { invalidate: ['/seller/listings', '/seller/dashboard'], onSuccess: () => toast.success('Submitted for moderation') })
  const avail = useSend((a: string) => api.patch(`/seller/listings/${l.id}/availability`, { availability: a }), { invalidate: ['/seller/listings', '/seller/dashboard'], onSuccess: () => toast.success('Availability updated') })
  const del = useSend(() => api.del(`/seller/listings/${l.id}`), { invalidate: ['/seller/listings', '/seller/dashboard'], onSuccess: () => { setArchive(false); toast.success('Listing archived') } })
  const err = (e: unknown) => {
    if (isApiError(e) && (e.code === 'subscription_required' || e.code === 'limit_reached')) { toast.error(e.message); nav('/seller/membership') } else toast.error(isApiError(e) ? e.message : 'Action failed')
  }
  return (
    <li className="card flex flex-col gap-3 p-3 sm:flex-row">
      <div className="h-24 w-full shrink-0 overflow-hidden rounded-chip bg-warm sm:w-32">{l.cover ? <img src={l.cover.thumb} alt="" loading="lazy" className="h-full w-full object-cover" /> : <PlaceholderImage icon={l.category.slug} className="h-full w-full" />}</div>
      <div className="min-w-0 flex-1 space-y-1.5">
        <div className="flex flex-wrap items-center gap-2"><h3 className="min-w-0 truncate text-base">{l.title}</h3><StatusBadge status={l.status} />{l.status === 'approved' && l.availability !== 'available' && <StatusBadge status={l.availability} />}</div>
        <p className="text-sm text-muted"><Price minor={l.price_minor} currency={l.currency} type={l.listing_type} className="text-sm" /> · {l.category.name} · updated {formatDate(l.updated_at)}</p>
        <p className="flex flex-wrap gap-3 text-xs text-muted tnum"><span className="inline-flex items-center gap-1"><Eye className="h-3.5 w-3.5" aria-hidden />{l.views_count} views</span><span className="inline-flex items-center gap-1"><Heart className="h-3.5 w-3.5" aria-hidden />{l.favourites_count}</span><span className="inline-flex items-center gap-1"><MessageSquare className="h-3.5 w-3.5" aria-hidden />{l.enquiries_count}</span></p>
        {l.status === 'rejected' && l.rejection_reason && <Alert tone="danger" title="Rejected">{l.rejection_reason}</Alert>}
        {l.status === 'suspended' && <Alert tone="danger">Suspended by moderators. Contact support if you believe this is a mistake.</Alert>}
        {l.status === 'expired' && <Alert tone="warning">{l.expired_reason === 'subscription' ? 'Hidden because your plan expired. Renew to republish.' : 'This listing has expired.'}</Alert>}
        <div className="flex flex-wrap items-center gap-2 pt-1">
          <LinkButton to={`/seller/listings/${l.id}/edit`} variant="outline" size="sm"><Pencil className="h-4 w-4" aria-hidden />Edit</LinkButton>
          {(l.status === 'draft' || l.status === 'rejected') && <Button size="sm" loading={submit.isPending} onClick={() => submit.mutate(undefined, { onError: err })}><Send className="h-4 w-4" aria-hidden />Submit</Button>}
          {l.status === 'approved' && <>
            <label className="sr-only" htmlFor={`av-${l.id}`}>Availability</label>
            <Select id={`av-${l.id}`} className="h-9 w-auto text-sm" value={l.availability} onChange={(e) => avail.mutate(e.target.value, { onError: err })}>{['available', 'reserved', 'sold', 'unavailable'].map((a) => <option key={a} value={a}>{titleCase(a)}</option>)}</Select>
            <LinkButton to={`/pets/${l.slug}`} variant="ghost" size="sm">View public page</LinkButton></>}
          <LinkButton to={`/seller/analytics?listing=${l.id}`} variant="ghost" size="sm"><BarChart3 className="h-4 w-4" aria-hidden />Analytics</LinkButton>
          <Button variant="ghost" size="sm" onClick={() => setArchive(true)}><Archive className="h-4 w-4" aria-hidden />Archive</Button>
        </div>
      </div>
      <ConfirmDialog open={archive} onOpenChange={setArchive} title="Archive this listing?" destructive confirmLabel="Archive" loading={del.isPending} body="It will no longer be visible to buyers. Existing enquiries are kept." onConfirm={() => del.mutate(undefined, { onError: err })} />
    </li>
  )
}

export function SellerListingsPage() {
  const [sp, setSp] = useSearchParams()
  const status = (sp.get('status') ?? '') as ListingStatus | 'sold' | ''
  const page = Number(sp.get('page')) || 1
  const q = useGet<ListingOwner[]>('/seller/listings', { status: status || undefined, page, per_page: 12 }, { keepPrevious: true })
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); if (v) n.set(k, v); else n.delete(k); if (k !== 'page') n.delete('page'); setSp(n) }
  return (
    <div className="space-y-3">
      <PageHeader title="Pet listings" subtitle="Create, edit and track moderation" actions={<LinkButton to="/seller/listings/new" variant="accent" size="sm">Add a pet</LinkButton>} />
      <TabBar label="Listing status" value={status} onChange={(v) => set('status', v)} items={TABS} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading ? <div className="space-y-2">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-32 w-full" />)}</div>
        : !q.items?.length ? <EmptyState title={status ? `No ${TABS.find((t) => t.value === status)?.label.toLowerCase()} listings` : 'No listings yet'} body="Add your first pet. Photos, health details and an honest description help buyers trust you." action={<LinkButton to="/seller/listings/new" variant="accent">Add a pet</LinkButton>} />
        : <ul className="space-y-3">{q.items.map((l) => <ListingRow key={l.id} l={l} />)}</ul>}
      <Pagination meta={q.meta} onPage={(p) => set('page', String(p))} />
    </div>
  )
}
