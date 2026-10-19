import { Link, useNavigate, useLocation } from 'react-router-dom'
import { BadgeCheck, Bird, Cat, Dog, Fish, Heart, MapPin, PawPrint, Rabbit, Rat, Squirrel, Turtle } from 'lucide-react'
import type { ComponentType } from 'react'
import { useAuth } from '@/auth/AuthContext'
import { useToggleFavourite } from '@/api/hooks'
import { isApiError } from '@/api/client'
import type { Category, ListingCard, SellerBadge as SellerBadgeT } from '@/api/types'
import { cn, formatAge, formatMoney, titleCase } from '@/lib/utils'
import { Badge, Skeleton } from './ui/Feedback'
import { useToast } from './ui/Toast'

const icons: Record<string, ComponentType<{ className?: string }>> = {
  dog: Dog, cat: Cat, bird: Bird, fish: Fish, rabbit: Rabbit, turtle: Turtle, reptile: Turtle, rat: Rat, hamster: Rat, squirrel: Squirrel, paw: PawPrint,
}
export function CategoryIcon({ name, className }: { name?: string; className?: string }) {
  const I = icons[(name ?? '').toLowerCase()] ?? PawPrint
  return <I className={className} />
}

export function PlaceholderImage({ icon, className }: { icon?: string; className?: string }) {
  return (
    <div className={cn('grid place-items-center bg-gradient-to-br from-primary-50 to-secondary-50 text-primary-400', className)} role="img" aria-label="No photo available">
      <CategoryIcon name={icon} className="h-10 w-10 opacity-70" />
    </div>
  )
}

export function Price({ minor, currency, type, className }: { minor: number; currency: string; type?: string; className?: string }) {
  const free = type === 'adoption' && minor === 0
  return <span className={cn('tnum font-bold', free ? 'text-secondary-600' : 'text-ink', className)}>{free ? 'Free adoption' : formatMoney(minor, currency, { free: true })}</span>
}

/** Only shown when the backend says an admin approved verification. Never implies licensing or medical checks. */
export function VerifiedBadge({ seller, compact }: { seller: Pick<SellerBadgeT, 'verified'>; compact?: boolean }) {
  if (!seller.verified) return null
  return (
    <span className="inline-flex items-center gap-1 text-xs font-semibold text-secondary-600" title="Identity/business documents reviewed by PETORA">
      <BadgeCheck className="h-4 w-4" aria-hidden />{compact ? <span className="sr-only">Verified seller</span> : 'Verified seller'}
    </span>
  )
}

export function FavouriteButton({ id, value, className }: { id: string; value: boolean; className?: string }) {
  const { user } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()
  const toast = useToast()
  const m = useToggleFavourite()
  const click = (e: React.MouseEvent) => {
    e.preventDefault(); e.stopPropagation()
    if (!user) { nav(`/login?next=${encodeURIComponent(loc.pathname + loc.search)}`); return }
    if (user.account_type !== 'buyer') { toast.info('Favourites are available on buyer accounts.'); return }
    m.mutate({ id, on: !value }, { onError: (err) => toast.error(isApiError(err) ? err.message : 'Could not update favourites') })
  }
  return (
    <button type="button" onClick={click} aria-pressed={value} aria-label={value ? 'Remove from favourites' : 'Save to favourites'}
      className={cn('grid h-10 w-10 place-items-center rounded-full bg-surface/95 shadow-card backdrop-blur transition-transform active:scale-90', className)}>
      <Heart className={cn('h-5 w-5', value ? 'fill-accent-500 text-accent-500' : 'text-ink')} aria-hidden />
    </button>
  )
}

export function ListingCardView({ l, priority }: { l: ListingCard; priority?: boolean }) {
  return (
    <article className="card group relative overflow-hidden transition-shadow hover:shadow-raised">
      <div className="relative aspect-[4/3] overflow-hidden bg-warm">
        {l.cover ? (
          <img src={l.cover.medium || l.cover.thumb} srcSet={`${l.cover.thumb} 320w, ${l.cover.medium} 640w`} sizes="(min-width:1024px) 280px, 50vw"
            alt={l.title} loading={priority ? 'eager' : 'lazy'} decoding="async" className="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105" />
        ) : <PlaceholderImage icon={l.category.slug} className="h-full w-full" />}
        <div className="absolute left-2 top-2 flex flex-wrap gap-1">
          {l.featured && <Badge tone="accent" className="bg-accent-500 text-white">Featured</Badge>}
          {l.listing_type === 'adoption' && <Badge tone="secondary">Adoption</Badge>}
          {l.availability !== 'available' && <Badge tone="warning">{titleCase(l.availability)}</Badge>}
        </div>
        <FavouriteButton id={l.id} value={l.is_favourite} className="absolute right-2 top-2" />
      </div>
      <div className="space-y-1 p-3">
        <Price minor={l.price_minor} currency={l.currency} type={l.listing_type} className="text-lg" />
        <h3 className="line-clamp-1 text-base font-semibold">
          <Link to={`/pets/${l.slug}`} className="after:absolute after:inset-0 focus-visible:outline-none">{l.title}</Link>
        </h3>
        <p className="line-clamp-1 text-xs text-muted">{[l.breed?.name ?? l.category.name, formatAge(l.age_months), titleCase(l.gender)].join(' · ')}</p>
        <div className="flex items-center justify-between gap-2 pt-0.5">
          <span className="inline-flex min-w-0 items-center gap-1 text-xs text-muted"><MapPin className="h-3.5 w-3.5 shrink-0" aria-hidden /><span className="truncate">{l.city || l.state || 'India'}{l.distance_km != null ? ` · ${Math.round(l.distance_km)} km` : ''}</span></span>
          <VerifiedBadge seller={l.seller} compact />
        </div>
      </div>
    </article>
  )
}

export function ListingGrid({ items, loading, count = 8 }: { items?: ListingCard[]; loading?: boolean; count?: number }) {
  const cls = 'grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-4'
  if (loading) {
    return <div className={cls}>{Array.from({ length: count }).map((_, i) => (
      <div key={i} className="card overflow-hidden"><Skeleton className="aspect-[4/3] w-full rounded-none" /><div className="space-y-2 p-3"><Skeleton className="h-5 w-1/2" /><Skeleton className="h-4 w-4/5" /><Skeleton className="h-3 w-2/3" /></div></div>
    ))}</div>
  }
  return <div className={cls}>{items?.map((l, i) => <ListingCardView key={l.id} l={l} priority={i < 4} />)}</div>
}

export function CategoryTile({ c }: { c: Category }) {
  return (
    <Link to={`/categories/${c.slug}`} className="card flex min-h-[88px] flex-col items-center justify-center gap-1.5 p-3 text-center transition-colors hover:border-primary-300 hover:bg-primary-50">
      <span className="grid h-10 w-10 place-items-center rounded-full bg-primary-50 text-primary-600"><CategoryIcon name={c.icon || c.slug} className="h-5 w-5" /></span>
      <span className="text-sm font-semibold">{c.name}</span>
      {c.listing_count != null && <span className="text-xs text-muted tnum">{c.listing_count} {c.listing_count === 1 ? 'pet' : 'pets'}</span>}
    </Link>
  )
}
