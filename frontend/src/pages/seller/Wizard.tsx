import { useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useForm, useWatch, type FieldPath } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { useQueryClient } from '@tanstack/react-query'
import { ArrowLeft, ArrowRight, ChevronLeft, ChevronRight, LocateFixed, Star, Trash2, Plus } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useCategories, useConfig, useGet } from '@/api/hooks'
import type { Image, ListingInput, ListingOwner } from '@/api/types'
import { Gallery } from '@/components/Gallery'
import { Price } from '@/components/Pet'
import { PageHeader } from '@/components/Section'
import { DropZone, UploadList, useUploads } from '@/components/Upload'
import { Button, LinkButton } from '@/components/ui/Button'
import { Alert, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Field, Input, Select, Textarea } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { listingSchema, WIZARD_STEPS, type ListingForm } from '@/lib/schemas'
import { formatAge, fromMinor, titleCase, toMinor } from '@/lib/utils'

const DEFAULTS: ListingForm = {
  title: '', category_id: '', breed_id: '', listing_type: 'sale', price: '', age_years: '', age_extra_months: '', gender: 'unknown', colour: '', description: '',
  vaccination_status: 'unspecified', vaccination_notes: '', health_notes: '', dewormed: '', microchipped: '', city: '', state: '', availability: 'available',
}
const triState = (v?: boolean | null): '' | 'yes' | 'no' => (v == null ? '' : v ? 'yes' : 'no')
const fromTri = (v: string): boolean | null => (v === '' ? null : v === 'yes')

export function listingToForm(l: ListingOwner): ListingForm {
  const m = l.age_months
  return {
    ...DEFAULTS, title: l.title, category_id: l.category.id, breed_id: l.breed?.id ?? '', listing_type: l.listing_type,
    price: l.listing_type === 'sale' && l.price_minor ? fromMinor(l.price_minor) : '', age_years: m != null ? String(Math.floor(m / 12)) : '', age_extra_months: m != null ? String(m % 12) : '',
    gender: l.gender, colour: l.colour ?? '', description: l.description ?? '', vaccination_status: (l.vaccination_status as ListingForm['vaccination_status']) ?? 'unspecified',
    vaccination_notes: l.vaccination_notes ?? '', health_notes: l.health_notes ?? '', dewormed: triState(l.dewormed), microchipped: triState(l.microchipped),
    city: l.city ?? '', state: l.state ?? '', availability: l.availability === 'reserved' ? 'reserved' : 'available',
  }
}
export function formToInput(v: ListingForm, attrs: { key: string; value: string }[], coords: { lat?: number; lng?: number }): ListingInput {
  const hasAge = v.age_years !== '' && v.age_years != null || v.age_extra_months !== '' && v.age_extra_months != null
  const attributes: Record<string, string> = {}
  for (const a of attrs) if (a.key && a.value) attributes[a.key] = a.value
  return {
    title: v.title.trim(), description: v.description ?? '', category_id: v.category_id, breed_id: v.breed_id || null, listing_type: v.listing_type,
    price_minor: v.listing_type === 'adoption' ? 0 : toMinor(v.price ?? ''), age_months: hasAge ? Number(v.age_years || 0) * 12 + Number(v.age_extra_months || 0) : null,
    gender: v.gender, colour: v.colour ?? '', vaccination_status: v.vaccination_status, vaccination_notes: v.vaccination_notes ?? '', health_notes: v.health_notes ?? '',
    dewormed: fromTri(v.dewormed), microchipped: fromTri(v.microchipped), city: v.city.trim(), state: v.state.trim(),
    lat: coords.lat ?? null, lng: coords.lng ?? null, attributes,
  }
}
const PRICE_STEP = WIZARD_STEPS.findIndex((x) => x.id === 'price')
const FIELD_MAP: Record<string, string> = { price_minor: 'price', age_months: 'age_years' }

