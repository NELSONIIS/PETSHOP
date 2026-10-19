import { useState, type FormEvent } from 'react'
import { ChevronDown } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet } from '@/api/hooks'
import type { LegalPage as LegalPageT } from '@/api/types'
import { Markdown } from '@/lib/markdown'
import { Button } from '@/components/ui/Button'
import { Alert, Skeleton } from '@/components/ui/Feedback'
import { Field, Input, Textarea } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { cn, formatDate } from '@/lib/utils'

export const DEFAULT_FAQ = [
  { q: 'Is browsing free?', a: 'Yes. Browsing and searching pets is free. A buyer membership is only needed to unlock seller contact details and send enquiries.' },
  { q: 'What does “Verified seller” mean?', a: 'PETORA staff reviewed the seller’s identity or business documents. It does not mean the seller is licensed or that a pet has been medically verified.' },
  { q: 'Does a membership guarantee I will get a pet?', a: 'No. A membership gives you access to contact details and enquiries only. It does not guarantee that a pet is available or that a sale will happen.' },
  { q: 'How do I stay safe when buying?', a: 'Meet in person in a public place, ask for vaccination records, have a vet check the pet, and never pay the full amount in advance. See our safety guide.' },
  { q: 'Can I get a refund on a membership?', a: 'Refunds follow the refund policy shown on each plan and on the Refund policy page.' },
  { q: 'How do I report a suspicious listing?', a: 'Use the “Report” button on any listing. Our moderators review every report.' },
]

interface FaqItem { q: string; a: string }
function normalizeFaq(raw: unknown): FaqItem[] {
  const arr = Array.isArray(raw) ? raw : (raw as { items?: unknown; faqs?: unknown } | null)?.items ?? (raw as { faqs?: unknown } | null)?.faqs
  if (!Array.isArray(arr)) return []
  return arr.map((x) => ({ q: String(x.q ?? x.question ?? ''), a: String(x.a ?? x.answer ?? '') })).filter((x) => x.q && x.a)
}

export function FaqList({ limit, level = 3 }: { limit?: number; level?: 2 | 3 }) {
  const H = level === 2 ? 'h2' : 'h3'
  const q = useGet<unknown>('/content/faq', undefined, { retry: false })
  const [open, setOpen] = useState<number | null>(null)
  const fromApi = normalizeFaq(q.items)
  const items = (fromApi.length ? fromApi : DEFAULT_FAQ).slice(0, limit)
  return (
    <div className="card divide-y divide-line">
      {items.map((it, i) => (
        <div key={it.q}>
          <H className="text-base">
            <button type="button" aria-expanded={open === i} aria-controls={`faq-${i}`} onClick={() => setOpen(open === i ? null : i)} className="flex min-h-[52px] w-full items-center justify-between gap-3 px-4 py-2 text-left font-semibold">
              {it.q}<ChevronDown className={cn('h-4 w-4 shrink-0 transition-transform', open === i && 'rotate-180')} aria-hidden />
            </button>
          </H>
          <div id={`faq-${i}`} role="region" hidden={open !== i} className="px-4 pb-3 text-sm text-muted">{it.a}</div>
        </div>
      ))}
    </div>
  )
}

export function FaqPage() {
  return <Shell title="Frequently asked questions"><FaqList level={2} /></Shell>
}

export function Shell({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <div className="container-page max-w-3xl py-6 md:py-10">
      <h1 className="text-3xl">{title}</h1>
      {subtitle && <p className="mt-1 text-sm text-muted">{subtitle}</p>}
      <div className="mt-4">{children}</div>
    </div>
  )
}

export function LegalPage({ slug, title, before }: { slug: string; title: string; before?: React.ReactNode }) {
  const q = useGet<LegalPageT>(`/legal/${slug}`, undefined, { retry: false })
  return (
    <Shell title={q.items?.title ?? title} subtitle={q.items ? `Version ${q.items.version} · updated ${formatDate(q.items.published_at)}` : undefined}>
      {before}
      {q.isLoading ? <div className="space-y-2"><Skeleton className="h-5 w-full" /><Skeleton className="h-5 w-5/6" /><Skeleton className="h-5 w-4/6" /></div>
        : q.items ? <article className="text-base"><Markdown source={q.items.body_md} /></article>
        : <Alert tone="info">This page hasn’t been published yet. Please check back soon.</Alert>}
    </Shell>
  )
}

const tips = [
  ['Meet in person', 'See the pet and its living conditions before any payment. Choose a public place or visit the seller’s premises with a friend.'],
  ['Ask for records', 'Request vaccination cards, deworming records and any vet documents. A “Verified seller” badge is not a health certificate.'],
  ['Never prepay in full', 'Avoid paying the entire amount in advance. Beware of sellers who refuse video calls or in-person visits.'],
  ['Check welfare', 'Healthy pets are alert, clean and active. Walk away if the animal looks unwell or the seller cannot say where it was bred.'],
  ['Know the rules', 'Rules for breeding, sale and transport of animals differ by state. Sellers are responsible for complying with them.'],
  ['Adopt, don’t shop', 'Consider adoption. Many wonderful pets need a home.'],
]
export function SafetyPage() {
  return (
    <LegalPage slug="safety" title="Safety & responsible ownership" before={
      <div className="mb-6 grid gap-3 sm:grid-cols-2">
        {tips.map(([t, d]) => <div key={t} className="card p-4"><h2 className="text-base">{t}</h2><p className="mt-1 text-sm text-muted">{d}</p></div>)}
      </div>} />
  )
}

export function SupportPage() {
  const toast = useToast()
  const [busy, setBusy] = useState(false)
  const [sent, setSent] = useState(false)
  const [errs, setErrs] = useState<Record<string, string>>({})
  const submit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    const body = { name: String(f.get('name') ?? '').trim(), email: String(f.get('email') ?? '').trim(), subject: String(f.get('subject') ?? '').trim(), message: String(f.get('message') ?? '').trim() }
    const er: Record<string, string> = {}
    if (body.name.length < 2) er.name = 'Enter your name'
    if (!/^\S+@\S+\.\S+$/.test(body.email)) er.email = 'Enter a valid email'
    if (body.message.length < 10) er.message = 'Tell us a little more (at least 10 characters)'
    setErrs(er)
    if (Object.keys(er).length) return
    setBusy(true)
    try { await api.post('/support/contact', body); setSent(true) } catch (x) {
      if (isApiError(x) && x.details.length) setErrs(Object.fromEntries(x.details.map((d) => [d.field, d.message])))
      else toast.error(isApiError(x) ? x.message : 'Could not send your message')
    } finally { setBusy(false) }
  }
  return (
    <Shell title="Contact support" subtitle="We usually reply within one working day.">
      {sent ? <Alert tone="success" title="Message sent">Thanks — our team will email you shortly.</Alert> : (
        <form onSubmit={submit} className="card space-y-3 p-4" noValidate>
          <Field label="Your name" required error={errs.name}><Input name="name" autoComplete="name" /></Field>
          <Field label="Email" required error={errs.email}><Input name="email" type="email" autoComplete="email" /></Field>
          <Field label="Subject" error={errs.subject}><Input name="subject" /></Field>
          <Field label="How can we help?" required error={errs.message}><Textarea name="message" rows={5} /></Field>
          <Button type="submit" loading={busy} className="w-full sm:w-auto">Send message</Button>
          <p className="text-xs text-muted">To report a listing, use the Report button on the listing page so moderators can act on it.</p>
        </form>
      )}
    </Shell>
  )
}
