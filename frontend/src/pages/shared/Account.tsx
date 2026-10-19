import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { Bell, Laptop, Smartphone, Trash2 } from 'lucide-react'
import { api, applyFieldErrors, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { BlockedUser, BuyerProfile, Notification, SessionInfo } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, EmptyState, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Checkbox, Field, Input } from '@/components/ui/Form'
import { Pagination } from '@/components/ui/Pagination'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { changePasswordSchema } from '@/lib/schemas'
import { cn, formatDate, timeAgo } from '@/lib/utils'

export function NotificationsPage({ base }: { base: '/buyer' | '/seller' }) {
  const nav = useNavigate()
  const [unread, setUnread] = useState('')
  const [page, setPage] = useState(1)
  const q = useGet<Notification[]>('/notifications', { unread: unread === 'unread', page, per_page: 20 }, { keepPrevious: true })
  const read = useSend((id: string) => api.post(`/notifications/${id}/read`), { invalidate: ['/notifications'] })
  const readAll = useSend(() => api.post('/notifications/read-all'), { invalidate: ['/notifications'] })
  const open = (n: Notification) => {
    if (!n.read) read.mutate(n.id)
    const d = n.data as { enquiry_id?: string; listing_slug?: string; payment_id?: string }
    if (d.enquiry_id) nav(`${base}/enquiries/${d.enquiry_id}`)
    else if (d.listing_slug) nav(`/pets/${d.listing_slug}`)
    else if (d.payment_id) nav(`${base}/billing`)
  }
  return (
    <div className="space-y-3">
      <PageHeader title="Notifications" actions={<Button variant="outline" size="sm" loading={readAll.isPending} onClick={() => readAll.mutate()}>Mark all read</Button>} />
      <TabBar label="Filter" value={unread} onChange={(v) => { setUnread(v); setPage(1) }} items={[{ value: '', label: 'All' }, { value: 'unread', label: 'Unread' }]} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading ? <Skeleton className="h-40 w-full" />
        : !q.items?.length ? <EmptyState icon={<Bell className="h-5 w-5" />} title="You’re all caught up" body="Replies, payment updates and listing decisions appear here." />
        : <ul className="space-y-2">{q.items.map((n) => (
          <li key={n.id}><button type="button" onClick={() => open(n)} className={cn('card flex w-full items-start gap-3 p-3 text-left', !n.read && 'border-primary-300 bg-primary-50/60')}>
            <span className={cn('mt-1.5 h-2 w-2 shrink-0 rounded-full', n.read ? 'bg-transparent' : 'bg-accent-500')} aria-hidden />
            <span className="min-w-0 flex-1"><span className="block text-sm font-semibold">{n.title}{!n.read && <span className="sr-only"> (unread)</span>}</span>{n.body && <span className="block text-sm text-muted">{n.body}</span>}</span>
            <span className="shrink-0 text-xs text-muted">{timeAgo(n.created_at)}</span></button></li>))}</ul>}
      <Pagination meta={q.meta} onPage={setPage} />
    </div>
  )
}

