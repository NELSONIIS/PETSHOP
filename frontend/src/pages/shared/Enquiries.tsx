import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { Ban, Flag, Send } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { EnquiryDetail, EnquirySummary } from '@/api/types'
import { PlaceholderImage } from '@/components/Pet'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { ConfirmDialog, Dialog } from '@/components/ui/Dialog'
import { Alert, EmptyState, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Field, Select, Textarea } from '@/components/ui/Form'
import { Pagination } from '@/components/ui/Pagination'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { cn, formatDate, timeAgo, titleCase } from '@/lib/utils'

export function EnquiryCard({ e, role }: { e: EnquirySummary; role: 'buyer' | 'seller' }) {
  return (
    <li>
      <Link to={`/${role}/enquiries/${e.id}`} className="card flex gap-3 p-3 transition-colors hover:border-primary-300">
        <div className="h-14 w-[72px] shrink-0 overflow-hidden rounded-chip bg-warm">
          {e.listing.cover ? <img src={e.listing.cover.thumb} alt="" loading="lazy" className="h-full w-full object-cover" /> : <PlaceholderImage className="h-full w-full" />}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2"><h3 className="truncate text-base">{e.listing.title}</h3><span className="shrink-0 text-xs text-muted">{timeAgo(e.last_message_at)}</span></div>
          <p className="truncate text-sm text-muted"><span className="font-medium text-ink">{e.counterparty.name}</span> · {e.last_message}</p>
          <div className="mt-1 flex items-center gap-2"><StatusBadge status={e.status} />{e.unread > 0 && <span className="rounded-full bg-accent-500 px-2 py-0.5 text-xs font-bold text-white tnum">{e.unread} new</span>}</div>
        </div>
      </Link>
    </li>
  )
}

export function EnquiryList({ role }: { role: 'buyer' | 'seller' }) {
  const [sp, setSp] = useSearchParams()
  const status = sp.get('status') ?? ''
  const page = Number(sp.get('page')) || 1
  const q = useGet<EnquirySummary[]>(`/${role}/enquiries`, { status: status || undefined, page, per_page: 15 }, { keepPrevious: true })
  const set = (k: string, v: string) => { const n = new URLSearchParams(sp); if (v) n.set(k, v); else n.delete(k); if (k !== 'page') n.delete('page'); setSp(n) }
  return (
    <div className="space-y-3">
      <PageHeader title={role === 'buyer' ? 'My enquiries' : 'Enquiry inbox'} subtitle={role === 'buyer' ? 'Conversations with sellers' : 'Buyers who contacted you about your pets'} />
      <TabBar label="Filter by status" value={status} onChange={(v) => set('status', v)}
        items={[{ value: '', label: 'All' }, { value: 'pending', label: 'Pending' }, { value: 'viewed', label: 'Viewed' }, { value: 'responded', label: 'Responded' }, { value: 'closed', label: 'Closed' }]} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} />
        : q.isLoading ? <div className="space-y-2">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-20 w-full" />)}</div>
        : !q.items?.length ? <EmptyState title="No enquiries yet" body={role === 'buyer' ? 'Unlock a seller’s contact and send an enquiry from any pet page.' : 'When buyers send enquiries about your listings, they’ll appear here.'}
          action={role === 'buyer' ? <Link to="/pets" className="font-semibold text-primary-600 underline">Browse pets</Link> : undefined} />
        : <ul className="space-y-2">{q.items.map((e) => <EnquiryCard key={e.id} e={e} role={role} />)}</ul>}
      <Pagination meta={q.meta} onPage={(p) => set('page', String(p))} />
    </div>
  )
}

