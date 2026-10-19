import { useState } from 'react'
import { Plus } from 'lucide-react'
import { api, isApiError } from '@/api/client'
import { useSend } from '@/api/hooks'
import type { AdminUser } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { PageHeader } from '@/components/Section'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Alert, Badge, StatusBadge } from '@/components/ui/Feedback'
import { Checkbox, Field, Input, Select } from '@/components/ui/Form'
import { useToast } from '@/components/ui/Toast'
import { formatDate } from '@/lib/utils'
import { AdminTable, FilterBar, ReasonDialog, usePagedList } from './common'

const STAFF_ROLES = ['moderator', 'finance', 'support', 'super_admin']

export default function AdminUsers() {
  const { can } = useAuth()
  const toast = useToast()
  const list = usePagedList<AdminUser>('/admin/users')
  const [sel, setSel] = useState<AdminUser | null>(null)
  const [suspend, setSuspend] = useState(false)
  const [roles, setRoles] = useState<string[]>([])
  const [staffOpen, setStaffOpen] = useState(false)
  const done = () => { setSel(null); list.q.refetch() }
  const fail = (e: unknown) => toast.error(isApiError(e) ? e.message : 'Action failed')
  const doSuspend = useSend((reason: string) => api.post(`/admin/users/${sel?.id}/suspend`, { reason }), { onSuccess: () => { setSuspend(false); toast.success('User suspended'); done() } })
  const reinstate = useSend(() => api.post(`/admin/users/${sel?.id}/reinstate`), { onSuccess: () => { toast.success('User reinstated'); done() } })
  const saveRoles = useSend(() => api.put(`/admin/users/${sel?.id}/roles`, { roles }), { onSuccess: () => { toast.success('Roles updated'); done() } })
  const open = (u: AdminUser) => { setSel(u); setRoles(u.roles.filter((r) => STAFF_ROLES.includes(r))) }
  return (
    <div className="space-y-3">
      <PageHeader title="Users" subtitle="Buyers, sellers and staff" actions={can('roles.manage') ? <Button size="sm" onClick={() => setStaffOpen(true)}><Plus className="h-4 w-4" aria-hidden />New staff account</Button> : undefined} />
      <FilterBar>
        <Field label="Search" className="min-w-[200px] flex-1"><Input placeholder="Name or email" onChange={(e) => list.set('q', e.target.value)} /></Field>
        <Field label="Type"><Select value={list.filters.account_type ?? ''} onChange={(e) => list.set('account_type', e.target.value)}><option value="">All</option><option value="buyer">Buyers</option><option value="seller">Sellers</option><option value="staff">Staff</option></Select></Field>
        <Field label="Status"><Select value={list.filters.status ?? ''} onChange={(e) => list.set('status', e.target.value)}><option value="">All</option><option value="active">Active</option><option value="suspended">Suspended</option><option value="deleted">Deleted</option></Select></Field>
      </FilterBar>
      <AdminTable list={list} rowKey={(u) => u.id} onRowClick={open} empty="No users match" columns={[
        { header: 'User', cell: (u) => <div><p className="font-medium">{u.name}</p><p className="text-xs text-muted">{u.email}</p></div> },
        { header: 'Type', cell: (u) => <Badge tone={u.account_type === 'staff' ? 'secondary' : 'neutral'}>{u.account_type}</Badge> },
        { header: 'Roles', cell: (u) => u.roles.join(', ') || '—', hideOnMobile: true },
        { header: 'Status', cell: (u) => <StatusBadge status={u.status} /> },
        { header: 'Last login', cell: (u) => formatDate(u.last_login_at), hideOnMobile: true },
      ]} />
      <Dialog open={!!sel} onOpenChange={(o) => !o && setSel(null)} title={sel?.name ?? ''} description={sel?.email}>
        {sel && (
          <div className="space-y-3 text-sm">
            <dl className="grid grid-cols-2 gap-2"><div><dt className="text-xs text-muted">Type</dt><dd>{sel.account_type}</dd></div><div><dt className="text-xs text-muted">Status</dt><dd><StatusBadge status={sel.status} /></dd></div>
              <div><dt className="text-xs text-muted">Email verified</dt><dd>{sel.email_verified ? 'Yes' : 'No'}</dd></div><div><dt className="text-xs text-muted">Joined</dt><dd>{formatDate(sel.created_at)}</dd></div>
              <div><dt className="text-xs text-muted">Last login</dt><dd>{formatDate(sel.last_login_at, true)}</dd></div><div><dt className="text-xs text-muted">MFA</dt><dd>{sel.mfa_enabled ? 'Enabled' : 'Off'}</dd></div></dl>
            {sel.suspended_reason && <Alert tone="danger" title="Suspension reason">{sel.suspended_reason}</Alert>}
            {can('users.manage') && sel.status !== 'deleted' && (sel.status === 'active'
              ? <Button variant="destructive" size="sm" onClick={() => setSuspend(true)}>Suspend user</Button>
              : <Button variant="outline" size="sm" loading={reinstate.isPending} onClick={() => reinstate.mutate(undefined, { onError: fail })}>Reinstate user</Button>)}
            {can('roles.manage') && sel.account_type === 'staff' && (
              <fieldset className="space-y-1 rounded-ctl border border-line p-3"><legend className="px-1 text-sm font-medium">Staff roles</legend>
                {STAFF_ROLES.map((r) => <Checkbox key={r} label={r.replace('_', ' ')} checked={roles.includes(r)} onChange={(e) => setRoles((xs) => (e.target.checked ? [...xs, r] : xs.filter((x) => x !== r)))} />)}
                <Button size="sm" loading={saveRoles.isPending} disabled={roles.length === 0} onClick={() => saveRoles.mutate(undefined, { onError: fail })}>Save roles</Button></fieldset>)}
          </div>)}
      </Dialog>
      <ReasonDialog open={suspend} onOpenChange={setSuspend} title="Suspend this user?" confirmLabel="Suspend" destructive loading={doSuspend.isPending} help="The user is signed out everywhere and shown this reason." onConfirm={(r) => doSuspend.mutate(r, { onError: fail })} />
      <NewStaff open={staffOpen} onOpenChange={setStaffOpen} onCreated={() => list.q.refetch()} />
    </div>
  )
}

