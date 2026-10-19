import { useState } from 'react'
import { Pencil, Plus } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { Category, Plan, PlanInput } from '@/api/types'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Checkbox, Field, Input, Select, Switch, Textarea } from '@/components/ui/Form'
import { DataTable } from '@/components/ui/Table'
import { useToast } from '@/components/ui/Toast'
import { formatMoney, fromMinor, toMinor } from '@/lib/utils'

export function AdminCategories() {
  const toast = useToast()
  const q = useGet<Category[]>('/admin/categories')
  const [edit, setEdit] = useState<Partial<Category> | null>(null)
  const [json, setJson] = useState('{}')
  const [err, setErr] = useState('')
  const [breedFor, setBreedFor] = useState<Category | null>(null)
  const [breed, setBreed] = useState('')
  const save = useSend(() => {
    let rules: Record<string, unknown> = {}
    try { rules = JSON.parse(json || '{}') } catch { return Promise.reject(new Error('Jurisdiction rules must be valid JSON')) }
    const body = { name: edit?.name?.trim(), slug: edit?.slug?.trim() || undefined, icon: edit?.icon, description: edit?.description, sort_order: Number(edit?.sort_order ?? 0), is_active: edit?.is_active ?? true, requires_verified_seller: !!edit?.requires_verified_seller, jurisdiction_rules: rules }
    return edit?.id ? api.put(`/admin/categories/${edit.id}`, body) : api.post('/admin/categories', body)
  }, { invalidate: ['/admin/categories', '/categories'], onSuccess: () => { toast.success('Category saved'); setEdit(null) } })
  const addBreed = useSend(() => api.post(`/admin/categories/${breedFor?.id}/breeds`, { name: breed.trim(), is_active: true }), { invalidate: ['/admin/categories', '/categories'], onSuccess: () => { toast.success('Breed added'); setBreed('') } })
  const toggleBreed = useSend((b: { id: string; is_active: boolean }) => api.put(`/admin/breeds/${b.id}`, { is_active: b.is_active }), { invalidate: ['/admin/categories', '/categories'] })
  const open = (c: Partial<Category>) => { setEdit(c); setJson(JSON.stringify(c.jurisdiction_rules ?? {}, null, 2)); setErr('') }
  return (
    <div className="space-y-3">
      <PageHeader title="Categories & breeds" subtitle="Configure what can be listed and seller requirements" actions={<Button size="sm" onClick={() => open({ is_active: true, sort_order: 0 })}><Plus className="h-4 w-4" aria-hidden />New category</Button>} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading ? <Skeleton className="h-40 w-full" /> : (
        <ul className="space-y-2">{q.items?.map((c) => (
          <li key={c.id} className="card p-3"><div className="flex flex-wrap items-center gap-2"><h2 className="text-base">{c.name}</h2><span className="text-xs text-muted">/{c.slug}</span>{!c.is_active && <Badge tone="neutral">Inactive</Badge>}{c.requires_verified_seller && <Badge tone="secondary">Verified sellers only</Badge>}
            <div className="ml-auto flex gap-1.5"><Button variant="outline" size="sm" onClick={() => setBreedFor(c)}>Breeds ({c.breeds?.length ?? 0})</Button><Button variant="outline" size="sm" onClick={() => open(c)}><Pencil className="h-4 w-4" aria-hidden />Edit</Button></div></div></li>))}</ul>)}
      <Dialog open={!!edit} onOpenChange={(o) => !o && setEdit(null)} title={edit?.id ? 'Edit category' : 'New category'} footer={<><Button variant="outline" onClick={() => setEdit(null)}>Cancel</Button>
        <Button loading={save.isPending} onClick={() => { setErr(''); if (!edit?.name?.trim()) { setErr('Name is required'); return } save.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? (e.details[0] ? `${e.details[0].field}: ${e.details[0].message}` : e.message) : (e as Error).message) }) }}>Save</Button></>}>
        {edit && <div className="space-y-3">{err && <Alert tone="danger">{err}</Alert>}
          <Field label="Name" required><Input value={edit.name ?? ''} onChange={(e) => setEdit({ ...edit, name: e.target.value })} /></Field>
          <div className="grid grid-cols-2 gap-3"><Field label="Slug" hint="Auto-generated if empty"><Input value={edit.slug ?? ''} onChange={(e) => setEdit({ ...edit, slug: e.target.value })} /></Field><Field label="Icon" hint="dog, cat, bird, fish, rabbit…"><Input value={edit.icon ?? ''} onChange={(e) => setEdit({ ...edit, icon: e.target.value })} /></Field></div>
          <Field label="Description"><Input value={edit.description ?? ''} onChange={(e) => setEdit({ ...edit, description: e.target.value })} /></Field>
          <Field label="Sort order"><Input inputMode="numeric" value={edit.sort_order ?? 0} onChange={(e) => setEdit({ ...edit, sort_order: Number(e.target.value.replace(/\D/g, '')) })} /></Field>
          <Checkbox label="Active (visible to sellers and buyers)" checked={edit.is_active ?? true} onChange={(e) => setEdit({ ...edit, is_active: e.target.checked })} />
          <Checkbox label="Only verified sellers may list in this category" checked={!!edit.requires_verified_seller} onChange={(e) => setEdit({ ...edit, requires_verified_seller: e.target.checked })} />
          <Field label="Jurisdiction rules (JSON)" hint='e.g. {"IN-MH": {"allowed": true, "requires_verified_seller": true}}'><Textarea rows={5} className="font-mono text-xs" value={json} onChange={(e) => setJson(e.target.value)} /></Field></div>}
      </Dialog>
      <Dialog open={!!breedFor} onOpenChange={(o) => !o && setBreedFor(null)} title={`Breeds — ${breedFor?.name ?? ''}`}>
        {breedFor && <div className="space-y-3">
          <ul className="divide-y divide-line rounded-ctl border border-line">{(q.items?.find((c) => c.id === breedFor.id)?.breeds ?? []).map((b) => (
            <li key={b.id} className="flex items-center justify-between gap-2 px-3 py-1.5 text-sm"><span>{b.name}</span><Switch label={`${b.name} active`} checked={b.is_active} onChange={(v) => toggleBreed.mutate({ id: b.id, is_active: v }, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Failed') })} /></li>))}
            {!(q.items?.find((c) => c.id === breedFor.id)?.breeds?.length) && <li className="px-3 py-3 text-sm text-muted">No breeds yet.</li>}</ul>
          <form className="flex gap-2" onSubmit={(e) => { e.preventDefault(); if (breed.trim()) addBreed.mutate(undefined, { onError: (er) => toast.error(isApiError(er) ? er.message : 'Failed') }) }}>
            <div className="flex-1"><label htmlFor="nb" className="sr-only">New breed name</label><Input id="nb" placeholder="New breed name" value={breed} onChange={(e) => setBreed(e.target.value)} /></div><Button type="submit" loading={addBreed.isPending}>Add</Button></form></div>}
      </Dialog>
    </div>
  )
}

interface PlanDraft {
  id?: string; code: string; audience: 'buyer' | 'seller'; name: string; description: string; price: string; currency: string; promo_price: string; promo_starts: string; promo_ends: string
  billing_interval: 'month' | 'quarter' | 'year'; interval_count: string; tax_pct: string; trial_days: string; grace_days: string; renewal_window_days: string; auto_renew: boolean
  cancellation_policy: 'end_of_period' | 'immediate'; refund_window_days: string; refund_policy: string; is_active: boolean; sort_order: string; features: string
  listing_unl: boolean; listing_limit: string; unlock_unl: boolean; contact_unlocks: string; enq_unl: boolean; enquiries: string; featured_slots: string; analytics: boolean
}
const dt = (iso?: string | null) => (iso ? new Date(iso).toISOString().slice(0, 16) : '')
const blank = (): PlanDraft => ({ code: '', audience: 'buyer', name: '', description: '', price: '', currency: 'INR', promo_price: '', promo_starts: '', promo_ends: '', billing_interval: 'month', interval_count: '1', tax_pct: '18', trial_days: '0', grace_days: '0', renewal_window_days: '7', auto_renew: false, cancellation_policy: 'end_of_period', refund_window_days: '0', refund_policy: '', is_active: true, sort_order: '0', features: '', listing_unl: false, listing_limit: '5', unlock_unl: false, contact_unlocks: '10', enq_unl: false, enquiries: '20', featured_slots: '0', analytics: false })
export const planToDraft = (p: Plan): PlanDraft => ({
  id: p.id, code: p.code, audience: p.audience, name: p.name, description: p.description, price: fromMinor(p.price_minor), currency: p.currency, promo_price: p.promo_price_minor != null ? fromMinor(p.promo_price_minor) : '',
  promo_starts: dt(p.promo_starts_at), promo_ends: dt(p.promo_ends_at), billing_interval: p.billing_interval, interval_count: String(p.interval_count), tax_pct: String(p.tax_rate_bps / 100), trial_days: String(p.trial_days),
  grace_days: String(p.grace_days), renewal_window_days: String(p.renewal_window_days), auto_renew: p.auto_renew, cancellation_policy: p.cancellation_policy, refund_window_days: String(p.refund_window_days), refund_policy: p.refund_policy,
  is_active: p.is_active, sort_order: String(p.sort_order), features: (p.features ?? []).join('\n'),
  listing_unl: p.entitlements.listing_limit == null, listing_limit: String(p.entitlements.listing_limit ?? 5), unlock_unl: p.entitlements.contact_unlocks == null, contact_unlocks: String(p.entitlements.contact_unlocks ?? 10),
  enq_unl: p.entitlements.enquiries == null, enquiries: String(p.entitlements.enquiries ?? 20), featured_slots: String(p.entitlements.featured_slots ?? 0), analytics: !!p.entitlements.analytics,
})
export function draftToInput(d: PlanDraft): PlanInput {
  const n = (s: string) => Number(s || 0)
  const ent: Record<string, unknown> = d.audience === 'seller'
    ? { listing_limit: d.listing_unl ? null : n(d.listing_limit), analytics: d.analytics, featured_slots: n(d.featured_slots) }
    : { contact_unlocks: d.unlock_unl ? null : n(d.contact_unlocks), enquiries: d.enq_unl ? null : n(d.enquiries) }
  return {
    code: d.code.trim(), audience: d.audience, name: d.name.trim(), description: d.description, price_minor: toMinor(d.price), currency: d.currency.toUpperCase(),
    promo_price_minor: d.promo_price ? toMinor(d.promo_price) : null, promo_starts_at: d.promo_starts ? new Date(d.promo_starts).toISOString() : null, promo_ends_at: d.promo_ends ? new Date(d.promo_ends).toISOString() : null,
    billing_interval: d.billing_interval, interval_count: n(d.interval_count) || 1, tax_rate_bps: Math.round(Number(d.tax_pct || 0) * 100), trial_days: n(d.trial_days), grace_days: n(d.grace_days),
    renewal_window_days: n(d.renewal_window_days), auto_renew: d.auto_renew, cancellation_policy: d.cancellation_policy, refund_window_days: n(d.refund_window_days), refund_policy: d.refund_policy,
    is_active: d.is_active, sort_order: n(d.sort_order), features: d.features.split('\n').map((x) => x.trim()).filter(Boolean), entitlements: ent,
  }
}
export function validatePlan(d: PlanDraft): string | null {
  if (!/^[a-z0-9][a-z0-9_-]{1,40}$/.test(d.code.trim())) return 'Code: lowercase letters, numbers, - or _ (2–40 chars)'
  if (d.name.trim().length < 2) return 'Name is required'
  if (!/^\d+(\.\d{1,2})?$/.test(d.price)) return 'Enter a valid price in ₹'
  if (d.promo_price && !/^\d+(\.\d{1,2})?$/.test(d.promo_price)) return 'Enter a valid promotional price'
  if (d.promo_price && toMinor(d.promo_price) >= toMinor(d.price)) return 'Promotional price must be lower than the price'
  if (Number(d.tax_pct) < 0 || Number(d.tax_pct) > 100) return 'Tax must be between 0 and 100%'
  return null
}

export function AdminPlans() {
  const toast = useToast()
  const q = useGet<Plan[]>('/admin/plans')
  const [d, setD] = useState<PlanDraft | null>(null)
  const [err, setErr] = useState('')
  const save = useSend(() => { const body = draftToInput(d!); return d?.id ? api.put(`/admin/plans/${d.id}`, body) : api.post('/admin/plans', body) }, { invalidate: ['/admin/plans', '/subscription-plans'], onSuccess: () => { toast.success('Plan saved'); setD(null) } })
  const set = <K extends keyof PlanDraft>(k: K, v: PlanDraft[K]) => setD((x) => (x ? { ...x, [k]: v } : x))
  const num = (k: keyof PlanDraft) => (e: React.ChangeEvent<HTMLInputElement>) => set(k, e.target.value.replace(/[^\d.]/g, '') as never)
  return (
    <div className="space-y-3">
      <PageHeader title="Subscription plans" subtitle="Changes never alter subscriptions that are already active" actions={<Button size="sm" onClick={() => { setD(blank()); setErr('') }}><Plus className="h-4 w-4" aria-hidden />New plan</Button>} />
      <DataTable rows={q.items} loading={q.isLoading} error={q.error} onRetry={() => q.refetch()} rowKey={(p) => p.id} empty="No plans yet" onRowClick={(p) => { setD(planToDraft(p)); setErr('') }} columns={[
        { header: 'Plan', cell: (p) => <div><p className="font-medium">{p.name}</p><p className="text-xs text-muted">{p.code}</p></div> }, { header: 'Audience', cell: (p) => <Badge tone={p.audience === 'seller' ? 'secondary' : 'primary'}>{p.audience}</Badge> },
        { header: 'Price', cell: (p) => <span className="tnum">{formatMoney(p.effective_price_minor, p.currency)} / {p.interval_count > 1 ? p.interval_count + ' ' : ''}{p.billing_interval}</span> },
        { header: 'Tax', cell: (p) => `${p.tax_rate_bps / 100}%`, hideOnMobile: true }, { header: 'Status', cell: (p) => <Badge tone={p.is_active ? 'success' : 'neutral'}>{p.is_active ? 'Active' : 'Inactive'}</Badge> }]} />
      <Dialog open={!!d} onOpenChange={(o) => !o && setD(null)} size="lg" title={d?.id ? `Edit plan — ${d.name}` : 'New plan'} footer={<><Button variant="outline" onClick={() => setD(null)}>Cancel</Button>
        <Button loading={save.isPending} onClick={() => { const v = d ? validatePlan(d) : null; setErr(v ?? ''); if (v) return; save.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? (e.details.length ? e.details.map((x) => `${x.field}: ${x.message}`).join('; ') : e.message) : 'Could not save') }) }}>Save plan</Button></>}>
        {d && <div className="space-y-4">{err && <Alert tone="danger">{err}</Alert>}
          <fieldset className="grid gap-3 sm:grid-cols-2"><legend className="mb-1 text-sm font-semibold">Basics</legend>
            <Field label="Code" required hint="Unique, e.g. buyer-monthly"><Input value={d.code} onChange={(e) => set('code', e.target.value)} disabled={!!d.id} /></Field>
            <Field label="Audience"><Select value={d.audience} onChange={(e) => set('audience', e.target.value as 'buyer' | 'seller')} disabled={!!d.id}><option value="buyer">Buyer</option><option value="seller">Seller</option></Select></Field>
            <Field label="Name" required><Input value={d.name} onChange={(e) => set('name', e.target.value)} /></Field><Field label="Sort order"><Input inputMode="numeric" value={d.sort_order} onChange={num('sort_order')} /></Field>
            <Field label="Description" className="sm:col-span-2"><Input value={d.description} onChange={(e) => set('description', e.target.value)} /></Field></fieldset>
          <fieldset className="grid gap-3 sm:grid-cols-3"><legend className="mb-1 text-sm font-semibold">Pricing & billing</legend>
            <Field label="Price (₹, before tax)" required><Input inputMode="decimal" value={d.price} onChange={num('price')} /></Field><Field label="Currency"><Input value={d.currency} maxLength={3} onChange={(e) => set('currency', e.target.value)} /></Field><Field label="Tax %"><Input inputMode="decimal" value={d.tax_pct} onChange={num('tax_pct')} /></Field>
            <Field label="Interval"><Select value={d.billing_interval} onChange={(e) => set('billing_interval', e.target.value as PlanDraft['billing_interval'])}><option value="month">Month</option><option value="quarter">Quarter</option><option value="year">Year</option></Select></Field>
            <Field label="Interval count"><Input inputMode="numeric" value={d.interval_count} onChange={num('interval_count')} /></Field><Field label="Trial days"><Input inputMode="numeric" value={d.trial_days} onChange={num('trial_days')} /></Field>
            <Field label="Promo price (₹)"><Input inputMode="decimal" value={d.promo_price} onChange={num('promo_price')} /></Field><Field label="Promo starts"><Input type="datetime-local" value={d.promo_starts} onChange={(e) => set('promo_starts', e.target.value)} /></Field><Field label="Promo ends"><Input type="datetime-local" value={d.promo_ends} onChange={(e) => set('promo_ends', e.target.value)} /></Field></fieldset>
          <fieldset className="grid gap-3 sm:grid-cols-3"><legend className="mb-1 text-sm font-semibold">Lifecycle, cancellation & refunds</legend>
            <Field label="Grace period (days)"><Input inputMode="numeric" value={d.grace_days} onChange={num('grace_days')} /></Field><Field label="Renewal window (days)"><Input inputMode="numeric" value={d.renewal_window_days} onChange={num('renewal_window_days')} /></Field>
            <Field label="Cancellation"><Select value={d.cancellation_policy} onChange={(e) => set('cancellation_policy', e.target.value as PlanDraft['cancellation_policy'])}><option value="end_of_period">End of period</option><option value="immediate">Immediate</option></Select></Field>
            <Field label="Refund window (days)"><Input inputMode="numeric" value={d.refund_window_days} onChange={num('refund_window_days')} /></Field><Field label="Refund policy text" className="sm:col-span-2"><Input value={d.refund_policy} onChange={(e) => set('refund_policy', e.target.value)} /></Field>
            <Checkbox label="Auto-renew (reminders only; no stored mandates)" checked={d.auto_renew} onChange={(e) => set('auto_renew', e.target.checked)} /><Checkbox label="Plan is active" checked={d.is_active} onChange={(e) => set('is_active', e.target.checked)} /></fieldset>
          <fieldset className="space-y-2"><legend className="mb-1 text-sm font-semibold">Entitlements ({d.audience})</legend>
            {d.audience === 'seller' ? <div className="grid gap-3 sm:grid-cols-3">
              <div><Field label="Active listings"><Input inputMode="numeric" value={d.listing_limit} disabled={d.listing_unl} onChange={num('listing_limit')} /></Field><Checkbox label="Unlimited" checked={d.listing_unl} onChange={(e) => set('listing_unl', e.target.checked)} /></div>
              <Field label="Featured slots"><Input inputMode="numeric" value={d.featured_slots} onChange={num('featured_slots')} /></Field><Checkbox label="Includes analytics" checked={d.analytics} onChange={(e) => set('analytics', e.target.checked)} /></div>
              : <div className="grid gap-3 sm:grid-cols-2">
                <div><Field label="Contact unlocks"><Input inputMode="numeric" value={d.contact_unlocks} disabled={d.unlock_unl} onChange={num('contact_unlocks')} /></Field><Checkbox label="Unlimited" checked={d.unlock_unl} onChange={(e) => set('unlock_unl', e.target.checked)} /></div>
                <div><Field label="Enquiries"><Input inputMode="numeric" value={d.enquiries} disabled={d.enq_unl} onChange={num('enquiries')} /></Field><Checkbox label="Unlimited" checked={d.enq_unl} onChange={(e) => set('enq_unl', e.target.checked)} /></div></div>}</fieldset>
          <Field label="Marketing bullet points" hint="One per line"><Textarea rows={3} value={d.features} onChange={(e) => set('features', e.target.value)} /></Field>
        </div>}
      </Dialog>
    </div>
  )
}
