import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'
import { CheckCircle2, XCircle, Info, X } from 'lucide-react'
import { cn, uuid } from '@/lib/utils'

type Tone = 'success' | 'error' | 'info'
interface Toast { id: string; tone: Tone; message: string }
interface ToastApi { success: (m: string) => void; error: (m: string) => void; info: (m: string) => void }
const Ctx = createContext<ToastApi | null>(null)

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([])
  const dismiss = useCallback((id: string) => setToasts((t) => t.filter((x) => x.id !== id)), [])
  const push = useCallback((tone: Tone, message: string) => {
    const id = uuid()
    setToasts((t) => [...t.slice(-3), { id, tone, message }])
    setTimeout(() => dismiss(id), tone === 'error' ? 7000 : 4000)
  }, [dismiss])
  const api = useMemo<ToastApi>(() => ({ success: (m) => push('success', m), error: (m) => push('error', m), info: (m) => push('info', m) }), [push])
  const Icon = { success: CheckCircle2, error: XCircle, info: Info }
  return (
    <Ctx.Provider value={api}>
      {children}
      <div aria-live="polite" className="pointer-events-none fixed inset-x-0 bottom-[calc(72px+env(safe-area-inset-bottom))] z-[60] flex flex-col items-center gap-2 px-4 md:bottom-6">
        {toasts.map((t) => {
          const I = Icon[t.tone]
          return (
            <div key={t.id} role={t.tone === 'error' ? 'alert' : 'status'}
              className={cn('pointer-events-auto flex w-full max-w-sm animate-slide-up items-center gap-2 rounded-ctl bg-ink px-3 py-2.5 text-sm text-bg shadow-raised')}>
              <I className={cn('h-4 w-4 shrink-0', t.tone === 'error' ? 'text-danger' : t.tone === 'success' ? 'text-primary-300' : 'text-info')} aria-hidden />
              <span className="flex-1">{t.message}</span>
              <button aria-label="Dismiss" onClick={() => dismiss(t.id)} className="grid h-8 w-8 place-items-center rounded hover:bg-white/10"><X className="h-4 w-4" /></button>
            </div>
          )
        })}
      </div>
    </Ctx.Provider>
  )
}

export function useToast(): ToastApi {
  const v = useContext(Ctx)
  if (!v) throw new Error('useToast outside ToastProvider')
  return v
}
