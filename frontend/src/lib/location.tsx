import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { safeStorage } from './utils'

export interface Loc { city?: string; state?: string; lat?: number; lng?: number }
const store = safeStorage('local')
const KEY = 'petora.location'

function load(): Loc {
  try { return JSON.parse(store.get(KEY) ?? '{}') as Loc } catch { return {} }
}

const Ctx = createContext<{ loc: Loc; setLoc: (l: Loc) => void; locate: () => Promise<Loc> } | null>(null)

export function LocationProvider({ children }: { children: ReactNode }) {
  const [loc, setState] = useState<Loc>(load)
  const setLoc = useCallback((l: Loc) => { setState(l); store.set(KEY, JSON.stringify(l)) }, [])
  /** Browser geolocation → lat/lng. Rejects with a friendly Error when denied/unavailable. */
  const locate = useCallback(() => new Promise<Loc>((resolve, reject) => {
    if (!('geolocation' in navigator)) return reject(new Error('Location is not available on this device.'))
    navigator.geolocation.getCurrentPosition(
      (p) => {
        const l = { lat: Math.round(p.coords.latitude * 1000) / 1000, lng: Math.round(p.coords.longitude * 1000) / 1000, city: 'Near me' }
        setLoc(l)
        resolve(l)
      },
      () => reject(new Error('Location permission was denied. Enter your city instead.')),
      { enableHighAccuracy: false, timeout: 8000, maximumAge: 600_000 },
    )
  }), [setLoc])
  const value = useMemo(() => ({ loc, setLoc, locate }), [loc, setLoc, locate])
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
}
export function useLocationPref() {
  const v = useContext(Ctx)
  if (!v) throw new Error('useLocationPref outside LocationProvider')
  return v
}
