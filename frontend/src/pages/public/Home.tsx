import { useState } from 'react'
import { Link } from 'react-router-dom'
import { BadgeCheck, HeartHandshake, LocateFixed, Search as SearchIcon, ShieldCheck, Sparkles, Unlock } from 'lucide-react'
import { useCategories, useGet, usePets } from '@/api/hooks'
import type { SellerPublic } from '@/api/types'
import { SearchBar } from '@/components/Header'
import { CategoryTile, ListingGrid, VerifiedBadge } from '@/components/Pet'
import { Section } from '@/components/Section'
import { Button, LinkButton } from '@/components/ui/Button'
import { EmptyState, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { useToast } from '@/components/ui/Toast'
import { useLocationPref } from '@/lib/location'
import { FaqList } from './Content'

function PetRow({ params, empty }: { params: Record<string, string | number | boolean>; empty: string }) {
  const q = usePets({ per_page: 8, ...params }, { keepPrevious: false })
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  if (!q.isLoading && !q.items?.length) return <EmptyState title={empty} />
  return <ListingGrid items={q.items} loading={q.isLoading} count={4} />
}

function Nearby() {
  const { loc, locate } = useLocationPref()
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const q = usePets({ lat: loc.lat, lng: loc.lng, radius_km: 50, sort: 'nearest', per_page: 4 }, { enabled: loc.lat != null && loc.lng != null, keepPrevious: false })
  if (loc.lat == null) {
    return (
      <div className="card flex flex-col items-center gap-2 p-6 text-center">
        <LocateFixed className="h-6 w-6 text-primary-600" aria-hidden />
        <p className="text-sm text-muted">Share your location to see pets close to you. You can also pick a city from the header.</p>
        <Button variant="secondary" loading={busy} onClick={async () => { setBusy(true); try { await locate() } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) } }}>Use my location</Button>
      </div>
    )
  }
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  if (!q.isLoading && !q.items?.length) return <EmptyState title="No pets within 50 km yet" body="Try browsing all of India." action={<LinkButton to="/pets" variant="outline">Browse all pets</LinkButton>} />
  return <ListingGrid items={q.items} loading={q.isLoading} count={4} />
}

function VerifiedSellers() {
  const q = useGet<SellerPublic[]>('/sellers', { per_page: 6 })
  if (q.isLoading) return <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-24" />)}</div>
  if (q.error) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  if (!q.items?.length) return <EmptyState title="Verified sellers will appear here" />
  return (
    <ul className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
      {q.items.map((s) => (
        <li key={s.id}>
          <Link to={`/sellers/${s.slug}`} className="card flex h-full flex-col items-center gap-1 p-3 text-center transition-colors hover:border-primary-300">
            <span className="grid h-12 w-12 place-items-center overflow-hidden rounded-full bg-primary-100 text-lg font-bold text-primary-700">
              {s.logo_url ? <img src={s.logo_url} alt="" className="h-full w-full object-cover" loading="lazy" /> : s.display_name.slice(0, 1)}
            </span>
            <span className="line-clamp-1 text-sm font-semibold">{s.display_name}</span>
            <VerifiedBadge seller={s} />
            <span className="text-xs text-muted">{s.city || s.state}</span>
          </Link>
        </li>
      ))}
    </ul>
  )
}

const how = [
  { icon: SearchIcon, t: 'Browse for free', d: 'Search by breed, price, age and location. No sign-up needed to look.' },
  { icon: Unlock, t: 'Unlock contact', d: 'A buyer membership unlocks seller contact details and enquiries.' },
  { icon: BadgeCheck, t: 'Meet responsibly', d: 'Prefer verified sellers, ask for records, and always meet in person.' },
]