export function ProfileSecurityPage({ title = 'Profile & security' }: { title?: string | null }) {
  const { user, refreshUser, logout } = useAuth()
  const nav = useNavigate()
  const toast = useToast()
  const [name, setName] = useState(user?.name ?? '')
  const [phone, setPhone] = useState(user?.phone ?? '')
  const [pErr, setPErr] = useState<Record<string, string>>({})
  const save = useSend(() => api.patch('/me', { name: name.trim(), phone: phone.trim() }), { onSuccess: () => { toast.success('Profile updated'); void refreshUser() } })
  const saveProfile = (e: React.FormEvent) => {
    e.preventDefault(); setPErr({})
    if (name.trim().length < 2) return setPErr({ name: 'Enter your name' })
    save.mutate(undefined, { onError: (er) => { if (isApiError(er) && er.details.length) setPErr(Object.fromEntries(er.details.map((d) => [d.field, d.message]))); else toast.error(isApiError(er) ? er.message : 'Could not save') } })
  }
  const sessions = useGet<SessionInfo[]>('/me/sessions')
  const revoke = useSend((id: string) => api.del(`/me/sessions/${id}`), { invalidate: ['/me/sessions'] })
  const [delOpen, setDelOpen] = useState(false)
  const [delPw, setDelPw] = useState('')
  const [delErr, setDelErr] = useState('')
  const del = useSend(() => api.post('/me/delete-account', { password: delPw }), { onSuccess: async () => { await logout(); nav('/', { replace: true }) } })
  const resend = useSend(() => api.post('/auth/resend-verification'), { onSuccess: () => toast.success('Verification code sent') })
  if (!user) return null
  return (
    <div className="mx-auto max-w-2xl space-y-4">
      {title && <PageHeader title={title} />}
      <section className="card space-y-3 p-4" aria-labelledby="prof-h">
        <h2 id="prof-h" className="text-lg">Profile</h2>
        <form onSubmit={saveProfile} className="space-y-3" noValidate>
          <Field label="Full name" error={pErr.name} required><Input value={name} onChange={(e) => setName(e.target.value)} autoComplete="name" /></Field>
          <Field label="Email" hint={user.email_verified ? 'Verified' : undefined}><Input value={user.email} readOnly disabled /></Field>
          {!user.email_verified && <Alert tone="warning" action={<Button size="sm" variant="outline" loading={resend.isPending} onClick={() => resend.mutate()}>Resend</Button>}>Email not verified. <Link to="/verify-email" className="font-semibold underline">Enter your code</Link></Alert>}
          <Field label="Mobile number" error={pErr.phone}><Input value={phone} onChange={(e) => setPhone(e.target.value)} type="tel" autoComplete="tel" /></Field>
          <Button type="submit" loading={save.isPending}>Save changes</Button>
        </form>
      </section>
      {user.account_type === 'buyer' && <BuyerPrefs />}
      <ChangePassword />
      <section className="card space-y-3 p-4" aria-labelledby="sess-h">
        <h2 id="sess-h" className="text-lg">Active sessions</h2>
        {sessions.isLoading ? <Skeleton className="h-16 w-full" /> : sessions.error ? <ErrorState error={sessions.error} onRetry={() => sessions.refetch()} /> : (
          <ul className="divide-y divide-line">
            {sessions.items?.map((s) => (
              <li key={s.id} className="flex items-center gap-3 py-2.5">
                {s.client === 'mobile' ? <Smartphone className="h-5 w-5 text-muted" aria-hidden /> : <Laptop className="h-5 w-5 text-muted" aria-hidden />}
                <div className="min-w-0 flex-1"><p className="truncate text-sm font-medium">{s.user_agent || s.client}{s.current && <Badge tone="success" className="ml-2">This device</Badge>}</p>
                  <p className="text-xs text-muted">{s.ip} · last active {timeAgo(s.last_used_at)} · signed in {formatDate(s.created_at)}</p></div>
                {!s.current && <Button size="sm" variant="outline" loading={revoke.isPending && revoke.variables === s.id} onClick={() => revoke.mutate(s.id, { onSuccess: () => toast.success('Session signed out') })}>Sign out</Button>}
              </li>))}
          </ul>)}
      </section>
      <BlockedUsers />
      <section className="card space-y-2 border-danger/30 p-4" aria-labelledby="del-h">
        <h2 id="del-h" className="text-lg text-danger">Delete account</h2>
        <p className="text-sm text-muted">Your personal data is erased and your listings are removed. Payment and invoice records are kept as required by law, without identifying details. This cannot be undone.</p>
        <Button variant="destructive" onClick={() => setDelOpen(true)}><Trash2 className="h-4 w-4" aria-hidden />Delete my account</Button>
      </section>
      <Dialog open={delOpen} onOpenChange={setDelOpen} title="Delete your account?" size="sm" footer={<><Button variant="outline" onClick={() => setDelOpen(false)}>Cancel</Button>
        <Button variant="destructive" loading={del.isPending} onClick={() => { setDelErr(''); del.mutate(undefined, { onError: (e) => setDelErr(isApiError(e) ? e.message : 'Could not delete account') }) }}>Delete permanently</Button></>}>
        <Field label="Confirm with your password" error={delErr}><Input type="password" value={delPw} onChange={(e) => setDelPw(e.target.value)} autoComplete="current-password" /></Field>
      </Dialog>
    </div>
  )
}

