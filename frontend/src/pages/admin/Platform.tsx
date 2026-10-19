import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import QRCode from 'qrcode'
import { Plus, ShieldCheck } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useGet, useSend } from '@/api/hooks'
import type { AdminUser, AuditLog, JobRow, LegalVersion, NotificationTemplate, RoleInfo, Setting } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { PageHeader } from '@/components/Section'
import { Button, LinkButton } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, EmptyState, ErrorState, Skeleton, StatusBadge } from '@/components/ui/Feedback'
import { Checkbox, Field, Input, Select, Switch, Textarea } from '@/components/ui/Form'
import { DataTable } from '@/components/ui/Table'
import { TabBar } from '@/components/ui/Tabs'
import { useToast } from '@/components/ui/Toast'
import { formatDate, timeAgo, titleCase } from '@/lib/utils'
import { AdminTable, FilterBar, shortId, usePagedList } from './common'

// ---------- notification templates ----------
type TemplateRow = NotificationTemplate & { custom: boolean }
export function AdminTemplates() {
  const toast = useToast()
  const q = useGet<{ templates: NotificationTemplate[]; known_keys: string[] }>('/admin/notification-templates')
  const [t, setT] = useState<(NotificationTemplate & { isNew?: boolean }) | null>(null)
  const [err, setErr] = useState('')
  // Built-in defaults live in code; list every known key and mark which ones have a saved override.
  const saved = q.items?.templates ?? []
  const rows: TemplateRow[] = [
    ...saved.map((x) => ({ ...x, custom: true })),
    ...(q.items?.known_keys ?? []).filter((k) => !saved.some((x) => x.key === k && x.channel === 'email')).map((k) => ({ key: k, channel: 'email' as const, subject: '', body: '', is_active: true, custom: false })),
  ].sort((a, b) => a.key.localeCompare(b.key) || a.channel.localeCompare(b.channel))
  const save = useSend(() => api.put(`/admin/notification-templates/${encodeURIComponent(t!.key)}/${t!.channel}`, { subject: t?.subject ?? '', body: t?.body, is_active: t?.is_active ?? true }), {
    invalidate: ['/admin/notification-templates'], onSuccess: () => { toast.success('Template saved'); setT(null) },
  })
  return (
    <div className="space-y-3">
      <PageHeader title="Notification templates" subtitle="Override built-in email, SMS and in-app messages. Use {{.name}}-style variables." actions={<Button size="sm" onClick={() => { setT({ key: '', channel: 'email', subject: '', body: '', is_active: true, isNew: true }); setErr('') }}><Plus className="h-4 w-4" aria-hidden />New template</Button>} />
      <DataTable rows={rows} loading={q.isLoading} error={q.error} onRetry={() => q.refetch()} rowKey={(x) => `${x.key}:${x.channel}`} empty="No templates" onRowClick={(x) => { setT({ ...x }); setErr('') }} columns={[
        { header: 'Key', cell: (x) => <code className="text-xs">{x.key}</code> }, { header: 'Channel', cell: (x) => <Badge>{x.channel}</Badge> },
        { header: 'Source', cell: (x) => (x.custom ? <Badge tone="primary">Custom</Badge> : <Badge>Built-in default</Badge>) },
        { header: 'Active', cell: (x) => (x.custom ? <Badge tone={x.is_active === false ? 'neutral' : 'success'}>{x.is_active === false ? 'Off' : 'On'}</Badge> : '—') },
        { header: 'Updated', cell: (x) => (x.updated_at ? timeAgo(x.updated_at) : '—'), hideOnMobile: true }]} />
      <Dialog open={!!t} onOpenChange={(o) => !o && setT(null)} title={t?.isNew ? 'New template' : `Edit ${t?.key} (${t?.channel})`} footer={<><Button variant="outline" onClick={() => setT(null)}>Cancel</Button>
        <Button loading={save.isPending} onClick={() => { if (!t?.key.trim() || !/^[a-z0-9_.-]+$/.test(t.key)) return setErr('Key: lowercase letters, numbers, _ . -'); if (!t.body.trim()) return setErr('Body is required'); setErr(''); save.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not save') }) }}>Save</Button></>}>
        {t && <div className="space-y-3">{err && <Alert tone="danger">{err}</Alert>}
          {!t.isNew && !t.body && <Alert tone="info">This message currently uses the built-in default text. Saving creates an override; untick “Active” to fall back to the default again.</Alert>}
          <div className="grid grid-cols-2 gap-3"><Field label="Key" required hint={t.isNew ? 'Pick a built-in message to override' : undefined}><Input list="known-template-keys" value={t.key} disabled={!t.isNew} onChange={(e) => setT({ ...t, key: e.target.value })} /><datalist id="known-template-keys">{q.items?.known_keys?.map((k) => <option key={k} value={k} />)}</datalist></Field>
            <Field label="Channel"><Select value={t.channel} disabled={!t.isNew} onChange={(e) => setT({ ...t, channel: e.target.value as NotificationTemplate['channel'] })}><option value="email">Email</option><option value="sms">SMS</option><option value="in_app">In-app</option></Select></Field></div>
          {t.channel === 'email' && <Field label="Subject"><Input value={t.subject ?? ''} onChange={(e) => setT({ ...t, subject: e.target.value })} /></Field>}
          <Field label="Body" required><Textarea rows={7} value={t.body} onChange={(e) => setT({ ...t, body: e.target.value })} /></Field>
          <Checkbox label="Active" checked={t.is_active !== false} onChange={(e) => setT({ ...t, is_active: e.target.checked })} /></div>}
      </Dialog>
    </div>
  )
}

// ---------- content & legal ----------
function JsonBlock({ k, title, children }: { k: 'home' | 'faq'; title: string; children?: (data: Record<string, unknown>, set: (d: Record<string, unknown>) => void) => React.ReactNode }) {
  const toast = useToast()
  const q = useGet<Record<string, unknown>>(`/admin/content/${k}`, undefined, { retry: false })
  const [text, setText] = useState<string | null>(null)
  const [err, setErr] = useState('')
  const data = q.items ?? {}
  const shown = text ?? JSON.stringify(data, null, 2)
  const save = useSend((body: Record<string, unknown>) => api.put(`/admin/content/${k}`, body), { invalidate: [`/admin/content/${k}`, `/content/${k}`], onSuccess: () => { toast.success('Content saved'); setText(null) } })
  const parsed = (): Record<string, unknown> | null => { try { const v = JSON.parse(shown); if (v && typeof v === 'object' && !Array.isArray(v)) return v } catch { /* invalid */ } return null }
  return (
    <section className="card space-y-3 p-4"><h2 className="text-lg">{title}</h2>
      {q.isLoading ? <Skeleton className="h-24 w-full" /> : <>
        {children?.(parsed() ?? data, (d) => setText(JSON.stringify(d, null, 2)))}
        <Field label="Raw JSON" error={err}><Textarea rows={8} className="font-mono text-xs" value={shown} onChange={(e) => setText(e.target.value)} /></Field>
        <Button loading={save.isPending} onClick={() => { const v = parsed(); if (!v) return setErr('Not valid JSON object'); setErr(''); save.mutate(v, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not save') }) }}>Save {title.toLowerCase()}</Button></>}
    </section>
  )
}

function LegalEditor() {
  const q = useGet<LegalVersion[]>('/admin/legal')
  const slugs = ['privacy', 'terms', 'refund-policy', 'seller-policy', 'safety']
  const [slug, setSlug] = useState('terms')
  const versions = (q.items ?? []).filter((v) => v.slug === slug).sort((a, b) => b.version - a.version)
  const cur = versions.find((v) => v.is_current) ?? versions[0]
  return (
    <section className="card space-y-3 p-4"><h2 className="text-lg">Legal pages</h2>
      <p className="text-xs text-muted">Publishing creates a new immutable version and makes it current. Have counsel review before publishing.</p>
      <Field label="Page"><Select value={slug} onChange={(e) => setSlug(e.target.value)}>{slugs.map((s) => <option key={s} value={s}>{titleCase(s)}</option>)}</Select></Field>
      {q.isLoading ? <Skeleton className="h-40 w-full" /> : <LegalForm key={`${slug}:${cur?.version ?? 0}`} slug={slug} cur={cur} versions={versions} />}
    </section>
  )
}

function LegalForm({ slug, cur, versions }: { slug: string; cur?: LegalVersion; versions: LegalVersion[] }) {
  const toast = useToast()
  const [title, setTitle] = useState(cur?.title ?? titleCase(slug))
  const [body, setBody] = useState(cur?.body_md ?? '')
  const [err, setErr] = useState('')
  const pub = useSend(() => api.post(`/admin/legal/${slug}`, { title: title.trim(), body_md: body }), { invalidate: ['/admin/legal', '/legal'], onSuccess: () => toast.success('New version published') })
  return (
    <>
      <Field label="Title"><Input value={title} onChange={(e) => setTitle(e.target.value)} /></Field>
      <Field label="Body (Markdown)" error={err}><Textarea rows={12} className="font-mono text-xs" value={body} onChange={(e) => setBody(e.target.value)} /></Field>
      <div className="flex flex-wrap items-center gap-3"><Button loading={pub.isPending} onClick={() => { if (!title.trim() || body.trim().length < 20) return setErr('Add a title and the full text (at least 20 characters).'); setErr(''); pub.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not publish') }) }}>Publish new version</Button>
        <span className="text-xs text-muted">{versions.length ? `Current: v${cur?.version}${cur?.published_at ? ` · ${formatDate(cur.published_at)}` : ''}` : 'Not published yet'}</span></div>
      {versions.length > 1 && <details className="text-sm"><summary className="cursor-pointer">Version history ({versions.length})</summary><ul className="mt-1 space-y-0.5 text-muted">{versions.map((v) => <li key={v.version}>v{v.version} — {v.title} {v.is_current && <Badge tone="success">current</Badge>}</li>)}</ul></details>}
    </>
  )
}

export function AdminContent() {
  const [tab, setTab] = useState('home')
  return (
    <div className="space-y-3">
      <PageHeader title="Content & legal" subtitle="Homepage copy, FAQs and policy pages" />
      <TabBar label="Content sections" value={tab} onChange={setTab} items={[{ value: 'home', label: 'Homepage' }, { value: 'faq', label: 'FAQ' }, { value: 'legal', label: 'Legal pages' }]} />
      {tab === 'home' && <JsonBlock k="home" title="Homepage">{(d, set) => <div className="grid gap-3"><Field label="Hero title"><Input value={String(d.hero_title ?? '')} onChange={(e) => set({ ...d, hero_title: e.target.value })} /></Field><Field label="Hero subtitle"><Input value={String(d.hero_subtitle ?? '')} onChange={(e) => set({ ...d, hero_subtitle: e.target.value })} /></Field></div>}</JsonBlock>}
      {tab === 'faq' && <JsonBlock k="faq" title="FAQ">{(d, set) => {
        const items = (Array.isArray(d.items) ? d.items : []) as { q: string; a: string }[]
        return <div className="space-y-2">{items.map((it, i) => <div key={i} className="grid gap-2 rounded-ctl border border-line p-2"><Input aria-label={`Question ${i + 1}`} placeholder="Question" value={it.q} onChange={(e) => set({ ...d, items: items.map((x, k) => (k === i ? { ...x, q: e.target.value } : x)) })} />
          <Textarea aria-label={`Answer ${i + 1}`} rows={2} placeholder="Answer" value={it.a} onChange={(e) => set({ ...d, items: items.map((x, k) => (k === i ? { ...x, a: e.target.value } : x)) })} />
          <Button variant="ghost" size="sm" onClick={() => set({ ...d, items: items.filter((_, k) => k !== i) })}>Remove</Button></div>)}
          <Button variant="outline" size="sm" onClick={() => set({ ...d, items: [...items, { q: '', a: '' }] })}><Plus className="h-4 w-4" aria-hidden />Add question</Button></div> }}</JsonBlock>}
      {tab === 'legal' && <LegalEditor />}
    </div>
  )
}

// ---------- settings ----------
function SettingRow({ s, onSaved }: { s: Setting; onSaved: () => void }) {
  const toast = useToast()
  const [val, setVal] = useState<unknown>(s.value)
  const [raw, setRaw] = useState(typeof s.value === 'object' ? JSON.stringify(s.value, null, 2) : '')
  const [err, setErr] = useState('')
  const save = useSend((v: unknown) => api.put(`/admin/settings/${encodeURIComponent(s.key)}`, { value: v }), { onSuccess: () => { toast.success(`${s.key} saved`); onSaved() } })
  const dirty = JSON.stringify(val) !== JSON.stringify(s.value) || (typeof s.value === 'object' && raw !== JSON.stringify(s.value, null, 2))
  const commit = () => {
    let v = val
    if (typeof s.value === 'object') { try { v = JSON.parse(raw) } catch { return setErr('Invalid JSON') } }
    setErr(''); save.mutate(v, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not save') })
  }
  return (
    <li className="space-y-1.5 py-3">
      <div className="flex flex-wrap items-center gap-2"><code className="text-sm font-semibold">{s.key}</code>{s.is_public && <Badge tone="info">public</Badge>}<span className="ml-auto text-xs text-muted">updated {timeAgo(s.updated_at)}</span></div>
      <div className="flex flex-wrap items-start gap-2">
        {typeof s.value === 'boolean' ? <Switch label={s.key} checked={!!val} onChange={setVal} />
          : typeof s.value === 'number' ? <div className="w-40"><label className="sr-only" htmlFor={`s-${s.key}`}>{s.key}</label><Input id={`s-${s.key}`} inputMode="decimal" value={String(val)} onChange={(e) => setVal(e.target.value === '' || Number.isNaN(Number(e.target.value)) ? 0 : Number(e.target.value))} /></div>
          : typeof s.value === 'string' ? <div className="min-w-[240px] flex-1"><label className="sr-only" htmlFor={`s-${s.key}`}>{s.key}</label><Input id={`s-${s.key}`} value={String(val)} onChange={(e) => setVal(e.target.value)} /></div>
          : <div className="min-w-[240px] flex-1"><label className="sr-only" htmlFor={`s-${s.key}`}>{s.key}</label><Textarea id={`s-${s.key}`} rows={3} className="font-mono text-xs" value={raw} onChange={(e) => setRaw(e.target.value)} /></div>}
        <Button size="sm" disabled={!dirty} loading={save.isPending} onClick={commit}>Save</Button>
      </div>
      {err && <p role="alert" className="text-xs text-danger">{err}</p>}
    </li>
  )
}
export function AdminSettings() {
  const q = useGet<Setting[]>('/admin/settings')
  const [group, setGroup] = useState('')
  const groups = Array.from(new Set((q.items ?? []).map((s) => s.key.split('.')[0])))
  const shown = (q.items ?? []).filter((s) => !group || s.key.startsWith(group + '.'))
  return (
    <div className="space-y-3">
      <PageHeader title="Platform settings" subtitle="Every change is audited" />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading ? <Skeleton className="h-60 w-full" /> : <>
        <TabBar label="Setting groups" value={group} onChange={setGroup} items={[{ value: '', label: 'All' }, ...groups.map((g) => ({ value: g, label: titleCase(g) }))]} />
        {shown.length === 0 ? <EmptyState title="No settings" /> : <ul className="card divide-y divide-line px-4">{shown.map((s) => <SettingRow key={s.key + JSON.stringify(s.value)} s={s} onSaved={() => q.refetch()} />)}</ul>}</>}
    </div>
  )
}

// ---------- security / MFA ----------
export function AdminSecurity() {
  const { user, can } = useAuth()
  const roles = useGet<{ roles: RoleInfo[]; permissions: { code: string; description: string }[] }>(can('roles.manage') ? '/admin/roles' : null)
  const staff = useGet<AdminUser[]>(can('users.view') ? '/admin/users' : null, { account_type: 'staff', per_page: 50 })
  return (
    <div className="space-y-4">
      <PageHeader title="Security & permissions" />
      <section className="card flex flex-wrap items-center justify-between gap-3 p-4" aria-label="Your MFA status"><div className="flex items-center gap-3"><ShieldCheck className="h-6 w-6 text-primary-600" aria-hidden /><div><h2 className="text-lg">Multi-factor authentication</h2><p className="text-sm text-muted">{user?.mfa_enabled ? 'Enabled for your account.' : 'Required for all staff accounts.'}</p></div></div>
        <LinkButton to="/admin/mfa" variant="outline" size="sm">{user?.mfa_enabled ? 'View' : 'Set up now'}</LinkButton></section>
      <section className="card space-y-1 p-4" aria-label="Your permissions"><h2 className="text-lg">Your access</h2><p className="text-sm text-muted">Roles: {user?.roles.join(', ')}</p><div className="flex flex-wrap gap-1.5 pt-1">{(user?.permissions ?? []).map((p) => <Badge key={p} tone="primary">{p}</Badge>)}</div></section>
      {can('roles.manage') && <section className="space-y-2"><h2 className="text-lg">Roles</h2>
        <DataTable rows={roles.items?.roles?.filter((r) => r.is_staff !== false)} loading={roles.isLoading} error={roles.error} onRetry={() => roles.refetch()} rowKey={(r) => r.code} columns={[
          { header: 'Role', cell: (r) => <div><p className="font-medium">{r.name ?? titleCase(r.code)}</p><p className="text-xs text-muted">{r.description}</p></div> }, { header: 'Permissions', cell: (r) => <div className="flex flex-wrap justify-end gap-1 md:justify-start">{(r.permissions ?? []).map((p) => <Badge key={p}>{p}</Badge>)}</div> }]} /></section>}
      {can('users.view') && <section className="space-y-2"><div className="flex items-center justify-between"><h2 className="text-lg">Staff accounts</h2><Link to="/admin/users" className="text-sm font-semibold text-primary-600">Manage in Users</Link></div>
        <DataTable rows={staff.items} loading={staff.isLoading} error={staff.error} onRetry={() => staff.refetch()} rowKey={(u) => u.id} columns={[{ header: 'Name', cell: (u) => <div><p className="font-medium">{u.name}</p><p className="text-xs text-muted">{u.email}</p></div> },
          { header: 'Roles', cell: (u) => u.roles.join(', ') }, { header: 'MFA', cell: (u) => <Badge tone={u.mfa_enabled ? 'success' : 'warning'}>{u.mfa_enabled ? 'On' : 'Off'}</Badge> }, { header: 'Status', cell: (u) => <StatusBadge status={u.status} /> }]} /></section>}
    </div>
  )
}

export function AdminMfaPage() {
  const { user, refreshUser } = useAuth()
  const nav = useNavigate()
  const toast = useToast()
  const [setup, setSetup] = useState<{ secret: string; otpauth_uri: string } | null>(null)
  const [qr, setQr] = useState('')
  const [code, setCode] = useState('')
  const [err, setErr] = useState('')
  const start = useSend(() => api.post<{ secret: string; otpauth_uri: string }>('/auth/mfa/setup'), { onSuccess: (d) => { setSetup(d); QRCode.toDataURL(d.otpauth_uri, { margin: 1, width: 192 }).then(setQr).catch(() => setQr('')) } })
  const enable = useSend(() => api.post('/auth/mfa/enable', { code: code.trim() }), { onSuccess: async () => { toast.success('MFA enabled'); await refreshUser(); nav('/admin', { replace: true }) } })
  if (user?.mfa_enabled && user.mfa_verified) return <div className="mx-auto max-w-md space-y-3"><PageHeader title="Multi-factor authentication" /><Alert tone="success">MFA is enabled and verified for this session.</Alert><LinkButton to="/admin" variant="outline">Back to admin</LinkButton></div>
  if (user?.mfa_enabled) return <div className="mx-auto max-w-md space-y-3"><PageHeader title="Multi-factor authentication" /><Alert tone="warning" title="This session is not MFA-verified">Sign out and sign in again, entering the code from your authenticator app.</Alert></div>
  return (
    <div className="mx-auto max-w-md space-y-3">
      <PageHeader title="Set up multi-factor authentication" subtitle="Required before you can use the admin portal" />
      <section className="card space-y-3 p-4">
        {!setup ? <><p className="text-sm">Use an authenticator app (Google Authenticator, Authy, 1Password…) to generate 6-digit codes.</p><Button loading={start.isPending} onClick={() => start.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not start setup') })}>Start setup</Button></> : (
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); setErr(''); if (!/^\d{6}$/.test(code.trim())) return setErr('Enter the 6-digit code'); enable.mutate(undefined, { onError: (er) => setErr(isApiError(er) ? er.message : 'Could not verify') }) }}>
            <p className="text-sm">1. Scan this QR code, or enter the key manually.</p>
            {qr && <img src={qr} width={192} height={192} alt="QR code for your authenticator app" className="mx-auto rounded-ctl border border-line bg-white p-1" />}
            <Field label="Setup key (manual entry)"><Input readOnly value={setup.secret} onFocus={(e) => e.currentTarget.select()} className="font-mono text-sm" /></Field>
            <p className="break-all text-xs text-muted">{setup.otpauth_uri}</p>
            <Field label="2. Enter the 6-digit code" error={err} required><Input inputMode="numeric" autoComplete="one-time-code" maxLength={6} value={code} onChange={(e) => setCode(e.target.value)} /></Field>
            <Button type="submit" loading={enable.isPending} className="w-full">Enable MFA</Button></form>)}
        {!setup && err && <Alert tone="danger">{err}</Alert>}
      </section>
    </div>
  )
}

// ---------- audit logs & jobs ----------
export function AdminAudit() {
  const list = usePagedList<AuditLog>('/admin/audit-logs', {}, 30)
  return (
    <div className="space-y-3">
      <PageHeader title="Audit logs" subtitle="Sensitive and financial actions" />
      <FilterBar><Field label="Action" className="min-w-[180px] flex-1"><Input placeholder="e.g. refund.created" onChange={(e) => list.set('action', e.target.value)} /></Field><Field label="Entity type"><Input placeholder="payment" onChange={(e) => list.set('entity_type', e.target.value)} /></Field><Field label="Actor id"><Input onChange={(e) => list.set('actor_id', e.target.value)} /></Field></FilterBar>
      <AdminTable list={list} rowKey={(l) => String(l.id)} empty="No audit entries" columns={[
        { header: 'When', cell: (l) => <span className="whitespace-nowrap text-xs">{formatDate(l.created_at, true)}</span> }, { header: 'Actor', cell: (l) => <div><p className="text-sm">{l.actor_email ?? (l.actor_id ? shortId(l.actor_id) : 'system')}</p><p className="text-xs text-muted">{l.actor_roles?.join(', ')}</p></div> },
        { header: 'Action', cell: (l) => <code className="text-xs">{l.action}</code> }, { header: 'Entity', cell: (l) => `${l.entity_type} ${l.entity_id ? shortId(l.entity_id) : ''}`, hideOnMobile: true },
        { header: 'Details', cell: (l) => <details><summary className="cursor-pointer text-xs text-primary-600">View</summary><pre className="mt-1 max-w-[320px] overflow-x-auto whitespace-pre-wrap rounded bg-warm p-2 text-left text-[11px]">{JSON.stringify({ ...l.metadata, ip: l.ip, request_id: l.request_id }, null, 1)}</pre></details> }]} />
    </div>
  )
}

export function AdminJobs() {
  const toast = useToast()
  const list = usePagedList<JobRow>('/admin/jobs', { status: 'dead' })
  const retry = useSend((id: string) => api.post(`/admin/jobs/${id}/retry`), { onSuccess: () => { toast.success('Job re-queued'); list.q.refetch() } })
  return (
    <div className="space-y-3">
      <PageHeader title="Background jobs" subtitle="Emails, expiry sweeps and webhooks. Dead jobs failed all retries." />
      <TabBar label="Job status" value={list.filters.status ?? ''} onChange={(v) => list.set('status', v)} items={[{ value: 'dead', label: 'Dead' }, { value: 'failed', label: 'Retrying' }, { value: 'queued', label: 'Queued' }, { value: 'running', label: 'Running' }, { value: 'succeeded', label: 'Succeeded' }, { value: 'all', label: 'All' }]} />
      <AdminTable list={list} rowKey={(j) => j.id} empty="No jobs in this state" columns={[
        { header: 'Kind', cell: (j) => <code className="text-xs">{j.kind}</code> }, { header: 'Status', cell: (j) => <StatusBadge status={j.status} /> }, { header: 'Attempts', cell: (j) => `${j.attempts}${j.max_attempts ? ` / ${j.max_attempts}` : ''}`, hideOnMobile: true },
        { header: 'Last error', cell: (j) => <span className="line-clamp-2 max-w-[260px] text-xs text-muted">{j.last_error ?? '—'}</span> }, { header: 'Created', cell: (j) => (j.created_at ? timeAgo(j.created_at) : '—'), hideOnMobile: true },
        { header: '', cell: (j) => (j.status === 'dead' || j.status === 'failed' ? <Button size="sm" variant="outline" loading={retry.isPending && retry.variables === j.id} onClick={() => retry.mutate(j.id, { onError: (e) => toast.error(isApiError(e) ? e.message : 'Retry failed') })}>Retry</Button> : null) }]} />
    </div>
  )
}