export default function Home() {
  const cats = useCategories()
  const home = useGet<{ hero_title?: string; hero_subtitle?: string; how_it_works?: { title: string; body: string }[]; adoption_title?: string; adoption_body?: string }>('/content/home', undefined, { retry: false })
  const c = home.items
  const steps = c?.how_it_works?.length ? c.how_it_works.map((h, i) => ({ icon: how[i % how.length].icon, t: h.title, d: h.body })) : how
  return (
    <>
      <section className="bg-gradient-to-b from-primary-50 to-bg">
        <div className="container-page grid gap-4 py-8 md:grid-cols-[1.1fr_1fr] md:items-center md:py-12">
          <div className="space-y-3">
            <p className="inline-flex items-center gap-1.5 rounded-full bg-secondary-100 px-3 py-1 text-xs font-semibold text-secondary-700"><Sparkles className="h-3.5 w-3.5" aria-hidden />Responsible pet discovery</p>
            <h1 className="text-3xl md:text-4xl md:leading-tight">{c?.hero_title ?? 'Find your pet, responsibly.'}</h1>
            <p className="max-w-lg text-base text-muted">{c?.hero_subtitle ?? 'Browse pets from sellers who are verified by PETORA, or adopt a pet that needs a home — across India.'}</p>
            <SearchBar className="max-w-lg" />
            <div className="flex flex-wrap gap-2 pt-1 text-sm">
              <Link to="/pets?listing_type=adoption" className="rounded-full border border-line bg-surface px-3 py-1.5 hover:bg-warm">Adoption</Link>
              <Link to="/pets?verified_seller=true" className="rounded-full border border-line bg-surface px-3 py-1.5 hover:bg-warm">Verified sellers</Link>
              <Link to="/pets?sort=newest" className="rounded-full border border-line bg-surface px-3 py-1.5 hover:bg-warm">New today</Link>
            </div>
          </div>
          <div className="hidden md:block">
            <ul className="card space-y-3 bg-surface/80 p-5">
              {[[BadgeCheck, 'Verified sellers', 'Identity or business documents reviewed by PETORA staff.'], [Unlock, 'Free to browse', 'Pay only when you want to contact a seller.'], [HeartHandshake, 'Adopt, don’t shop', 'Rescues and owners list pets for adoption too.']].map(([Icon, t, d]) => {
                const I = Icon as typeof BadgeCheck
                return <li key={t as string} className="flex gap-3"><span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-primary-100 text-primary-700"><I className="h-5 w-5" aria-hidden /></span><div><p className="font-semibold">{t as string}</p><p className="text-sm text-muted">{d as string}</p></div></li>
              })}
            </ul>
          </div>
        </div>
      </section>

      <Section title="Browse by category" to="/pets" linkLabel="All pets">
        {cats.isLoading ? <div className="grid grid-cols-3 gap-3 md:grid-cols-6">{Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} className="h-[88px]" />)}</div>
          : cats.error ? <ErrorState error={cats.error} onRetry={() => cats.refetch()} />
          : <div className="grid grid-cols-3 gap-3 md:grid-cols-6">{cats.items?.map((cat) => <CategoryTile key={cat.id} c={cat} />)}</div>}
      </Section>
      <Section title="Featured pets" to="/pets?featured=true"><PetRow params={{ featured: true }} empty="No featured pets right now" /></Section>
      <Section title="Recently listed" to="/pets?sort=newest" tone="warm"><PetRow params={{ sort: 'newest' }} empty="No pets listed yet" /></Section>
      <Section title="Pets near you" subtitle="Within 50 km of your location"><Nearby /></Section>
      <Section title="Verified sellers" subtitle="Identity and business documents reviewed by PETORA" to="/pets?verified_seller=true" tone="warm"><VerifiedSellers /></Section>
      <Section title={c?.adoption_title ?? 'Adopt a pet'} subtitle={c?.adoption_body ?? 'Give a pet a loving home'} to="/pets?listing_type=adoption"><PetRow params={{ listing_type: 'adoption', per_page: 4 }} empty="Adoption listings will appear here" /></Section>

      <Section title="How PETORA works" tone="warm">
        <ol className="grid gap-3 md:grid-cols-3">
          {steps.map((h, i) => (
            <li key={h.t} className="card flex gap-3 p-4">
              <span className="grid h-10 w-10 shrink-0 place-items-center rounded-full bg-primary-100 text-primary-700"><h.icon className="h-5 w-5" aria-hidden /></span>
              <div><h3 className="text-base"><span className="text-muted tnum">{i + 1}. </span>{h.t}</h3><p className="mt-0.5 text-sm text-muted">{h.d}</p></div>
            </li>
          ))}
        </ol>
      </Section>

      <section className="container-page grid gap-3 py-6 md:grid-cols-2">
        <div className="rounded-card bg-primary-700 p-6 text-white dark:bg-primary-100 dark:text-ink">
          <h2 className="text-xl !text-inherit">Ready to contact a seller?</h2>
          <p className="mt-1 text-sm opacity-90">Buyer membership unlocks seller phone, WhatsApp and email — plus enquiries — on listings you like.</p>
          <LinkButton to="/pricing" variant="accent" className="mt-4">See buyer plans</LinkButton>
        </div>
        <div className="rounded-card bg-secondary-700 p-6 text-white dark:bg-secondary-100 dark:text-ink">
          <h2 className="text-xl !text-inherit">Sell on PETORA</h2>
          <p className="mt-1 text-sm opacity-90">Get verified, choose a seller plan and reach buyers who care about welfare.</p>
          <LinkButton to="/register/seller" variant="outline" className="mt-4 border-white/40 bg-white/10 text-white hover:bg-white/20 dark:text-ink">Become a seller</LinkButton>
        </div>
      </section>

      <Section title="Safety & welfare first" tone="warm">
        <div className="grid gap-3 md:grid-cols-2">
          <div className="card flex gap-3 p-4"><ShieldCheck className="h-6 w-6 shrink-0 text-primary-600" aria-hidden /><p className="text-sm text-muted">Every listing is moderated. Look for the <strong className="text-ink">Verified seller</strong> badge — it means PETORA reviewed identity or business documents. It is not a licence or a health certificate.</p></div>
          <div className="card flex gap-3 p-4"><HeartHandshake className="h-6 w-6 shrink-0 text-accent-600" aria-hidden /><p className="text-sm text-muted">Meet in person, ask for vaccination records and a vet check, and never pay in full in advance. <Link to="/safety" className="font-semibold text-primary-600 underline">Read the safety guide</Link>.</p></div>
        </div>
      </Section>
      <Section title="Frequently asked questions" to="/faq" linkLabel="All FAQs"><FaqList limit={4} /></Section>
    </>
  )
}
