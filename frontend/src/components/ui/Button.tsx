import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { Link, type LinkProps } from 'react-router-dom'
import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'

type Variant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'destructive' | 'accent'
type Size = 'sm' | 'md' | 'lg' | 'icon'

const base =
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-ctl font-semibold transition-colors disabled:pointer-events-none disabled:opacity-50 select-none'
const variants: Record<Variant, string> = {
  primary: 'bg-primary-600 text-white hover:bg-primary-700 dark:bg-primary dark:text-primary-fg dark:hover:bg-primary-500',
  secondary: 'bg-secondary-50 text-secondary-700 hover:bg-secondary-100 dark:bg-secondary-50 dark:text-secondary-700',
  outline: 'border border-line bg-surface text-ink hover:bg-warm',
  ghost: 'text-ink hover:bg-warm',
  destructive: 'bg-danger text-white hover:opacity-90',
  accent: 'bg-accent-600 text-white hover:bg-accent-600/90 dark:bg-accent dark:text-[#2b1008]',
}
const sizes: Record<Size, string> = {
  sm: 'h-9 px-3 text-sm min-w-[44px]',
  md: 'h-11 px-4 text-sm',
  lg: 'h-12 px-6 text-base',
  icon: 'h-11 w-11',
}
export const buttonClass = (variant: Variant = 'primary', size: Size = 'md', className?: string) =>
  cn(base, variants[variant], sizes[size], className)

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  size?: Size
  loading?: boolean
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  { variant = 'primary', size = 'md', loading, className, children, disabled, type = 'button', ...rest }, ref) {
  return (
    <button ref={ref} type={type} disabled={disabled || loading} aria-busy={loading || undefined}
      className={buttonClass(variant, size, className)} {...rest}>
      {loading && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
      {children}
    </button>
  )
})

export function LinkButton({ variant = 'primary', size = 'md', className, children, ...rest }: LinkProps & { variant?: Variant; size?: Size; children: ReactNode }) {
  return <Link className={buttonClass(variant, size, className)} {...rest}>{children}</Link>
}
