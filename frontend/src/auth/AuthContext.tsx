import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { api, hasSessionHint, onAuthLost } from '@/api/client'
import type { AuthResult, RegisterRequest, User } from '@/api/types'

interface AuthState {
  user: User | null
  loading: boolean
  login: (email: string, password: string, otp?: string) => Promise<User>
  register: (input: RegisterRequest) => Promise<User>
  logout: () => Promise<void>
  refreshUser: () => Promise<User | null>
  can: (perm: string) => boolean
}

const Ctx = createContext<AuthState | null>(null)

export function AuthProvider({ children, initialUser }: { children: ReactNode; initialUser?: User | null }) {
  const qc = useQueryClient()
  const [user, setUser] = useState<User | null>(initialUser ?? null)
  const [loading, setLoading] = useState(initialUser === undefined && hasSessionHint())

  const refreshUser = useCallback(async () => {
    try {
      const r = await api.get<User>('/me')
      setUser(r.data)
      return r.data
    } catch {
      setUser(null)
      return null
    }
  }, [])

  useEffect(() => {
    // Visitors who never held a session skip the network round-trip (loading starts false for them).
    if (initialUser !== undefined || !hasSessionHint()) return
    let live = true
    api.get<User>('/me')
      .then((r) => { if (live) setUser(r.data) })
      .catch(() => { if (live) setUser(null) })
      .finally(() => { if (live) setLoading(false) })
    return () => { live = false }
  }, [initialUser])

  useEffect(() => {
    onAuthLost(() => { setUser(null); qc.clear() })
    return () => onAuthLost(null)
  }, [qc])

  const login = useCallback(async (email: string, password: string, otp?: string) => {
    const r = await api.post<AuthResult>('/auth/login', { email, password, ...(otp ? { otp } : {}) })
    qc.clear()
    // GET /me is authoritative for session-level flags (login responses may omit mfa_verified), so staff re-read it.
    let u = r.data.user
    if (u.account_type === 'staff') { try { u = (await api.get<User>('/me')).data } catch { /* keep login payload */ } }
    setUser(u)
    return u
  }, [qc])

  const register = useCallback(async (input: RegisterRequest) => {
    const r = await api.post<AuthResult>('/auth/register', input)
    qc.clear()
    setUser(r.data.user)
    return r.data.user
  }, [qc])

  const logout = useCallback(async () => {
    try { await api.post('/auth/logout') } catch { /* already signed out */ }
    setUser(null)
    qc.clear()
  }, [qc])

  const can = useCallback((perm: string) => !!user?.permissions?.includes(perm), [user])

  const value = useMemo(() => ({ user, loading, login, register, logout, refreshUser, can }), [user, loading, login, register, logout, refreshUser, can])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}

export function useAuth(): AuthState {
  const v = useContext(Ctx)
  if (!v) throw new Error('useAuth outside AuthProvider')
  return v
}

export function homeFor(user: User): string {
  return user.account_type === 'staff' ? '/admin' : user.account_type === 'seller' ? '/seller' : '/buyer'
}
