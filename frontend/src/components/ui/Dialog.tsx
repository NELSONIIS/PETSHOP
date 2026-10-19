import * as RD from '@radix-ui/react-dialog'
import { X } from 'lucide-react'
import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { Button } from './Button'

/** Accessible modal (Radix): focus trap, ESC, aria. On phones it renders as a bottom sheet. */
export function Dialog({ open, onOpenChange, title, description, children, footer, size = 'md', sheetOnly }: {
  open: boolean; onOpenChange: (o: boolean) => void; title: string; description?: string; children?: ReactNode
  footer?: ReactNode; size?: 'sm' | 'md' | 'lg' | 'xl'; sheetOnly?: boolean
}) {
  const width = { sm: 'sm:max-w-sm', md: 'sm:max-w-lg', lg: 'sm:max-w-2xl', xl: 'sm:max-w-4xl' }[size]
  return (
    <RD.Root open={open} onOpenChange={onOpenChange}>
      <RD.Portal>
        <RD.Overlay className="fixed inset-0 z-50 animate-fade-in bg-black/50" />
        <RD.Content
          className={cn(
            'fixed z-50 flex max-h-[92dvh] w-full flex-col overflow-hidden bg-surface shadow-raised animate-slide-up focus:outline-none',
            'bottom-0 left-0 rounded-t-sheet', !sheetOnly && cn('sm:bottom-auto sm:left-1/2 sm:top-1/2 sm:-translate-x-1/2 sm:-translate-y-1/2 sm:rounded-sheet', width),
          )}
          aria-describedby={description ? undefined : undefined}
        >
          <div className="flex items-start justify-between gap-3 border-b border-line px-4 py-3">
            <div className="min-w-0">
              <RD.Title className="text-lg font-semibold">{title}</RD.Title>
              {description ? <RD.Description className="mt-0.5 text-sm text-muted">{description}</RD.Description> : <RD.Description className="sr-only">{title}</RD.Description>}
            </div>
            <RD.Close asChild><Button variant="ghost" size="icon" aria-label="Close" className="-mr-2 -mt-1"><X className="h-5 w-5" /></Button></RD.Close>
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">{children}</div>
          {footer && <div className="safe-bottom flex flex-wrap justify-end gap-2 border-t border-line bg-warm/50 px-4 py-3">{footer}</div>}
        </RD.Content>
      </RD.Portal>
    </RD.Root>
  )
}

export function ConfirmDialog({ open, onOpenChange, title, body, confirmLabel = 'Confirm', destructive, loading, onConfirm }: {
  open: boolean; onOpenChange: (o: boolean) => void; title: string; body: ReactNode; confirmLabel?: string
  destructive?: boolean; loading?: boolean; onConfirm: () => void
}) {
  return (
    <Dialog open={open} onOpenChange={onOpenChange} title={title} size="sm"
      footer={<>
        <Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
        <Button variant={destructive ? 'destructive' : 'primary'} loading={loading} onClick={onConfirm}>{confirmLabel}</Button>
      </>}>
      <div className="text-sm text-ink/90">{body}</div>
    </Dialog>
  )
}
