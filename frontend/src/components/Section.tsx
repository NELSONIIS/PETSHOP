import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { ChevronRight } from 'lucide-react'
import { cn } from '@/lib/utils'

export function Section({ title, subtitle, to, linkLabel = 'See all', children, className, tone }: {
  title: string; subtitle?: string; to?: string; linkLabel?: string; children: ReactNode; className?: string; tone?: 'warm'
}) {
  return (
    <section className={cn('py-6 md:py-8', tone === 'warm' && 'bg-warm', className)} aria-label={title}>
      <div className="container-page space-y-3">
        <div className="flex items-end justify-between gap-3">
          <div><h2 className="text-xl md:text-2xl">{title}</h2>{subtitle && <p className="text-sm text-muted">{subtitle}</p>}</div>
          {to && <Link to={to} className="inline-flex min-h-[44px] items-center gap-0.5 text-sm font-semibold text-primary-600 hover:underline">{linkLabel}<ChevronRight className="h-4 w-4" aria-hidden /></Link>}
        </div>
        {children}
      </div>
    </section>
  )
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <div className="mb-4 flex flex-wrap items-end justify-between gap-3">
      <div><h1 className="text-2xl">{title}</h1>{subtitle && <p className="mt-0.5 text-sm text-muted">{subtitle}</p>}</div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </div>
  )
}

export function Stat({ label, value, hint, to, tone }: { label: string; value: ReactNode; hint?: string; to?: string; tone?: 'warn' }) {
  const inner = (
    <div className={cn('card h-full p-3', tone === 'warn' && 'border-warning/50', to && 'transition-colors hover:border-primary-300')}>
      <p className="text-xs font-medium text-muted">{label}</p>
      <p className="mt-0.5 text-2xl font-bold tnum">{value}</p>
      {hint && <p className="text-xs text-muted">{hint}</p>}
    </div>
  )
  return to ? <Link to={to} className="block">{inner}</Link> : inner
}
