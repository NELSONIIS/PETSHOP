import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { Trash2 } from 'lucide-react'
import { useQueryClient } from '@tanstack/react-query'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { ListingAnalytics, ListingOwner, SellerDocument, SellerProfileOwner, VerificationStatus } from '@/api/types'
import { LineChart, dayLabel } from '@/components/Chart'
import { PageHeader, Stat } from '@/components/Section'
import { DropZone, UploadList, useUploads } from '@/components/Upload'
import { Button, LinkButton } from '@/components/ui/Button'
import { Alert, EmptyState, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Field, Input, Select, Textarea } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { formatDate, titleCase } from '@/lib/utils'
import { ProfileSecurityPage } from '../shared/Account'

export function SellerAnalyticsPage() {
  const [sp, setSp] = useSearchParams()
  const listings = useGet<ListingOwner[]>('/seller/listings', { per_page: 50 })
  const listing = sp.get('listing') ?? listings.items?.[0]?.id ?? ''
  const days = sp.get('days') ?? '30'
  const q = useGet<ListingAnalytics>(listing ? `/seller/listings/${listing}/analytics` : null, { days }, { retry: false })
  const noAccess = isApiError(q.error) && (q.error.status === 402 || q.error.code === 'subscription_required')
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); n.set(k, v); setSp(n) }
  return (
    <div className="space-y-3">
      <PageHeader title="Analytics" subtitle="Views, saves and enquiries per listing" />
      {listings.isLoading ? <Skeleton className="h-10 w-full" /> : !listings.items?.length ? <EmptyState title="No listings to analyse yet" action={<LinkButton to="/seller/listings/new">Add a pet</LinkButton>} /> : (
        <div className="flex flex-wrap gap-3">
          <Field label="Listing" className="min-w-[220px] flex-1"><Select value={listing} onChange={(e) => set('listing', e.target.value)}>{listings.items.map((l) => <option key={l.id} value={l.id}>{l.title}</option>)}</Select></Field>
          <Field label="Period"><Select value={days} onChange={(e) => set('days', e.target.value)}>{['7', '30', '90'].map((d) => <option key={d} value={d}>Last {d} days</option>)}</Select></Field>
        </div>)}
      {noAccess ? <Alert tone="info" title="Analytics isn’t included in your plan" action={<LinkButton to="/seller/membership" size="sm" variant="accent">Upgrade</LinkButton>}>Upgrade to a plan with analytics to see how buyers engage with your listings.</Alert>
        : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading && listing ? <Skeleton className="h-56 w-full" /> : q.items && (
          <>
            <div className="grid grid-cols-3 gap-3"><Stat label="Views" value={q.items.views_total} /><Stat label="Saves" value={q.items.favourites_total} /><Stat label="Enquiries" value={q.items.enquiries_total} /></div>
            <section className="card p-4"><h2 className="mb-2 text-lg">Daily views</h2><LineChart title={`Daily views, last ${days} days`} data={q.items.series.map((s) => ({ label: dayLabel(s.date), value: s.views }))} /></section>
          </>)}
    </div>
  )
}

const DOC_KINDS = ['identity', 'business_registration', 'trade_licence', 'breeder_registration', 'address_proof', 'other']

