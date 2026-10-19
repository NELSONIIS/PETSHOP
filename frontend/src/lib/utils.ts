import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export const cn = (...v: ClassValue[]) => twMerge(clsx(v))

export function formatMoney(minor: number | null | undefined, currency = 'INR', opts: { free?: boolean } = {}): string {
  if (minor == null) return '—'
  if (minor === 0 && opts.free) return 'Free'
  const major = minor / 100
  const whole = Number.isInteger(major)
  try {
    return new Intl.NumberFormat(currency === 'INR' ? 'en-IN' : undefined, {
      style: 'currency', currency, minimumFractionDigits: whole ? 0 : 2, maximumFractionDigits: 2,
    }).format(major)
  } catch {
    return `${currency} ${major.toFixed(2)}`
  }
}

/** Rupees (user input) → integer paise without float drift. */
export function toMinor(input: string | number): number {
  const s = String(input).replace(/[,\s₹]/g, '')
  if (!s) return 0
  const [w, f = ''] = s.split('.')
  return parseInt(w || '0', 10) * 100 + parseInt((f + '00').slice(0, 2), 10)
}
export const fromMinor = (m?: number | null): string => (m == null ? '' : (m / 100).toString())

export function formatAge(months?: number | null): string {
  if (months == null) return 'Age not stated'
  if (months < 1) return 'Under 1 month'
  if (months < 24) return `${months} month${months === 1 ? '' : 's'}`
  const y = Math.floor(months / 12)
  const m = months % 12
  return m ? `${y} yr ${m} mo` : `${y} years`
}

export function formatDate(iso?: string | null, withTime = false): string {
  if (!iso) return '—'
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return '—'
  return d.toLocaleString('en-IN', withTime
    ? { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }
    : { day: 'numeric', month: 'short', year: 'numeric' })
}

export function timeAgo(iso?: string | null): string {
  if (!iso) return ''
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000)
  if (s < 60) return 'just now'
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  if (s < 86400 * 7) return `${Math.floor(s / 86400)}d ago`
  return formatDate(iso)
}

export const titleCase = (s: string) => s.replace(/[_-]/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())

export function uuid(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16)
  })
}

export function safeStorage(kind: 'local' | 'session' = 'local') {
  return {
    get(key: string): string | null {
      try { return (kind === 'local' ? localStorage : sessionStorage).getItem(key) } catch { return null }
    },
    set(key: string, val: string) {
      try { (kind === 'local' ? localStorage : sessionStorage).setItem(key, val) } catch { /* storage unavailable */ }
    },
    remove(key: string) {
      try { (kind === 'local' ? localStorage : sessionStorage).removeItem(key) } catch { /* storage unavailable */ }
    },
  }
}

export function debounce<A extends unknown[]>(fn: (...a: A) => void, ms: number) {
  let t: ReturnType<typeof setTimeout> | undefined
  return (...a: A) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms) }
}
