import { forwardRef, useId, type InputHTMLAttributes, type ReactNode, type SelectHTMLAttributes, type TextareaHTMLAttributes, createContext, useContext } from 'react'
import { cn } from '@/lib/utils'

const FieldCtx = createContext<{ id: string; describedBy?: string; invalid: boolean } | null>(null)

/** Label + control + hint/error, wiring ids and aria so every input is announced correctly. */
export function Field({ label, error, hint, required, className, children }: {
  label: string; error?: string; hint?: string; required?: boolean; className?: string; children: ReactNode
}) {
  const id = useId()
  const describedBy = [error ? `${id}-err` : null, hint ? `${id}-hint` : null].filter(Boolean).join(' ') || undefined
  return (
    <div className={cn('space-y-1', className)}>
      <label htmlFor={id} className="block text-sm font-medium text-ink">
        {label}{required && <span aria-hidden className="text-danger"> *</span>}
      </label>
      <FieldCtx.Provider value={{ id, describedBy, invalid: !!error }}>{children}</FieldCtx.Provider>
      {hint && !error && <p id={`${id}-hint`} className="text-xs text-muted">{hint}</p>}
      {error && <p id={`${id}-err`} role="alert" className="text-xs font-medium text-danger">{error}</p>}
    </div>
  )
}

const control =
  'w-full rounded-ctl border bg-surface px-3 text-base text-ink placeholder:text-muted/70 transition-colors focus-visible:border-primary disabled:opacity-60'

function useCtl() {
  const c = useContext(FieldCtx)
  return { id: c?.id, 'aria-describedby': c?.describedBy, 'aria-invalid': c?.invalid || undefined, invalid: !!c?.invalid }
}

export const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(function Input({ className, ...rest }, ref) {
  const { invalid, ...a11y } = useCtl()
  return <input ref={ref} {...a11y} {...rest} className={cn(control, 'h-11', invalid ? 'border-danger' : 'border-line', className)} />
})

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaHTMLAttributes<HTMLTextAreaElement>>(function Textarea({ className, ...rest }, ref) {
  const { invalid, ...a11y } = useCtl()
  return <textarea ref={ref} {...a11y} {...rest} className={cn(control, 'min-h-[88px] py-2', invalid ? 'border-danger' : 'border-line', className)} />
})

export const Select = forwardRef<HTMLSelectElement, SelectHTMLAttributes<HTMLSelectElement>>(function Select({ className, children, ...rest }, ref) {
  const { invalid, ...a11y } = useCtl()
  return (
    <select ref={ref} {...a11y} {...rest} className={cn(control, 'h-11 appearance-none bg-no-repeat pr-8', invalid ? 'border-danger' : 'border-line', className)}
      style={{ backgroundImage: "url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%235E6B64' stroke-width='1.6' fill='none' stroke-linecap='round'/%3E%3C/svg%3E\")", backgroundPosition: 'right 12px center' }}>
      {children}
    </select>
  )
})

export const Checkbox = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement> & { label: ReactNode }>(function Checkbox({ label, className, id, ...rest }, ref) {
  const gen = useId()
  const cid = id ?? gen
  return (
    <label htmlFor={cid} className={cn('flex min-h-[44px] cursor-pointer items-center gap-2.5 text-sm text-ink', className)}>
      <input ref={ref} id={cid} type="checkbox" {...rest} className="h-[18px] w-[18px] shrink-0 rounded border-line accent-primary-600" />
      <span>{label}</span>
    </label>
  )
})

export function Switch({ checked, onChange, label, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled} onClick={() => onChange(!checked)}
      className={cn('relative inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors disabled:opacity-50', checked ? 'bg-primary-600' : 'bg-line')}>
      <span className={cn('inline-block h-5 w-5 rounded-full bg-white shadow transition-transform', checked ? 'translate-x-[22px]' : 'translate-x-0.5')} />
    </button>
  )
}
