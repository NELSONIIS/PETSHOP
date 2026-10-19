import { useParams, useSearchParams } from 'react-router-dom'
import { MapPin } from 'lucide-react'
import { isApiError } from '@/api/client'
import { useGet } from '@/api/hooks'
import type { ListingCard, SellerPublic } from '@/api/types'
import { ListingGrid, VerifiedBadge } from '@/components/Pet'
import { EmptyState, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Pagination } from '@/components/ui/Pagination'
import { formatDate, titleCase } from '@/lib/utils'

export default function SellerProfile() {
  const { slug = '' } = useParams()
  const [sp, setSp] = useSearchParams()
  const page = Number(sp.get('page')) || 1
  const s = useGet<SellerPublic>(`/sellers/${slug}`, undefined, { retry: false })
  const pets = useGet<ListingCard[]>(`/sellers/${slug}/pets`, { page, per_page: 12 }, { keepPrevious: true })
  if (s.isLoading) return <div className="container-page py-6"><Skeleton className="h-32 w-full" /></div>
  if (s.error) return <div className="container-page py-10">{isApiError(s.error) && s.error.status === 404 ? <EmptyState title="Seller not found" /> : <ErrorState error={s.error} onRetry={() => s.refetch()} />}</div>
  const x = s.items!
  return (
    <div className="container-page space-y-4 py-4 md:py-6">
      <header className="card flex flex-col gap-3 p-4 sm:flex-row sm:items-center">
        <span className="grid h-16 w-16 shrink-0 place-items-center overflow-hidden rounded-full bg-primary-100 text-2xl font-bold text-primary-700">{x.logo_url ? <img src={x.logo_url} alt="" className="h-full w-full object-cover" /> : x.display_name.slice(0, 1)}</span>
        <div className="min-w-0 flex-1 space-y-1">
          <h1 className="text-2xl">{x.display_name}</h1>
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"><VerifiedBadge seller={x} /><span>{titleCase(x.seller_type)} seller</span>
            <span className="inline-flex items-center gap-1"><MapPin className="h-4 w-4" aria-hidden />{[x.city, x.state].filter(Boolean).join(', ') || 'India'}</span><span>Member since {formatDate(x.member_since)}</span></div>
          {x.bio && <p className="pt-1 text-sm">{x.bio}</p>}
          {x.verified && <p className="text-xs text-muted">Verified means PETORA reviewed this seller’s identity or business documents{x.verified_at ? ` on ${formatDate(x.verified_at)}` : ''}. It is not a government licence or a health guarantee.</p>}
        </div>
      </header>
      <h2 className="text-xl">Pets from {x.display_name} <span className="text-sm font-normal text-muted tnum">({x.active_listings})</span></h2>
      {pets.error ? <ErrorState error={pets.error} onRetry={() => pets.refetch()} /> : !pets.isLoading && !pets.items?.length ? <EmptyState title="No active listings" /> : <ListingGrid items={pets.items} loading={pets.isLoading && !pets.items} />}
      <Pagination meta={pets.meta} onPage={(p) => setSp({ page: String(p) })} />
    </div>
  )
}
