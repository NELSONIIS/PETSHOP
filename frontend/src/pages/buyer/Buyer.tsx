import { useState } from 'react'
import { Link } from 'react-router-dom'
import { Heart } from 'lucide-react'
import { useGet } from '@/api/hooks'
import type { BuyerDashboard, ListingCard } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { ListingGrid } from '@/components/Pet'
import { PageHeader, Section, Stat } from '@/components/Section'
import { LinkButton } from '@/components/ui/Button'
import { Alert, EmptyState, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Pagination } from '@/components/ui/Pagination'
import { formatDate } from '@/lib/utils'
import { EnquiryCard } from '../shared/Enquiries'

export function BuyerDashboardPage() {
  const { user } = useAuth()
  const q = useGet<BuyerDashboard>('/buyer/dashboard')
  const recent = useGet<ListingCard[]>('/buyer/recently-viewed')
  const d = q.items
  const sub = d?.subscription
  return (
    <div className="space-y-4">
      <PageHeader title={`Hi ${user?.name.split(' ')[0] ?? 'there'} 👋`} subtitle="Your pet search at a glance" actions={<LinkButton to="/pets" size="sm">Browse pets</LinkButton>} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading || !d ? <div className="grid grid-cols-2 gap-3 md:grid-cols-4">{[0, 1, 2, 3].map((i) => <Skeleton key={i} className="h-20" />)}</div> : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Favourites" value={d.favourites} to="/buyer/favourites" /><Stat label="Enquiries" value={d.enquiries} to="/buyer/enquiries" />
            <Stat label="Unread replies" value={d.unread_replies} to="/buyer/enquiries" tone={d.unread_replies ? 'warn' : undefined} /><Stat label="Contacts unlocked" value={d.unlocked_contacts} />
          </div>
          <section className="card flex flex-wrap items-center justify-between gap-3 p-4" aria-label="Membership summary">
            <div><p className="text-xs text-muted">Membership</p>
              {sub?.active && sub.subscription ? <><h2 className="text-lg">{sub.subscription.plan.name}</h2><p className="text-sm text-muted">Active until {formatDate(sub.subscription.current_period_end)}{sub.entitlements.contact_unlocks != null && ` · ${Math.max(0, sub.entitlements.contact_unlocks - (sub.entitlements.contact_unlocks_used ?? 0))} unlocks left`}</p></>
                : <><h2 className="text-lg">No active membership</h2><p className="text-sm text-muted">Unlock seller contacts and send enquiries.</p></>}</div>
            <LinkButton to="/buyer/membership" variant={sub?.active ? 'outline' : 'accent'} size="sm">{sub?.active ? 'Manage' : 'See plans'}</LinkButton>
          </section>
          <Section title="Recent enquiries" to="/buyer/enquiries" className="!px-0 !py-0">            {d.recent_enquiries.length ? <ul className="space-y-2">{d.recent_enquiries.slice(0, 3).map((e) => <EnquiryCard key={e.id} e={e} role="buyer" />)}</ul> : <EmptyState title="No enquiries yet" body="Open a pet and unlock the seller’s contact to start." />}
          </Section>
        </>
      )}
      {recent.items && recent.items.length > 0 && <Section title="Recently viewed" className="!px-0 !py-0"><ListingGrid items={recent.items.slice(0, 4)} /></Section>}
      <Alert tone="info" title="Stay safe">Meet in person, ask for vaccination records, and never pay in full in advance. <Link to="/safety" className="underline">Read the safety guide</Link>.</Alert>
    </div>
  )
}

export function FavouritesPage() {
  const [page, setPage] = useState(1)
  const q = useGet<ListingCard[]>('/favourites', { page, per_page: 20 }, { keepPrevious: true })
  return (
    <div className="space-y-3">
      <PageHeader title="Saved pets" subtitle="Your favourites" />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading ? <ListingGrid loading count={4} />
        : !q.items?.length ? <EmptyState icon={<Heart className="h-5 w-5" />} title="No saved pets yet" body="Tap the heart on a pet to save it here." action={<LinkButton to="/pets" variant="outline">Browse pets</LinkButton>} />
        : <ListingGrid items={q.items} />}
      <Pagination meta={q.meta} onPage={setPage} />
    </div>
  )
}