export function SellerVerificationPage() {
  const toast = useToast()
  const qc = useQueryClient()
  const q = useGet<VerificationStatus>('/seller/verification')
  const [kind, setKind] = useState('identity')
  const [state, setState] = useState('')
  const refresh = () => qc.invalidateQueries({ predicate: (x) => typeof x.queryKey[0] === 'string' && (x.queryKey[0] as string).startsWith('/seller') })
  const up = useUploads({ path: '/seller/documents', extra: { kind }, accept: ['application/pdf', 'image/jpeg', 'image/png'], maxBytes: 10 * 1048576, onUploaded: refresh })
  const del = useSend((id: string) => api.del(`/seller/documents/${id}`), { invalidate: ['/seller'], onSuccess: () => toast.success('Document removed') })
  const submit = useSend(() => api.post<VerificationStatus>('/seller/verification/submit', { jurisdiction_state: state.trim() }), { invalidate: ['/seller'], onSuccess: () => toast.success('Submitted for review') })
  const [err, setErr] = useState<string | null>(null)
  const v = q.items
  if (q.isLoading) return <Skeleton className="h-64 w-full" />
  if (q.error || !v) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  const editable = v.status === 'unsubmitted' || v.status === 'rejected'
  return (
    <div className="mx-auto max-w-2xl space-y-3">
      <PageHeader title="Seller verification" subtitle="Verified sellers earn a badge buyers can trust" />
      <section className="card space-y-2 p-4" aria-label="Verification status">
        <div className="flex items-center justify-between"><h2 className="text-lg">Status</h2><StatusBadge status={v.status} /></div>
        {v.status === 'pending' && <Alert tone="info">Submitted {formatDate(v.submitted_at)}. Reviews usually take 1–2 working days. Documents can’t be changed while under review.</Alert>}
        {v.status === 'approved' && <Alert tone="success">Your seller account is verified{v.reviewed_at ? ` (${formatDate(v.reviewed_at)})` : ''}. Buyers see a “Verified seller” badge.</Alert>}
        {v.status === 'rejected' && <Alert tone="danger" title="Not approved">{v.reason ?? 'Please review your documents and resubmit.'}</Alert>}
        {v.status === 'suspended' && <Alert tone="danger">Your verification is suspended. Contact support.</Alert>}
        <p className="text-xs text-muted">The badge means PETORA reviewed identity or business documents. It is not a government licence and does not certify any pet’s health.</p>
      </section>
      {editable && v.requirements.length > 0 && <Alert tone="warning" title="Still needed"><ul className="list-disc pl-5">{v.requirements.map((r) => <li key={r}>{r}</li>)}</ul><Link to="/seller/profile" className="mt-1 inline-block font-semibold underline">Complete your seller profile</Link></Alert>}
      <section className="card space-y-3 p-4" aria-label="Documents">
        <h2 className="text-lg">Documents</h2>
        {v.documents.length === 0 ? <p className="text-sm text-muted">No documents uploaded yet.</p> : (
          <ul className="divide-y divide-line">{v.documents.map((d: SellerDocument) => (
            <li key={d.id} className="flex items-center gap-3 py-2"><div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{d.original_name}</p><p className="text-xs text-muted">{titleCase(d.kind)} · {(d.size_bytes / 1024).toFixed(0)} KB · {formatDate(d.uploaded_at)}</p></div>
              {editable && <Button variant="ghost" size="icon" aria-label={`Delete ${d.original_name}`} onClick={() => del.mutate(d.id, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Could not delete') })}><Trash2 className="h-4 w-4 text-danger" /></Button>}</li>))}</ul>)}
        {editable && <>
          <Field label="Document type"><Select value={kind} onChange={(e) => setKind(e.target.value)}>{DOC_KINDS.map((k) => <option key={k} value={k}>{titleCase(k)}</option>)}</Select></Field>
          <DropZone label="Upload a document" hint="PDF, JPEG or PNG · up to 10 MB · stored privately" accept="application/pdf,image/jpeg,image/png" onFiles={up.add} />
          <UploadList items={up.items} rejected={up.rejected} onCancel={up.cancel} onRetry={up.retry} onDismiss={up.dismiss} /></>}
      </section>
      {editable && (
        <section className="card space-y-3 p-4" aria-label="Submit for review">
          <Field label="State where you operate" hint="Rules for selling animals vary by state." error={err ?? undefined}><Input value={state} onChange={(e) => setState(e.target.value)} /></Field>
          <Button variant="accent" loading={submit.isPending} onClick={() => { setErr(null); submit.mutate(undefined, { onError: (e) => { setErr(isApiError(e) ? (e.details[0]?.message ?? e.message) : 'Could not submit'); if (isApiError(e)) toast.error(e.message) } }) }}>Submit for verification</Button>
        </section>)}
    </div>
  )
}

export function SellerProfilePage() {
  const toast = useToast()
  const qc = useQueryClient()
  const q = useGet<SellerProfileOwner>('/seller/profile')
  const [f, setF] = useState<Record<string, string> | null>(null)
  const [errs, setErrs] = useState<Record<string, string>>({})
  const p = q.items
  const v = f ?? (p ? { display_name: p.display_name, seller_type: p.seller_type, business_name: p.business_name ?? '', gst_number: p.gst_number ?? '', bio: p.bio ?? '', city: p.city ?? '', state: p.state ?? '', contact_phone: p.contact_phone ?? '', contact_whatsapp: p.contact_whatsapp ?? '', contact_email: p.contact_email ?? '' } : null)
  const refresh = () => qc.invalidateQueries({ queryKey: ['/seller/profile'] })
  const save = useSend(() => api.put('/seller/profile', Object.fromEntries(Object.entries(v ?? {}).map(([k, x]) => [k, x.trim()]))), { invalidate: ['/seller'], onSuccess: () => { toast.success('Profile saved'); setF(null) } })
  const logo = useUploads({ path: '/seller/logo', accept: ['image/jpeg', 'image/png', 'image/webp'], maxBytes: 5 * 1048576, maxCount: 1, onUploaded: () => { toast.success('Logo updated'); void refresh() } })
  if (q.isLoading) return <Skeleton className="h-64 w-full" />
  if (q.error || !v || !p) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  const set = (k: string, x: string) => setF({ ...v, [k]: x })
  const submit = (e: React.FormEvent) => {
    e.preventDefault(); setErrs({})
    if (v.display_name.trim().length < 2) return setErrs({ display_name: 'Enter a display name' })
    save.mutate(undefined, { onError: (er) => { if (isApiError(er) && er.details.length) setErrs(Object.fromEntries(er.details.map((d) => [d.field, d.message]))); else toast.error(isApiError(er) ? er.message : 'Could not save') } })
  }
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      <PageHeader title="Seller profile" subtitle="How buyers see you" actions={<LinkButton to={`/sellers/${p.slug}`} variant="outline" size="sm">View public profile</LinkButton>} />
      <form onSubmit={submit} className="card space-y-3 p-4" noValidate>
        <div className="flex items-center gap-3"><span className="grid h-16 w-16 place-items-center overflow-hidden rounded-full bg-primary-100 text-2xl font-bold text-primary-700">{p.logo_url ? <img src={p.logo_url} alt="Current logo" className="h-full w-full object-cover" /> : p.display_name.slice(0, 1)}</span>
          <div className="min-w-0 flex-1"><DropZone label="Upload logo / photo" hint="JPEG, PNG or WebP · up to 5 MB" accept="image/jpeg,image/png,image/webp" onFiles={logo.add} /></div></div>
        <UploadList items={logo.items} rejected={logo.rejected} onCancel={logo.cancel} onRetry={logo.retry} onDismiss={logo.dismiss} />
        <Field label="Display name" required error={errs.display_name}><Input value={v.display_name} onChange={(e) => set('display_name', e.target.value)} /></Field>
        <Field label="Seller type"><Select value={v.seller_type} onChange={(e) => set('seller_type', e.target.value)}><option value="individual">Individual</option><option value="business">Business / kennel / shop</option></Select></Field>
        {v.seller_type === 'business' && <div className="grid gap-3 sm:grid-cols-2"><Field label="Business name" error={errs.business_name}><Input value={v.business_name} onChange={(e) => set('business_name', e.target.value)} /></Field><Field label="GST number (optional)" error={errs.gst_number}><Input value={v.gst_number} onChange={(e) => set('gst_number', e.target.value)} /></Field></div>}
        <Field label="About you" error={errs.bio}><Textarea rows={4} maxLength={1000} value={v.bio} onChange={(e) => set('bio', e.target.value)} /></Field>
        <div className="grid gap-3 sm:grid-cols-2"><Field label="City" error={errs.city}><Input value={v.city} onChange={(e) => set('city', e.target.value)} /></Field><Field label="State" error={errs.state}><Input value={v.state} onChange={(e) => set('state', e.target.value)} /></Field></div>
        <fieldset className="space-y-3 rounded-ctl border border-line p-3"><legend className="px-1 text-sm font-medium">Private contact details</legend>
          <p className="text-xs text-muted">Only shown to buyers who unlock your contact on a listing — never on public pages.</p>
          <div className="grid gap-3 sm:grid-cols-2"><Field label="Phone" error={errs.contact_phone}><Input type="tel" value={v.contact_phone} onChange={(e) => set('contact_phone', e.target.value)} /></Field><Field label="WhatsApp" error={errs.contact_whatsapp}><Input type="tel" value={v.contact_whatsapp} onChange={(e) => set('contact_whatsapp', e.target.value)} /></Field></div>
          <Field label="Email" error={errs.contact_email}><Input type="email" value={v.contact_email} onChange={(e) => set('contact_email', e.target.value)} /></Field></fieldset>
        <Button type="submit" loading={save.isPending}>Save profile</Button>
      </form>
      <ProfileSecurityPage title={null} />
    </div>
  )
}

