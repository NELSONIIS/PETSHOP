import type { ReactNode } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import type { AccountType } from '@/api/types'
import { Spinner } from '@/components/ui/Spinner'
import { useAuth, homeFor } from './AuthContext'

/** UI-level route guard. The backend remains authoritative for every request. */
export function RequireAuth({ types, perm, children }: { types?: AccountType[]; perm?: string; children: ReactNode }) {
  const { user, loading, can } = useAuth()
  const loc = useLocation()
  if (loading) return <div className="grid min-h-[50vh] place-items-center"><Spinner label="Loading your account" /></div>
  if (!user) return <Navigate to={`/login?next=${encodeURIComponent(loc.pathname + loc.search)}`} replace />
  if (types && !types.includes(user.account_type)) return <Navigate to={homeFor(user)} replace />
  if (perm && !can(perm)) return <Navigate to="/admin" replace />
  return <>{children}</>
}

/** Admin area: staff + MFA. Staff without verified MFA are sent to the enrolment page. */
export function RequireStaff({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const loc = useLocation()
  return (
    <RequireAuth types={['staff']}>
      {user && (!user.mfa_enabled || !user.mfa_verified) && loc.pathname !== '/admin/mfa' ? <Navigate to="/admin/mfa" replace /> : children}
    </RequireAuth>
  )
}

export function Guest({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth()
  if (loading) return <div className="grid min-h-[50vh] place-items-center"><Spinner label="Loading" /></div>
  if (user) return <Navigate to={homeFor(user)} replace />
  return <>{children}</>
}
