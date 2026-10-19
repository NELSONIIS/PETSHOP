import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom'
import { Calendar, Flag, MapPin, Share2, Syringe, Cpu, Bug } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet } from '@/api/hooks'
import type { ListingCard, ListingDetail } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { ContactPanel } from '@/components/ContactPanel'
import { Gallery } from '@/components/Gallery'
import { FavouriteButton, ListingGrid, Price, VerifiedBadge } from '@/components/Pet'
import { Section } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, EmptyState, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Field, Select, Textarea } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { formatAge, formatDate, titleCase } from '@/lib/utils'

function ReportDialog({ id, open, onOpenChange }: { id: string; open: boolean; onOpenChange: (o: boolean) => void }) {
  const toast = useToast()
  const [reason, setReason] = useState('misleading')
  const [details, setDetails] = useState('')
  const [busy, setBusy] = useState(false)
  const submit = async () => {
    setBusy(true)
    try { await api.post('/reports', { target_type: 'listing', target_id: id, reason, details }); toast.success('Thanks — our moderators will review this listing.'); onOpenChange(false); setDetails('') }
    catch (e) { toast.error(isApiError(e) ? (e.status === 409 ? 'You have already reported this listing.' : e.message) : 'Could not send report') } finally { setBusy(false) }
  }
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title="Report this listing" description="Tell us what’s wrong. Reports are confidential."
      footer={<><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button><Button variant="destructive" loading={busy} onClick={submit}>Submit report</Button></>}>
      <div className="space-y-3">
        <Field label="Reason"><Select value={reason} onChange={(e) => setReason(e.target.value)}>
          {['spam', 'scam', 'prohibited', 'misleading', 'animal_welfare', 'abuse', 'other'].map((r) => <option key={r} value={r}>{titleCase(r)}</option>)}</Select></Field>
        <Field label="Details (optional)"><Textarea value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} /></Field>
      </div>
    </Dialog>
  )
}

function Fact({ icon: I, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string }) {
  return <div className="flex items-start gap-2 rounded-ctl bg-warm p-2.5"><I className="mt-0.5 h-4 w-4 shrink-0 text-primary-600" aria-hidden /><div><p className="text-xs text-muted">{label}</p><p className="text-sm font-semibold">{value}</p></div></div>
}
const yn = (v?: boolean | null) => (v == null ? 'Not stated' : v ? 'Yes' : 'No')

