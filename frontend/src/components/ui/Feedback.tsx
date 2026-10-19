import { AlertTriangle, Inbox, RefreshCw, Info, CheckCircle2, XCircle } from 'lucide-react'
import type { ReactNode } from 'react'
import { isApiError } from '@/api/client'
import { cn } from '@/lib/utils'
import { Button } from './Button'

export function Skeleton({ className }: { className?: string }) {
  return (
    <div aria-hidden className={cn('relative overflow-hidden rounded-chip bg-line/70', className)}>
      <div className="absolute inset-0 -translate-x-full animate-shimmer bg-gradient-to-r from-transparent via-white/40 to-transparent dark:via-white/10" />
    </div>
  )
}

export function EmptyState({ icon, title, body, action }: { icon?: ReactNode; title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-2 rounded-card border border-dashed border-line bg-warm/60 px-6 py-10 text-center">
      <div className="grid h-11 w-11 place-items-center rounded-full bg-primary-50 text-primary-600">{icon ?? <Inbox className="h-5 w-5" aria-hidden />}</div>
      <h3 className="text-lg">{title}</h3>
      {body && <p className="max-w-sm text-sm text-muted">{body}</p>}
      {action && <div className="mt-2">{action}</div>}
    </div>
  )
}

export function errorMessage(e: unknown): string {
  if (isApiError(e)) return e.message
  if (e instanceof Error) return e.message
  return 'Something went wrong.'
}

export function ErrorState({ error, onRetry, title = 'Something went wrong' }: { error?: unknown; onRetry?: () => void; title?: string }) {
  return (
    <div role="alert" className="flex flex-col items-center gap-2 rounded-card border border-danger/30 bg-danger/5 px-6 py-8 text-center">
      <AlertTriangle className="h-6 w-6 text-danger" aria-hidden />
      <h3 className="text-lg">{title}</h3>
      <p className="max-w-sm text-sm text-muted">{error ? errorMessage(error) : 'Please try again.'}</p>
      {isApiError(error) && error.requestId && <p className="text-xs text-muted">Reference: {error.requestId}</p>}
      {onRetry && <Button variant="outline" size="sm" onClick={onRetry}><RefreshCw className="h-4 w-4" aria-hidden />Retry</Button>}
    </div>
  )
}

const tones = {
  info: { cls: 'border-info/30 bg-info/10', Icon: Info, color: 'text-info' },
  success: { cls: 'border-success/30 bg-success/10', Icon: CheckCircle2, color: 'text-success' },
  warning: { cls: 'border-warning/40 bg-warning/10', Icon: AlertTriangle, color: 'text-warning' },
  danger: { cls: 'border-danger/30 bg-danger/10', Icon: XCircle, color: 'text-danger' },
}
export function Alert({ tone = 'info', title, children, className, action }: { tone?: keyof typeof tones; title?: string; children?: ReactNode; className?: string; action?: ReactNode }) {
  const { cls, Icon, color } = tones[tone]
  return (
    <div role={tone === 'danger' ? 'alert' : 'status'} className={cn('flex items-start gap-2.5 rounded-ctl border p-3 text-sm', cls, className)}>
      <Icon className={cn('mt-0.5 h-4 w-4 shrink-0', color)} aria-hidden />
      <div className="min-w-0 flex-1">
        {title && <p className="font-semibold text-ink">{title}</p>}
        {children && <div className="text-ink/90">{children}</div>}
      </div>
      {action}
    </div>
  )
}

const badgeTones: Record<string, string> = {
  neutral: 'bg-line/60 text-ink', success: 'bg-success/15 text-success', warning: 'bg-warning/15 text-warning',
  danger: 'bg-danger/15 text-danger', info: 'bg-info/15 text-info', primary: 'bg-primary-100 text-primary-700', secondary: 'bg-secondary-100 text-secondary-700',
  accent: 'bg-accent-400/20 text-accent-600',
}
export function Badge({ tone = 'neutral', children, className }: { tone?: keyof typeof badgeTones; children: ReactNode; className?: string }) {
  return <span className={cn('inline-flex items-center gap-1 rounded-chip px-2 py-0.5 text-xs font-semibold', badgeTones[tone], className)}>{children}</span>
}

const statusTone: Record<string, keyof typeof badgeTones> = {
  approved: 'success', active: 'success', succeeded: 'success', resolved: 'success', responded: 'success', available: 'success', complete: 'success',
  pending: 'warning', reviewing: 'warning', under_review: 'warning', grace: 'warning', created: 'warning', partial: 'warning', reserved: 'warning', viewed: 'info', open: 'warning',
  rejected: 'danger', failed: 'danger', suspended: 'danger', reported: 'danger', dead: 'danger', deleted: 'danger',
  draft: 'neutral', expired: 'neutral', closed: 'neutral', cancelled: 'neutral', archived: 'neutral', superseded: 'neutral', dismissed: 'neutral', sold: 'secondary', unavailable: 'neutral',
  refunded: 'info', partially_refunded: 'info', queued: 'info', running: 'info', succeeded_job: 'success', unsubmitted: 'neutral',
}
export function StatusBadge({ status }: { status: string }) {
  return <Badge tone={statusTone[status] ?? 'neutral'}>{status.replace(/_/g, ' ')}</Badge>
}