function NewStaff({ open, onOpenChange, onCreated }: { open: boolean; onOpenChange: (o: boolean) => void; onCreated: () => void }) {
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [roles, setRoles] = useState<string[]>(['support'])
  const [err, setErr] = useState('')
  const [pw, setPw] = useState<string | null>(null)
  const create = useSend(() => api.post<{ user: AdminUser; temporary_password: string }>('/admin/staff', { name: name.trim(), email: email.trim(), roles }), { onSuccess: (d) => { setPw(d.temporary_password); onCreated() } })
  const close = (o: boolean) => { onOpenChange(o); if (!o) { setPw(null); setName(''); setEmail(''); setErr('') } }
  return (
    <Dialog open={open} onOpenChange={close} title={pw ? 'Staff account created' : 'New staff account'} footer={pw ? <Button onClick={() => close(false)}>Done</Button> : <><Button variant="outline" onClick={() => close(false)}>Cancel</Button>
      <Button loading={create.isPending} onClick={() => { setErr(''); if (name.trim().length < 2 || !/^\S+@\S+\.\S+$/.test(email) || !roles.length) { setErr('Enter a name, a valid email and at least one role.'); return } create.mutate(undefined, { onError: (e) => setErr(isApiError(e) ? e.message : 'Could not create') }) }}>Create</Button></>}>
      {pw ? <div className="space-y-2"><Alert tone="warning" title="Copy this temporary password now">It is shown only once. The user must set up multi-factor authentication at first login.</Alert><code className="block select-all rounded-ctl bg-warm p-3 text-base font-semibold">{pw}</code></div> : (
        <div className="space-y-3">{err && <Alert tone="danger">{err}</Alert>}
          <Field label="Full name" required><Input value={name} onChange={(e) => setName(e.target.value)} /></Field><Field label="Email" required><Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} /></Field>
          <fieldset><legend className="text-sm font-medium">Roles</legend>{STAFF_ROLES.map((r) => <Checkbox key={r} label={r.replace('_', ' ')} checked={roles.includes(r)} onChange={(e) => setRoles((xs) => (e.target.checked ? [...xs, r] : xs.filter((x) => x !== r)))} />)}</fieldset></div>)}
    </Dialog>
  )
}