export default function PetDetail() {
  const { slug = '' } = useParams()
  const { user } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()
  const toast = useToast()
  const q = useGet<ListingDetail>(`/pets/${slug}`, undefined, { retry: (n, e) => !(isApiError(e) && e.status === 404) && n < 2 })
  const l = q.items
  const similar = useGet<ListingCard[]>(l ? `/pets/${l.id}/similar` : null)
  const [report, setReport] = useState(false)

  useEffect(() => {
    if (l?.id) api.post(`/pets/${l.id}/view`).catch(() => undefined)
  }, [l?.id])
  useEffect(() => { if (l) document.title = `${l.title} — PETORA` }, [l])

  if (q.isLoading) return <div className="container-page grid gap-5 py-6 lg:grid-cols-[1fr_360px]"><Skeleton className="aspect-[4/3] w-full" /><Skeleton className="h-64 w-full" /></div>
  if (q.error) {
    return <div className="container-page py-10">{isApiError(q.error) && q.error.status === 404
      ? <EmptyState title="This pet is no longer listed" body="The listing may have been sold, removed or is awaiting review." action={<Link to="/pets" className="font-semibold text-primary-600 underline">Browse other pets</Link>} />
      : <ErrorState error={q.error} onRetry={() => q.refetch()} />}</div>
  }
  if (!l) return null
  const share = async () => {
    const url = window.location.href
    try { if (navigator.share) await navigator.share({ title: l.title, url }); else { await navigator.clipboard.writeText(url); toast.success('Link copied') } } catch { /* user cancelled */ }
  }
  const sp = l.seller_profile
  return (
    <div className="container-page py-4 md:py-6">
      <nav aria-label="Breadcrumb" className="mb-3 text-xs text-muted">
        <Link to="/pets" className="hover:underline">Pets</Link> / <Link to={`/categories/${l.category.slug}`} className="hover:underline">{l.category.name}</Link>{l.breed && <> / <span>{l.breed.name}</span></>}
      </nav>
      <div className="grid gap-5 lg:grid-cols-[1fr_360px]">
        <div className="min-w-0 space-y-4">
          <Gallery images={l.images} title={l.title} icon={l.category.slug} />
          <div className="space-y-2">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0"><h1 className="text-2xl">{l.title}</h1>
                <p className="mt-1 flex flex-wrap items-center gap-x-3 gap-y-1 text-sm text-muted"><span className="inline-flex items-center gap-1"><MapPin className="h-4 w-4" aria-hidden />{[l.city, l.state].filter(Boolean).join(', ') || 'India'}</span>
                  {l.published_at && <span className="inline-flex items-center gap-1"><Calendar className="h-4 w-4" aria-hidden />Listed {formatDate(l.published_at)}</span>}</p></div>
              <div className="flex shrink-0 gap-1.5">
                <FavouriteButton id={l.id} value={l.is_favourite} className="border border-line" />
                <button type="button" onClick={share} aria-label="Share listing" className="grid h-10 w-10 place-items-center rounded-full border border-line bg-surface"><Share2 className="h-5 w-5" aria-hidden /></button>
              </div>
            </div>
            <div className="flex flex-wrap items-center gap-2"><Price minor={l.price_minor} currency={l.currency} type={l.listing_type} className="text-2xl" />
              {l.listing_type === 'adoption' && <Badge tone="secondary">Adoption</Badge>}{l.featured && <Badge tone="accent">Featured</Badge>}
              <Badge tone={l.availability === 'available' ? 'success' : 'warning'}>{titleCase(l.availability)}</Badge></div>
          </div>
          <dl className="grid grid-cols-2 gap-2 sm:grid-cols-4">
            {[['Breed', l.breed?.name ?? l.category.name], ['Age', formatAge(l.age_months)], ['Gender', titleCase(l.gender)], ['Colour', l.colour || 'Not stated']].map(([k, v]) => (
              <div key={k} className="card p-2.5"><dt className="text-xs text-muted">{k}</dt><dd className="text-sm font-semibold">{v}</dd></div>))}
          </dl>
          {l.description && <section aria-labelledby="desc-h"><h2 id="desc-h" className="mb-1 text-lg">About this pet</h2><p className="whitespace-pre-line text-base text-ink/90">{l.description}</p></section>}
          {Object.keys(l.attributes ?? {}).length > 0 && (
            <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3">{Object.entries(l.attributes).map(([k, v]) => <div key={k} className="rounded-ctl bg-warm p-2.5"><dt className="text-xs text-muted">{titleCase(k)}</dt><dd className="text-sm font-semibold">{v}</dd></div>)}</dl>)}
          <section aria-labelledby="health-h" className="space-y-2">
            <h2 id="health-h" className="text-lg">Health & vaccination (as declared by the seller)</h2>
            <div className="grid gap-2 sm:grid-cols-3">
              <Fact icon={Syringe} label="Vaccination" value={l.vaccination_status === 'unspecified' ? 'Not stated' : titleCase(l.vaccination_status)} />
              <Fact icon={Bug} label="Dewormed" value={yn(l.dewormed)} /><Fact icon={Cpu} label="Microchipped" value={yn(l.microchipped)} />
            </div>
            {l.vaccination_notes && <p className="text-sm"><strong>Vaccination notes:</strong> {l.vaccination_notes}</p>}
            {l.health_notes && <p className="text-sm"><strong>Health notes:</strong> {l.health_notes}</p>}
            <Alert tone="info">{l.disclaimer || 'Health details are provided by the seller and have not been verified by PETORA. Please have the pet examined by a veterinarian before you decide.'}</Alert>
          </section>
          <section aria-labelledby="seller-h" className="card flex items-center gap-3 p-3">
            <span className="grid h-12 w-12 shrink-0 place-items-center overflow-hidden rounded-full bg-primary-100 text-lg font-bold text-primary-700">{sp.logo_url ? <img src={sp.logo_url} alt="" className="h-full w-full object-cover" /> : sp.display_name.slice(0, 1)}</span>
            <div className="min-w-0 flex-1"><h2 id="seller-h" className="truncate text-base">{sp.display_name}</h2>
              <div className="flex flex-wrap items-center gap-x-2 text-xs text-muted"><VerifiedBadge seller={sp} /><span>{titleCase(sp.seller_type)}</span><span>Member since {formatDate(sp.member_since)}</span><span>{sp.active_listings} active listing{sp.active_listings === 1 ? '' : 's'}</span></div></div>
            <Link to={`/sellers/${sp.slug}`} className="shrink-0 text-sm font-semibold text-primary-600 underline">View profile</Link>
          </section>
          <button type="button" onClick={() => (user ? setReport(true) : nav(`/login?next=${encodeURIComponent(loc.pathname)}`))} className="inline-flex min-h-[44px] items-center gap-1.5 text-sm text-muted hover:text-danger"><Flag className="h-4 w-4" aria-hidden />Report this listing</button>
        </div>
        <aside className="lg:sticky lg:top-20 lg:self-start" id="contact"><ContactPanel listing={l} /></aside>
      </div>
      {similar.items && similar.items.length > 0 && <Section title="Similar pets" className="px-0"><ListingGrid items={similar.items} /></Section>}
      <ReportDialog id={l.id} open={report} onOpenChange={setReport} />
    </div>
  )
}
