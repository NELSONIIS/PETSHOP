import { useMemo, useState } from 'react'
import { useParams, useSearchParams, Link } from 'react-router-dom'
import { LocateFixed, SlidersHorizontal, X } from 'lucide-react'
import { useCategories, usePets } from '@/api/hooks'
import { CategoryIcon, ListingGrid } from '@/components/Pet'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { EmptyState, ErrorState } from '@/components/ui/Feedback'
import { Checkbox, Field, Input, Select } from '@/components/ui/Form'
import { Pagination } from '@/components/ui/Pagination'
import { useToast } from '@/components/ui/Toast'
import { useLocationPref } from '@/lib/location'
import { fromMinor, toMinor, titleCase } from '@/lib/utils'

/** Filters mirror GET /pets query params 1:1 so the URL is shareable and the API call is trivial. */
export const FILTER_KEYS = ['q', 'category', 'breed', 'min_price', 'max_price', 'min_age_months', 'max_age_months', 'gender', 'city', 'state',
  'lat', 'lng', 'radius_km', 'seller_type', 'verified_seller', 'listing_type', 'vaccination', 'availability', 'listed_within_days', 'featured', 'sort'] as const
type FilterKey = (typeof FILTER_KEYS)[number]
export type Filters = Partial<Record<FilterKey, string>>

export function filtersFromParams(sp: URLSearchParams): Filters {
  const f: Filters = {}
  for (const k of FILTER_KEYS) { const v = sp.get(k); if (v) f[k] = v }
  return f
}

const LABELS: Partial<Record<FilterKey, (v: string) => string>> = {
  q: (v) => `“${v}”`, category: (v) => titleCase(v), breed: (v) => `Breed: ${titleCase(v)}`,
  min_price: (v) => `From ₹${Number(v) / 100}`, max_price: (v) => `Up to ₹${Number(v) / 100}`,
  min_age_months: (v) => `Age ≥ ${v} mo`, max_age_months: (v) => `Age ≤ ${v} mo`, gender: titleCase, city: (v) => v, state: (v) => v,
  radius_km: (v) => `Within ${v} km`, seller_type: (v) => `${titleCase(v)} seller`, verified_seller: () => 'Verified sellers', listing_type: titleCase,
  vaccination: (v) => `Vaccination: ${v}`, availability: titleCase, listed_within_days: (v) => `Last ${v} days`, featured: () => 'Featured',
}

