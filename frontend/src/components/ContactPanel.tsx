import { useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { Lock, Mail, MessageCircle, Phone, ShieldAlert, Unlock } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import type { ContactInfo, EnquirySummary, ListingDetail } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { Button, LinkButton } from './ui/Button'
import { Alert } from './ui/Feedback'
import { Field, Textarea } from './ui/Form'
import { PlanPicker } from './Billing'

/** Seller contact is fetched ONLY from POST /pets/{id}/contact-unlock; nothing contact-related is in the listing payload. */
export function ContactPanel({ listing }: { listing: ListingDetail }) {
  const { user } = useAuth()
  const nav = useNavigate()
  const loc = useLocation()
  const qc = useQueryClient()
  const [contact, setContact] = useState<ContactInfo | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<{ code?: string; message: string } | null>(null)
  const [plansOpen, setPlansOpen] = useState(false)
  const [suggested, setSuggested] = useState<string[] | undefined>()
  const unavailable = listing.availability === 'sold' || listing.availability === 'unavailable'

  const unlock = async () => {
    if (!user) { nav(`/login?next=${encodeURIComponent(loc.pathname + loc.search)}`); return }
    setBusy(true); setError(null)
    try {
      const r = await api.post<ContactInfo>(`/pets/${listing.id}/contact-unlock`)
      setContact(r.data)
      qc.invalidateQueries({ predicate: (q) => typeof q.queryKey[0] === 'string' && (q.queryKey[0] as string).startsWith('/subscriptions') })
      qc.invalidateQueries({ queryKey: [`/pets/${listing.slug}`] })
    } catch (e) {
      if (isApiError(e) && e.code === 'membership_required') {
        const sp = (e.extra as { suggested_plans?: { id: string }[] } | undefined)?.suggested_plans
        setSuggested(Array.isArray(sp) ? sp.map((x) => x.id) : undefined)
        setPlansOpen(true)
      } else if (isApiError(e)) setError({ code: e.code, message: e.message })
      else setError({ message: 'Could not unlock contact details.' })
    } finally { setBusy(false) }
  }

  const wrongRole = user && user.account_type !== 'buyer'
  return (
    <section aria-labelledby="contact-h" className="card space-y-3 p-4">
      <h2 id="contact-h" className="text-lg">Contact seller</h2>
      {contact ? (
        <div className="space-y-2">
          <p className="flex items-center gap-1.5 text-sm font-semibold text-success"><Unlock className="h-4 w-4" aria-hidden />Contact unlocked · {contact.seller_name}</p>
          <ul className="space-y-1.5">
            {contact.phone && <li><a className="flex min-h-[44px] items-center gap-2 rounded-ctl border border-line px-3 text-sm font-medium hover:bg-warm" href={`tel:${contact.phone}`}><Phone className="h-4 w-4" aria-hidden />{contact.phone}</a></li>}
            {contact.whatsapp && <li><a className="flex min-h-[44px] items-center gap-2 rounded-ctl border border-line px-3 text-sm font-medium hover:bg-warm" href={`https://wa.me/${contact.whatsapp.replace(/\D/g, '')}`} target="_blank" rel="noopener noreferrer"><MessageCircle className="h-4 w-4" aria-hidden />WhatsApp {contact.whatsapp}</a></li>}
            {contact.email && <li><a className="flex min-h-[44px] items-center gap-2 rounded-ctl border border-line px-3 text-sm font-medium hover:bg-warm" href={`mailto:${contact.email}`}><Mail className="h-4 w-4" aria-hidden />{contact.email}</a></li>}
          </ul>
          {contact.remaining_unlocks != null && <p className="text-xs text-muted">{contact.remaining_unlocks} contact unlock{contact.remaining_unlocks === 1 ? '' : 's'} left on your plan.</p>}
          <p className="flex items-start gap-1.5 rounded-ctl bg-warm p-2 text-xs text-muted"><ShieldAlert className="mt-0.5 h-3.5 w-3.5 shrink-0" aria-hidden />Meet in a public place, see the pet in person, and never pay a full amount in advance. <Link to="/safety" className="underline">Safety guide</Link></p>
        </div>
      ) : (
        <div className="space-y-2">
          <div className="flex items-center gap-2 rounded-ctl bg-warm p-3 text-sm"><Lock className="h-4 w-4 shrink-0 text-accent-600" aria-hidden /><span>Seller phone, WhatsApp and email are <strong>locked</strong>. A buyer membership unlocks them.</span></div>
          {wrongRole ? <Alert tone="info">Contact unlocking is available to buyer accounts. Use a buyer account to contact this seller.</Alert> : (
            <Button variant="accent" className="w-full" size="lg" loading={busy} disabled={unavailable} onClick={unlock}>
              <Unlock className="h-4 w-4" aria-hidden />{listing.contact.unlocked ? 'Show seller contact' : 'Unlock seller contact'}
            </Button>
          )}
          {unavailable && <p className="text-xs text-muted">This pet is no longer available.</p>}
          {!user && <p className="text-center text-xs text-muted">You’ll be asked to log in first.</p>}
        </div>
      )}
      {error && (error.code === 'verification_required'
        ? <Alert tone="warning" title="Verify your email first" action={<LinkButton to="/verify-email" size="sm" variant="outline">Verify</LinkButton>}>{error.message}</Alert>
        : <Alert tone="danger">{error.message}</Alert>)}
      {user?.account_type === 'buyer' && <EnquiryForm listing={listing} />}
      <PlanPicker audience="buyer" suggestedIds={suggested} open={plansOpen} onOpenChange={setPlansOpen} onPurchased={() => { setPlansOpen(false); void unlock() }} />
    </section>
  )
}

function EnquiryForm({ listing }: { listing: ListingDetail }) {
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [done, setDone] = useState<EnquirySummary | null>(null)
  const [dupId, setDupId] = useState<string | null>(null)
  const [plansOpen, setPlansOpen] = useState(false)
  const submit = async (e?: React.FormEvent) => {
    e?.preventDefault()
    if (msg.trim().length < 5) { setErr('Write at least 5 characters.'); return }
    setBusy(true); setErr(null); setDupId(null)
    try { setDone((await api.post<EnquirySummary>(`/pets/${listing.id}/enquiries`, { message: msg.trim() })).data) } catch (e2) {
      if (isApiError(e2) && e2.code === 'membership_required') setPlansOpen(true)
      else if (isApiError(e2) && e2.status === 409) { setDupId(String((e2.extra as { enquiry_id?: string } | undefined)?.enquiry_id ?? '')); setErr(e2.message) }
      else setErr(isApiError(e2) ? e2.message : 'Could not send your enquiry.')
    } finally { setBusy(false) }
  }
  if (done) return <Alert tone="success" title="Enquiry sent">The seller has been notified. <Link className="font-semibold underline" to={`/buyer/enquiries/${done.id}`}>View conversation</Link></Alert>
  return (
    <form onSubmit={submit} className="space-y-2 border-t border-line pt-3" noValidate>
      <Field label="Send an enquiry" error={err && !dupId ? err : undefined} hint="Ask about health records, vaccination dates, viewing times and handover.">
        <Textarea value={msg} onChange={(e) => setMsg(e.target.value)} maxLength={2000} placeholder="Hi, is this pet still available?" />
      </Field>
      {dupId !== null && <Alert tone="info">{err} {dupId && <Link to={`/buyer/enquiries/${dupId}`} className="font-semibold underline">Open your conversation</Link>}</Alert>}
      <Button type="submit" className="w-full" loading={busy}>Send enquiry</Button>
      <PlanPicker audience="buyer" open={plansOpen} onOpenChange={setPlansOpen} onPurchased={() => { setPlansOpen(false); void submit() }} />
    </form>
  )
}