function ImageManager({ listingId, images }: { listingId: string; images: Image[] }) {
  const qc = useQueryClient()
  const toast = useToast()
  const { items: cfg } = useConfig()
  const refresh = () => qc.invalidateQueries({ queryKey: [`/seller/listings/${listingId}`] })
  const maxImages = cfg?.max_images_per_listing ?? 8
  const maxMb = cfg?.max_image_mb ?? 8
  const up = useUploads({ path: `/seller/listings/${listingId}/images`, accept: ['image/jpeg', 'image/png', 'image/webp'], maxBytes: maxMb * 1048576, maxCount: maxImages, currentCount: images.length, onUploaded: refresh })
  const act = async (fn: () => Promise<unknown>, ok?: string) => { try { await fn(); await refresh(); if (ok) toast.success(ok) } catch (e) { toast.error(isApiError(e) ? e.message : 'Action failed') } }
  const move = (i: number, d: number) => {
    const ids = images.map((x) => x.id); const j = i + d
    if (j < 0 || j >= ids.length) return
    ;[ids[i], ids[j]] = [ids[j], ids[i]]
    void act(() => api.put(`/seller/listings/${listingId}/images/order`, { image_ids: ids }))
  }
  return (
    <div className="space-y-3">
      <DropZone label="Add photos" hint={`JPEG, PNG or WebP · up to ${maxMb} MB each · ${images.length}/${maxImages} used`} accept="image/jpeg,image/png,image/webp" multiple onFiles={up.add} disabled={images.length >= maxImages} />
      <UploadList items={up.items} rejected={up.rejected} onCancel={up.cancel} onRetry={up.retry} onDismiss={up.dismiss} />
      {images.length > 0 && (
        <ul className="grid grid-cols-2 gap-2 sm:grid-cols-3" aria-label="Listing photos">
          {images.map((im, i) => (
            <li key={im.id} className="card overflow-hidden">
              <div className="relative aspect-[4/3] bg-warm"><img src={im.thumb} alt={`Photo ${i + 1}`} className="h-full w-full object-cover" />
                {im.is_cover && <span className="absolute left-1.5 top-1.5 rounded-chip bg-accent-500 px-1.5 py-0.5 text-[11px] font-bold text-white">Cover</span>}</div>
              <div className="flex items-center justify-between gap-1 p-1">
                <div className="flex">
                  <Button variant="ghost" size="icon" className="h-9 w-9" aria-label={`Move photo ${i + 1} earlier`} disabled={i === 0} onClick={() => move(i, -1)}><ChevronLeft className="h-4 w-4" /></Button>
                  <Button variant="ghost" size="icon" className="h-9 w-9" aria-label={`Move photo ${i + 1} later`} disabled={i === images.length - 1} onClick={() => move(i, 1)}><ChevronRight className="h-4 w-4" /></Button>
                </div>
                <div className="flex">
                  <Button variant="ghost" size="icon" className="h-9 w-9" aria-label={`Make photo ${i + 1} the cover`} disabled={im.is_cover} onClick={() => act(() => api.put(`/seller/listings/${listingId}/images/${im.id}/cover`), 'Cover updated')}><Star className="h-4 w-4" /></Button>
                  <Button variant="ghost" size="icon" className="h-9 w-9 text-danger" aria-label={`Delete photo ${i + 1}`} onClick={() => act(() => api.del(`/seller/listings/${listingId}/images/${im.id}`), 'Photo deleted')}><Trash2 className="h-4 w-4" /></Button>
                </div>
              </div>
            </li>))}
        </ul>)}
    </div>
  )
}