function FilterForm({ value, onApply, lockCategory }: { value: Filters; onApply: (f: Filters) => void; lockCategory?: boolean }) {
  const cats = useCategories()
  const { loc, locate } = useLocationPref()
  const toast = useToast()
  const [d, setD] = useState<Filters>(value)
  const set = (k: FilterKey, v: string | undefined) => setD((p) => { const n = { ...p }; if (v) n[k] = v; else delete n[k]; if (k === 'category') delete n.breed; return n })
  const breeds = useMemo(() => cats.items?.find((c) => c.slug === d.category)?.breeds?.filter((b) => b.is_active) ?? [], [cats.items, d.category])
  const nearMe = async () => {
    try { const l = loc.lat != null ? loc : await locate(); setD((p) => ({ ...p, lat: String(l.lat), lng: String(l.lng), radius_km: p.radius_km ?? '50', sort: 'nearest' })) } catch (e) { toast.error((e as Error).message) }
  }
  const money = (k: 'min_price' | 'max_price', label: string) => (
    <Field label={label}><Input inputMode="numeric" placeholder="₹" value={d[k] ? fromMinor(Number(d[k])) : ''} onChange={(e) => set(k, e.target.value.replace(/\D/g, '') ? String(toMinor(e.target.value.replace(/\D/g, ''))) : undefined)} /></Field>
  )
  return (
    <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); onApply(d) }}>
      <Field label="Search"><Input value={d.q ?? ''} onChange={(e) => set('q', e.target.value || undefined)} placeholder="Breed, colour, keyword" /></Field>
      {!lockCategory && (
        <Field label="Category"><Select value={d.category ?? ''} onChange={(e) => set('category', e.target.value || undefined)}>
          <option value="">All categories</option>{cats.items?.map((c) => <option key={c.id} value={c.slug}>{c.name}</option>)}</Select></Field>
      )}
      <Field label="Breed"><Select value={d.breed ?? ''} onChange={(e) => set('breed', e.target.value || undefined)} disabled={!d.category || !breeds.length}>
        <option value="">{d.category ? 'All breeds' : 'Choose a category first'}</option>{breeds.map((b) => <option key={b.id} value={b.slug}>{b.name}</option>)}</Select></Field>
      <div className="grid grid-cols-2 gap-2">{money('min_price', 'Min price')}{money('max_price', 'Max price')}</div>
      <div className="grid grid-cols-2 gap-2">
        <Field label="Min age (months)"><Input inputMode="numeric" value={d.min_age_months ?? ''} onChange={(e) => set('min_age_months', e.target.value.replace(/\D/g, '') || undefined)} /></Field>
        <Field label="Max age (months)"><Input inputMode="numeric" value={d.max_age_months ?? ''} onChange={(e) => set('max_age_months', e.target.value.replace(/\D/g, '') || undefined)} /></Field>
      </div>
      <Field label="Gender"><Select value={d.gender ?? ''} onChange={(e) => set('gender', e.target.value || undefined)}><option value="">Any</option><option value="male">Male</option><option value="female">Female</option></Select></Field>
      <fieldset className="space-y-2 rounded-ctl border border-line p-3"><legend className="px-1 text-sm font-medium">Location</legend>
        <Field label="City"><Input value={d.city ?? ''} onChange={(e) => set('city', e.target.value || undefined)} autoComplete="address-level2" /></Field>
        <Button type="button" variant="secondary" size="sm" className="w-full" onClick={nearMe}><LocateFixed className="h-4 w-4" aria-hidden />{d.lat ? 'Using your location' : 'Use my location'}</Button>
        {d.lat && <Field label="Radius"><Select value={d.radius_km ?? '50'} onChange={(e) => set('radius_km', e.target.value)}>{[10, 25, 50, 100, 250, 500].map((r) => <option key={r} value={r}>{r} km</option>)}</Select></Field>}
        {d.lat && <Button type="button" variant="ghost" size="sm" onClick={() => setD((p) => { const n = { ...p }; delete n.lat; delete n.lng; delete n.radius_km; if (n.sort === 'nearest') delete n.sort; return n })}>Clear location</Button>}
      </fieldset>
      <div className="grid grid-cols-2 gap-2">
        <Field label="Listing type"><Select value={d.listing_type ?? ''} onChange={(e) => set('listing_type', e.target.value || undefined)}><option value="">Sale & adoption</option><option value="sale">For sale</option><option value="adoption">Adoption</option></Select></Field>
        <Field label="Seller type"><Select value={d.seller_type ?? ''} onChange={(e) => set('seller_type', e.target.value || undefined)}><option value="">Any</option><option value="individual">Individual</option><option value="business">Business</option></Select></Field>
        <Field label="Vaccination"><Select value={d.vaccination ?? ''} onChange={(e) => set('vaccination', e.target.value || undefined)}><option value="">Any</option><option value="complete">Fully vaccinated</option><option value="partial">Partly vaccinated</option><option value="none">Not vaccinated</option></Select></Field>
        <Field label="Availability"><Select value={d.availability ?? ''} onChange={(e) => set('availability', e.target.value || undefined)}><option value="">Any</option><option value="available">Available</option><option value="reserved">Reserved</option></Select></Field>
        <Field label="Listed within"><Select value={d.listed_within_days ?? ''} onChange={(e) => set('listed_within_days', e.target.value || undefined)}><option value="">Any time</option><option value="1">24 hours</option><option value="7">7 days</option><option value="30">30 days</option></Select></Field>
        <Field label="Sort by"><Select value={d.sort ?? 'newest'} onChange={(e) => set('sort', e.target.value === 'newest' ? undefined : e.target.value)}>
          <option value="newest">Newest</option><option value="price_asc">Price: low to high</option><option value="price_desc">Price: high to low</option>{d.q && <option value="relevance">Relevance</option>}{d.lat && <option value="nearest">Nearest</option>}</Select></Field>
      </div>
      <Checkbox label="Verified sellers only" checked={d.verified_seller === 'true'} onChange={(e) => set('verified_seller', e.target.checked ? 'true' : undefined)} />
      <Checkbox label="Featured only" checked={d.featured === 'true'} onChange={(e) => set('featured', e.target.checked ? 'true' : undefined)} />
      <div className="flex gap-2">
        <Button type="submit" className="flex-1">Apply filters</Button>
        <Button type="button" variant="outline" onClick={() => onApply(lockCategory && value.category ? { category: value.category } : {})}>Reset</Button>
      </div>
    </form>
  )
}