function ChangePassword() {
  const toast = useToast()
  const [err, setErr] = useState<string | null>(null)
  const { register, handleSubmit, reset, setError, formState: { errors, isSubmitting } } = useForm<{ current_password: string; new_password: string }>({ resolver: zodResolver(changePasswordSchema), defaultValues: { current_password: '', new_password: '' } })
  const onSubmit = handleSubmit(async (v) => {
    setErr(null)
    try { await api.post('/me/change-password', v); toast.success('Password changed. Other devices were signed out.'); reset() } catch (e) { setErr(applyFieldErrors(e, setError as never, ['current_password', 'new_password'])) }
  })
  return (
    <section className="card space-y-3 p-4" aria-labelledby="pw-h">
      <h2 id="pw-h" className="text-lg">Change password</h2>
      <form onSubmit={onSubmit} className="space-y-3" noValidate>
        {err && <Alert tone="danger">{err}</Alert>}
        <Field label="Current password" error={errors.current_password?.message} required><Input type="password" autoComplete="current-password" {...register('current_password')} /></Field>
        <Field label="New password" error={errors.new_password?.message} hint="At least 10 characters, with a letter and a number." required><Input type="password" autoComplete="new-password" {...register('new_password')} /></Field>
        <Button type="submit" loading={isSubmitting}>Update password</Button>
      </form>
    </section>
  )
}

function BuyerPrefs() {
  const toast = useToast()
  const q = useGet<BuyerProfile>('/buyer/profile')
  const [form, setForm] = useState<BuyerProfile | null>(null)
  const v = form ?? q.items
  const save = useSend((b: BuyerProfile) => api.put('/buyer/profile', b), { invalidate: ['/buyer/profile'], onSuccess: () => toast.success('Preferences saved') })
  if (q.isLoading) return <Skeleton className="h-40 w-full" />
  if (q.error || !v) return <ErrorState error={q.error} onRetry={() => q.refetch()} />
  const set = <K extends keyof BuyerProfile>(k: K, val: BuyerProfile[K]) => setForm({ ...v, [k]: val })
  return (
    <section className="card space-y-3 p-4" aria-labelledby="loc-h">
      <h2 id="loc-h" className="text-lg">Location & notifications</h2>
      <div className="grid grid-cols-2 gap-3">
        <Field label="City"><Input value={v.city} onChange={(e) => set('city', e.target.value)} /></Field>
        <Field label="State"><Input value={v.state} onChange={(e) => set('state', e.target.value)} /></Field>
        <Field label="Search radius (km)"><Input inputMode="numeric" value={v.radius_km} onChange={(e) => set('radius_km', Math.min(1000, Math.max(1, Number(e.target.value.replace(/\D/g, '')) || 1)))} /></Field>
      </div>
      <Checkbox label="Email notifications" checked={v.notify_email} onChange={(e) => set('notify_email', e.target.checked)} />
      <Checkbox label="SMS notifications" checked={v.notify_sms} onChange={(e) => set('notify_sms', e.target.checked)} />
      <Checkbox label="Push notifications (mobile app)" checked={v.notify_push} onChange={(e) => set('notify_push', e.target.checked)} />
      <Button loading={save.isPending} onClick={() => save.mutate(v, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Could not save') })}>Save preferences</Button>
    </section>
  )
}

function BlockedUsers() {
  const toast = useToast()
  const q = useGet<BlockedUser[]>('/blocks')
  const unblock = useSend((id: string) => api.del(`/blocks/${id}`), { invalidate: ['/blocks'], onSuccess: () => toast.success('User unblocked') })
  return (
    <section className="card space-y-3 p-4" aria-labelledby="blk-h">
      <h2 id="blk-h" className="text-lg">Blocked users</h2>
      {q.isLoading ? <Skeleton className="h-12 w-full" /> : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} />
        : !q.items?.length ? <p className="text-sm text-muted">You haven’t blocked anyone.</p> : (
          <ul className="divide-y divide-line">{q.items.map((b) => (
            <li key={b.user_id} className="flex items-center justify-between gap-3 py-2.5">
              <div><p className="text-sm font-medium">{b.name}</p><p className="text-xs text-muted">Blocked {formatDate(b.created_at)}</p></div>
              <Button size="sm" variant="outline" loading={unblock.isPending && unblock.variables === b.user_id} onClick={() => unblock.mutate(b.user_id, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Could not unblock') })}>Unblock</Button>
            </li>))}</ul>)}
    </section>
  )
}