export function EnquiryThread({ role }: { role: 'buyer' | 'seller' }) {
  const { id = '' } = useParams()
  const nav = useNavigate()
  const toast = useToast()
  const q = useGet<EnquiryDetail>(`/${role}/enquiries/${id}`, undefined, { refetchInterval: 15_000, retry: (n, e) => !(isApiError(e) && e.status === 404) && n < 2 })
  const [body, setBody] = useState('')
  const [closeOpen, setCloseOpen] = useState(false)
  const [reportOpen, setReportOpen] = useState(false)
  const [blockOpen, setBlockOpen] = useState(false)
  const end = useRef<HTMLDivElement>(null)
  const e = q.items
  useEffect(() => { end.current?.scrollIntoView({ block: 'end' }) }, [e?.messages.length])
  const send = useSend((text: string) => api.post(`/${role}/enquiries/${id}/messages`, { body: text }), {
    invalidate: [`/${role}/enquiries`, '/notifications', `/${role}/dashboard`], onSuccess: () => setBody(''),
  })
  const block = useSend((userId: string) => api.post('/blocks', { user_id: userId }), { invalidate: ['/blocks'], onSuccess: () => { setBlockOpen(false); toast.success('User blocked. They can no longer message you.') } })
  const close = useSend(() => api.post(`/${role}/enquiries/${id}/close`), { invalidate: [`/${role}/enquiries`], onSuccess: () => { setCloseOpen(false); toast.success('Enquiry closed') } })
  if (q.isLoading) return <Skeleton className="h-72 w-full" />
  if (q.error) return isApiError(q.error) && q.error.status === 404 ? <EmptyState title="Enquiry not found" action={<Link to={`/${role}/enquiries`} className="font-semibold text-primary-600 underline">Back to enquiries</Link>} /> : <ErrorState error={q.error} onRetry={() => q.refetch()} />
  if (!e) return null
  const closed = e.status === 'closed'
  const submit = (ev: React.FormEvent) => { ev.preventDefault(); const t = body.trim(); if (!t) return; send.mutate(t, { onError: (er) => toast.error(isApiError(er) ? er.message : 'Message not sent') }) }
  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-3">
      <PageHeader title={e.listing.title} subtitle={`${role === 'buyer' ? 'Seller' : 'Buyer'}: ${e.counterparty.name} · started ${formatDate(e.created_at)}`}
        actions={<><Button variant="outline" size="sm" onClick={() => nav(`/pets/${e.listing.slug}`)}>View listing</Button>
          <Button variant="ghost" size="sm" onClick={() => setReportOpen(true)}><Flag className="h-4 w-4" aria-hidden />Report</Button>
          {e.counterparty.user_id && <Button variant="ghost" size="sm" onClick={() => setBlockOpen(true)}><Ban className="h-4 w-4" aria-hidden />Block user</Button>}
          {!closed && <Button variant="outline" size="sm" onClick={() => setCloseOpen(true)}>Close</Button>}</>} />
      <div className="flex flex-wrap items-center gap-2 text-sm"><StatusBadge status={e.status} />{role === 'buyer' && e.contact_unlocked && <span className="text-success">Contact unlocked</span>}
        {e.first_response_at && <span className="text-muted">First reply {timeAgo(e.first_response_at)}</span>}</div>
      <div className="card flex max-h-[55dvh] min-h-[220px] flex-col gap-2 overflow-y-auto p-3" role="log" aria-label="Conversation" aria-live="polite">
        {e.messages.map((m) => (
          <div key={m.id} className={cn('max-w-[85%] rounded-card px-3 py-2 text-sm', m.mine ? 'self-end bg-primary-600 text-white dark:bg-primary dark:text-primary-fg' : 'self-start bg-warm')}>
            <p className="whitespace-pre-wrap break-words">{m.body}</p>
            <p className={cn('mt-0.5 text-[11px]', m.mine ? 'opacity-80' : 'text-muted')}>{timeAgo(m.created_at)}</p>
          </div>
        ))}
        <div ref={end} />
      </div>
      {closed ? <Alert tone="info">This enquiry is closed.</Alert> : (
        <form onSubmit={submit} className="flex items-end gap-2">
          <div className="flex-1"><label htmlFor="msg" className="sr-only">Message</label>
            <textarea id="msg" value={body} onChange={(x) => setBody(x.target.value)} maxLength={2000} rows={2} placeholder="Write a message…" className="w-full rounded-ctl border border-line bg-surface px-3 py-2 text-base" /></div>
          <Button type="submit" size="icon" loading={send.isPending} aria-label="Send message"><Send className="h-5 w-5" /></Button>
        </form>
      )}
      <ConfirmDialog open={closeOpen} onOpenChange={setCloseOpen} title="Close this enquiry?" body="You can no longer send messages in a closed enquiry." confirmLabel="Close enquiry" loading={close.isPending} onConfirm={() => close.mutate()} />
      <ReportEnquiry id={e.id} open={reportOpen} onOpenChange={setReportOpen} />
      <ConfirmDialog open={blockOpen} onOpenChange={setBlockOpen} title={`Block ${e.counterparty.name}?`} destructive confirmLabel="Block user" loading={block.isPending}
        body={<>They won’t be able to send you enquiries or messages. You can unblock them any time from Profile &amp; security. If they broke the rules, please also report the conversation.</>}
        onConfirm={() => e.counterparty.user_id && block.mutate(e.counterparty.user_id, { onError: (er) => toast.error(isApiError(er) ? er.message : 'Could not block this user') })} />
    </div>
  )
}

function ReportEnquiry({ id, open, onOpenChange }: { id: string; open: boolean; onOpenChange: (o: boolean) => void }) {
  const toast = useToast()
  const [reason, setReason] = useState('abuse')
  const [details, setDetails] = useState('')
  const m = useSend(() => api.post('/reports', { target_type: 'enquiry', target_id: id, reason, details }), {
    onSuccess: () => { toast.success('Report sent to our moderators'); onOpenChange(false) },
  })
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title="Report this conversation" footer={<><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
      <Button variant="destructive" loading={m.isPending} onClick={() => m.mutate(undefined, { onError: (e) => toast.error(isApiError(e) ? (e.status === 409 ? 'Already reported' : e.message) : 'Could not report') })}>Report</Button></>}>
      <div className="space-y-3">
        <Field label="Reason"><Select value={reason} onChange={(e) => setReason(e.target.value)}>{['abuse', 'spam', 'scam', 'other'].map((r) => <option key={r} value={r}>{titleCase(r)}</option>)}</Select></Field>
        <Field label="Details"><Textarea value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} /></Field>
      </div>
    </Dialog>
  )
}