export default function Search() {
  const { slug } = useParams()
  const [sp, setSp] = useSearchParams()
  const cats = useCategories()
  const [sheet, setSheet] = useState(false)
  const filters = useMemo(() => { const f = filtersFromParams(sp); if (slug) f.category = slug; return f }, [sp, slug])
  const page = Math.max(1, Number(sp.get('page')) || 1)
  const q = usePets({ ...filters, page, per_page: 20 })
  const cat = slug ? cats.items?.find((c) => c.slug === slug) : undefined

  const apply = (f: Filters) => {
    const n = new URLSearchParams()
    for (const [k, v] of Object.entries(f)) if (v && !(slug && k === 'category')) n.set(k, v)
    setSp(n)
    setSheet(false)
  }
  const remove = (k: FilterKey) => { const n = new URLSearchParams(sp); n.delete(k); if (k === 'lat') { n.delete('lng'); n.delete('radius_km') } if (k === 'category') n.delete('breed'); n.delete('page'); setSp(n) }
  const active = (Object.keys(filters) as FilterKey[]).filter((k) => k !== 'sort' && k !== 'lng' && !(slug && k === 'category') && (LABELS[k] || k === 'lat'))
  const setPage = (p: number) => { const n = new URLSearchParams(sp); n.set('page', String(p)); setSp(n); window.scrollTo({ top: 0 }) }

  return (
    <div className="container-page py-4 md:py-6">
      {cat ? (
        <header className="mb-3 flex items-center gap-3">
          <span className="grid h-12 w-12 place-items-center rounded-full bg-primary-100 text-primary-700"><CategoryIcon name={cat.icon || cat.slug} className="h-6 w-6" /></span>
          <div><h1 className="text-2xl">{cat.name}</h1>{cat.description && <p className="text-sm text-muted">{cat.description}</p>}</div>
        </header>
      ) : <h1 className="mb-3 text-2xl">Browse pets</h1>}
      <div className="grid gap-5 lg:grid-cols-[272px_1fr]">
        <aside className="hidden lg:block" aria-label="Filters"><div className="card sticky top-20 max-h-[calc(100dvh-100px)] overflow-y-auto p-4"><FilterForm key={JSON.stringify(filters)} value={filters} onApply={apply} lockCategory={!!slug} /></div></aside>
        <div className="min-w-0 space-y-3">
          <div className="flex items-center gap-2">
            <Button variant="outline" className="lg:hidden" onClick={() => setSheet(true)}><SlidersHorizontal className="h-4 w-4" aria-hidden />Filters{active.length > 0 && <span className="rounded-full bg-primary-600 px-1.5 text-xs text-white">{active.length}</span>}</Button>
            <p className="text-sm text-muted tnum" aria-live="polite">{q.meta ? `${q.meta.total} pet${q.meta.total === 1 ? '' : 's'}` : q.isLoading ? 'Searching…' : ''}</p>
            <label className="ml-auto flex items-center gap-2 text-sm"><span className="sr-only sm:not-sr-only text-muted">Sort</span>
              <Select aria-label="Sort results" className="h-10 w-auto" value={filters.sort ?? 'newest'} onChange={(e) => { const n = new URLSearchParams(sp); if (e.target.value === 'newest') n.delete('sort'); else n.set('sort', e.target.value); n.delete('page'); setSp(n) }}>
                <option value="newest">Newest</option><option value="price_asc">Price ↑</option><option value="price_desc">Price ↓</option>{filters.q && <option value="relevance">Relevance</option>}{filters.lat && <option value="nearest">Nearest</option>}</Select></label>
          </div>
          {active.length > 0 && (
            <ul className="flex flex-wrap gap-1.5" aria-label="Active filters">
              {active.map((k) => (
                <li key={k}><button type="button" onClick={() => remove(k)} className="inline-flex h-9 items-center gap-1 rounded-full bg-primary-100 px-3 text-sm font-medium text-primary-700" aria-label={`Remove filter ${k === 'lat' ? 'near me' : LABELS[k]?.(filters[k] ?? '')}`}>
                  {k === 'lat' ? 'Near me' : LABELS[k]?.(filters[k] ?? '')}<X className="h-3.5 w-3.5" aria-hidden /></button></li>
              ))}
            </ul>
          )}
          {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : !q.isLoading && !q.items?.length ? (
            <EmptyState title="No pets match your filters" body="Try widening the price range, removing a filter, or searching a nearby city." action={<Button variant="outline" onClick={() => apply(slug ? {} : {})}>Clear filters</Button>} />
          ) : <><ListingGrid items={q.items} loading={q.isLoading && !q.items} />
            {q.isFetching && q.items && <p className="text-center text-xs text-muted" role="status">Updating…</p>}
            <Pagination meta={q.meta} onPage={setPage} /></>}
          {!slug && !q.isLoading && <p className="pt-2 text-xs text-muted">Looking for a specific kind of pet? <Link className="underline" to="/categories/dogs">Browse by category</Link>.</p>}
        </div>
      </div>
      <Dialog open={sheet} onOpenChange={setSheet} title="Filters" sheetOnly><FilterForm key={JSON.stringify(filters)} value={filters} onApply={apply} lockCategory={!!slug} /></Dialog>
    </div>
  )
}
