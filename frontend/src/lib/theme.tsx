import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { safeStorage } from './utils'

type Theme = 'light' | 'dark'
const Ctx = createContext<{ theme: Theme; toggle: () => void } | null>(null)
const store = safeStorage('local')

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setTheme] = useState<Theme>(() => (store.get('petora.theme') === 'dark' ? 'dark' : 'light'))
  useEffect(() => {
    document.documentElement.classList.toggle('dark', theme === 'dark')
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#0F1714' : '#1E6B44')
  }, [theme])
  const toggle = useCallback(() => setTheme((t) => { const n = t === 'dark' ? 'light' : 'dark'; store.set('petora.theme', n); return n }), [])
  const value = useMemo(() => ({ theme, toggle }), [theme, toggle])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}
export function useTheme() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useTheme outside ThemeProvider')
  return v
}