export default function ListingWizard() {
  const { id: routeId } = useParams()
  const nav = useNavigate()
  const toast = useToast()
  const qc = useQueryClient()
  const cats = useCategories()
  const [listingId, setListingId] = useState<string | undefined>(routeId)
  const existing = useGet<ListingOwner>(listingId ? `/seller/listings/${listingId}` : null, undefined, { refetchOnWindowFocus: false })
  const [stepIdx, setStepIdx] = useState(0)
  const [busy, setBusy] = useState(false)
  const [banner, setBanner] = useState<{ tone: 'danger' | 'warning'; msg: string; link?: boolean } | null>(null)
  const [attrs, setAttrs] = useState<{ key: string; value: string }[]>([])
  const [coords, setCoords] = useState<{ lat?: number; lng?: number }>({})
  const hydrated = useRef(false)
  const form = useForm<ListingForm>({ resolver: zodResolver(listingSchema), mode: 'onTouched', defaultValues: DEFAULTS })
  const { register, trigger, getValues, control, reset, setError, setValue, formState: { errors } } = form
  const l = existing.items

  useEffect(() => {
    if (l && !hydrated.current) { hydrated.current = true; reset(listingToForm(l)); setAttrs(Object.entries(l.attributes ?? {}).map(([key, value]) => ({ key, value }))) }
  }, [l, reset])

  const step = WIZARD_STEPS[stepIdx]
  const catId = useWatch({ control, name: 'category_id' })
  const type = useWatch({ control, name: 'listing_type' })
  const cat = cats.items?.find((c) => c.id === catId)
  const breeds = useMemo(() => cat?.breeds?.filter((b) => b.is_active) ?? [], [cat])

  const fail = (e: unknown) => {
    if (!isApiError(e)) { setBanner({ tone: 'danger', msg: 'Something went wrong. Please try again.' }); return }
    if (e.code === 'subscription_required' || e.code === 'limit_reached') { setBanner({ tone: 'warning', msg: e.message, link: true }); return }
    let rest = e.details.length === 0
    for (const d of e.details) { const f = FIELD_MAP[d.field] ?? d.field; if (f in DEFAULTS) setError(f as FieldPath<ListingForm>, { type: 'server', message: d.message }); else rest = true }
    setBanner({ tone: 'danger', msg: rest ? e.message : 'Please fix the highlighted fields.' })
  }

  const saveDraft = async (): Promise<ListingOwner | null> => {
    const body = formToInput(getValues(), attrs, coords)
    setBusy(true); setBanner(null)
    try {
      const r = listingId ? await api.put<ListingOwner>(`/seller/listings/${listingId}`, body) : await api.post<ListingOwner>('/seller/listings', body)
      hydrated.current = true // the form already holds these values; never overwrite it from the server copy
      setListingId(r.data.id)
      qc.setQueryData([`/seller/listings/${r.data.id}`, {}], r)
      qc.invalidateQueries({ queryKey: ['/seller/listings'] })
      return r.data
    } catch (e) { fail(e); return null } finally { setBusy(false) }
  }

  const next = async () => {
    setBanner(null)
    if (step.id === 'photos' && !(l?.images?.length)) { setBanner({ tone: 'warning', msg: 'Add at least one photo before continuing.' }); return }
    if (!(await trigger(step.fields as FieldPath<ListingForm>[]))) return
    // The API rejects a sale listing without a price (even as a draft), so the draft is created once the price step is done.
    if ((listingId || stepIdx >= PRICE_STEP) && step.id !== 'photos' && step.id !== 'preview') { const r = await saveDraft(); if (!r) return }
    if (step.id === 'availability' && listingId) {
      try { await api.patch(`/seller/listings/${listingId}/availability`, { availability: getValues('availability') }) } catch (e) { fail(e); return }
    }
    if (step.id === 'availability' || step.id === 'photos') await qc.invalidateQueries({ queryKey: [`/seller/listings/${listingId}`] })
    setStepIdx((i) => Math.min(i + 1, WIZARD_STEPS.length - 1))
    window.scrollTo({ top: 0 })
  }
  const saveExit = async () => { if (!(await trigger(['title', 'category_id', 'listing_type', 'price']))) { setBanner({ tone: 'warning', msg: 'Add a title, species and price (or choose adoption) to save a draft.' }); return }; if (await saveDraft()) { toast.success('Draft saved'); nav('/seller/listings') } }
  const submit = async () => {
    setBusy(true); setBanner(null)
    try {
      const saved = await saveDraft(); if (!saved) return
      await api.post(`/seller/listings/${saved.id}/submit`)
      qc.invalidateQueries({ predicate: (q) => typeof q.queryKey[0] === 'string' && (q.queryKey[0] as string).startsWith('/seller') })
      setStepIdx(WIZARD_STEPS.length)
    } catch (e) { fail(e); await qc.invalidateQueries({ queryKey: [`/seller/listings/${listingId}`] }) } finally { setBusy(false) }
  }
  const locate = () => navigator.geolocation?.getCurrentPosition((p) => { setCoords({ lat: Math.round(p.coords.latitude * 1e4) / 1e4, lng: Math.round(p.coords.longitude * 1e4) / 1e4 }); toast.success('Location captured') }, () => toast.error('Could not read your location. Enter city and state instead.'), { timeout: 8000 })

  if (routeId && existing.isLoading) return <Skeleton className="h-96 w-full" />
  if (routeId && existing.error) return <ErrorState error={existing.error} onRetry={() => existing.refetch()} />

  if (stepIdx >= WIZARD_STEPS.length) {
    return (
      <div className="mx-auto max-w-lg space-y-3 py-6 text-center">
        <h1 className="text-2xl">Submitted for moderation</h1>
        <p className="text-muted">Our team reviews every listing before it goes live. You’ll be notified when it’s approved or if changes are needed.</p>
        <div className="flex justify-center gap-2"><LinkButton to="/seller/listings?status=pending">View pending listings</LinkButton><LinkButton to="/seller/listings/new" variant="outline" onClick={() => window.location.assign('/seller/listings/new')}>Add another</LinkButton></div>
      </div>
    )
  }
  const err = (k: keyof ListingForm) => errors[k]?.message as string | undefined
  const values = getValues()
  const editing = !!routeId
  const missing = l?.missing_for_submission ?? []
  return (
    <div className="mx-auto max-w-2xl space-y-3">
      <PageHeader title={editing ? 'Edit listing' : 'Add a pet'} subtitle={`Step ${stepIdx + 1} of ${WIZARD_STEPS.length} · ${step.title}`} actions={listingId ? <Button variant="outline" size="sm" onClick={saveExit} loading={busy}>Save & exit</Button> : undefined} />
      <div className="h-1.5 overflow-hidden rounded-full bg-line" role="progressbar" aria-label="Listing progress" aria-valuemin={1} aria-valuemax={WIZARD_STEPS.length} aria-valuenow={stepIdx + 1}><div className="h-full rounded-full bg-primary-500 transition-all" style={{ width: `${((stepIdx + 1) / WIZARD_STEPS.length) * 100}%` }} /></div>
      {editing && l?.status === 'approved' && <Alert tone="info">Changing the content of a live listing sends it back to moderation until it’s re-approved.</Alert>}
      {banner && <Alert tone={banner.tone} action={banner.link ? <LinkButton to="/seller/membership" size="sm" variant="outline">Plans</LinkButton> : undefined}>{banner.msg}</Alert>}
      <form onSubmit={(e) => { e.preventDefault(); void next() }} className="card space-y-4 p-4" noValidate aria-label={step.title}>
        {step.id === 'basic' && <Field label="Listing title" required error={err('title')} hint="e.g. “Labrador puppy, 3 months, vaccinated”"><Input {...register('title')} maxLength={140} /></Field>}
        {step.id === 'species' && <>
          <Field label="Species / category" required error={err('category_id')}><Select {...register('category_id', { onChange: () => setValue('breed_id', '') })}><option value="">Choose…</option>{cats.items?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}</Select></Field>
          {cat?.requires_verified_seller && <Alert tone="info">Listings in {cat.name} can only be published by verified sellers.</Alert>}
          <Field label="Breed" error={err('breed_id')} hint={!catId ? 'Choose a species first' : breeds.length ? undefined : 'No breeds configured — leave blank'}><Select {...register('breed_id')} disabled={!breeds.length}><option value="">Not specified / mixed</option>{breeds.map((b) => <option key={b.id} value={b.id}>{b.name}</option>)}</Select></Field></>}
        {step.id === 'age' && <>
          <div className="grid grid-cols-2 gap-3"><Field label="Age — years" error={err('age_years')}><Input inputMode="numeric" {...register('age_years')} /></Field><Field label="Plus months" error={err('age_extra_months')}><Input inputMode="numeric" {...register('age_extra_months')} /></Field></div>
          <Field label="Gender"><Select {...register('gender')}><option value="unknown">Not sure</option><option value="male">Male</option><option value="female">Female</option></Select></Field>
          <Field label="Colour / markings"><Input {...register('colour')} /></Field></>}
        {step.id === 'price' && <>
          <Field label="Listing type"><Select {...register('listing_type')}><option value="sale">For sale</option><option value="adoption">Adoption (free)</option></Select></Field>
          {type === 'sale' ? <Field label="Price (₹)" required error={err('price')}><Input inputMode="decimal" placeholder="15000" {...register('price')} /></Field> : <Alert tone="info">Adoption listings are free. Do not ask for payment other than reasonable, disclosed vet or vaccination costs.</Alert>}</>}
        {step.id === 'desc' && <>
          <Field label="Description" error={err('description')} hint="Temperament, diet, living conditions, what’s included. Be honest."><Textarea rows={6} maxLength={5000} {...register('description')} /></Field>
          <fieldset className="space-y-2"><legend className="text-sm font-medium">Extra details (optional)</legend>
            {attrs.map((a, i) => (
              <div key={i} className="flex gap-2"><Input aria-label={`Detail ${i + 1} name`} placeholder="e.g. temperament" value={a.key} onChange={(e) => setAttrs((xs) => xs.map((x, k) => (k === i ? { ...x, key: e.target.value.toLowerCase().replace(/[^a-z0-9_]/g, '_').slice(0, 40) } : x)))} />
                <Input aria-label={`Detail ${i + 1} value`} placeholder="e.g. friendly" value={a.value} maxLength={200} onChange={(e) => setAttrs((xs) => xs.map((x, k) => (k === i ? { ...x, value: e.target.value } : x)))} />
                <Button variant="ghost" size="icon" aria-label={`Remove detail ${i + 1}`} onClick={() => setAttrs((xs) => xs.filter((_, k) => k !== i))}><Trash2 className="h-4 w-4" /></Button></div>))}
            {attrs.length < 8 && <Button variant="outline" size="sm" onClick={() => setAttrs((xs) => [...xs, { key: '', value: '' }])}><Plus className="h-4 w-4" aria-hidden />Add detail</Button>}</fieldset></>}
        {step.id === 'health' && <>
          <Alert tone="info">Share only what you can document. PETORA shows these as seller-declared and does not verify them.</Alert>
          <Field label="Vaccination status"><Select {...register('vaccination_status')}><option value="unspecified">Not stated</option><option value="none">Not vaccinated</option><option value="partial">Partly vaccinated</option><option value="complete">Fully vaccinated</option></Select></Field>
          <Field label="Vaccination details" error={err('vaccination_notes')} hint="Vaccines given, dates, vet name"><Textarea rows={3} maxLength={1000} {...register('vaccination_notes')} /></Field>
          <div className="grid grid-cols-2 gap-3"><Field label="Dewormed"><Select {...register('dewormed')}><option value="">Not stated</option><option value="yes">Yes</option><option value="no">No</option></Select></Field>
            <Field label="Microchipped"><Select {...register('microchipped')}><option value="">Not stated</option><option value="yes">Yes</option><option value="no">No</option></Select></Field></div>
          <Field label="Other health notes" error={err('health_notes')}><Textarea rows={3} maxLength={1000} {...register('health_notes')} /></Field></>}
        {step.id === 'photos' && (listingId ? <ImageManager listingId={listingId} images={l?.images ?? []} /> : <Alert tone="warning">Save the earlier steps first.</Alert>)}
        {step.id === 'location' && <>
          <div className="grid grid-cols-2 gap-3"><Field label="City" required error={err('city')}><Input autoComplete="address-level2" {...register('city')} /></Field><Field label="State" required error={err('state')}><Input autoComplete="address-level1" {...register('state')} /></Field></div>
          <Button variant="secondary" size="sm" onClick={locate}><LocateFixed className="h-4 w-4" aria-hidden />{coords.lat ? 'Location captured' : 'Add map location (improves “near me” results)'}</Button>
          <p className="text-xs text-muted">Buyers only see your city and state, never your exact address.</p></>}
        {step.id === 'availability' && <>
          <Field label="Availability"><Select {...register('availability')}><option value="available">Available</option><option value="reserved">Reserved</option></Select></Field>
          <p className="text-xs text-muted">You can mark the pet sold or unavailable any time from your listings.</p></>}
        {step.id === 'preview' && (
          <div className="space-y-3">
            {l && <Gallery images={l.images} title={values.title} icon={cat?.slug} />}
            <h2 className="text-xl">{values.title}</h2>
            <p className="flex flex-wrap items-center gap-x-3 text-sm text-muted"><Price minor={type === 'adoption' ? 0 : toMinor(values.price ?? '')} currency="INR" type={type} className="text-lg" />
              <span>{cat?.name}{values.breed_id ? ` · ${breeds.find((b) => b.id === values.breed_id)?.name ?? ''}` : ''}</span>
              <span>{formatAge(values.age_years || values.age_extra_months ? Number(values.age_years || 0) * 12 + Number(values.age_extra_months || 0) : null)}</span><span>{titleCase(values.gender)}</span><span>{[values.city, values.state].filter(Boolean).join(', ')}</span></p>
            {values.description && <p className="whitespace-pre-line text-sm">{values.description}</p>}
            <p className="text-sm"><strong>Vaccination:</strong> {values.vaccination_status === 'unspecified' ? 'Not stated' : titleCase(values.vaccination_status)}</p>
            {missing.length > 0 && <Alert tone="warning" title="Before you can submit">{<ul className="list-disc pl-5">{missing.map((m) => <li key={m}>{m}</li>)}</ul>}</Alert>}
            <p className="text-xs text-muted">By submitting you confirm the details are accurate and that you comply with the laws that apply to selling animals in your state. Submitted listings are reviewed by moderators before going live.</p>
          </div>)}
        <div className="flex items-center justify-between gap-2 border-t border-line pt-3">
          <Button variant="outline" disabled={stepIdx === 0 || busy} onClick={() => setStepIdx((i) => Math.max(0, i - 1))}><ArrowLeft className="h-4 w-4" aria-hidden />Back</Button>
          {step.id === 'preview' ? <Button variant="accent" loading={busy} onClick={submit}>{editing && l?.status === 'approved' ? 'Save & resubmit' : 'Submit for moderation'}</Button>
            : <Button type="submit" loading={busy}>Next<ArrowRight className="h-4 w-4" aria-hidden /></Button>}
        </div>
      </form>
      <p className="text-center text-xs text-muted"><Link to="/seller/listings" className="underline">Cancel and return to listings</Link></p>
    </div>
  )
}
