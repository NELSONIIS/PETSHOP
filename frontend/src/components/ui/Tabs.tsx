import { cn } from '@/lib/utils'

export interface TabItem { value: string; label: string; count?: number }

/** Simple accessible segmented control for status filters (buttons with aria-pressed). */
export function TabBar({ items, value, onChange, label }: { items: TabItem[]; value: string; onChange: (v: string) => void; label: string }) {
  return (
    <div role="group" aria-label={label} className="scroll-x -mx-4 flex gap-1.5 overflow-x-auto px-4 md:mx-0 md:px-0">
      {items.map((t) => (
        <button key={t.value} type="button" aria-pressed={value === t.value} onClick={() => onChange(t.value)}
          className={cn('inline-flex h-10 shrink-0 items-center gap-1.5 rounded-full border px-3.5 text-sm font-medium transition-colors',
            value === t.value ? 'border-primary-600 bg-primary-600 text-white dark:bg-primary dark:text-primary-fg' : 'border-line bg-surface text-ink hover:bg-warm')}>
          {t.label}
          {t.count !== undefined && <span className={cn('tnum rounded-full px-1.5 text-xs', value === t.value ? 'bg-white/25' : 'bg-line/70')}>{t.count}</span>}
        </button>
      ))}
    </div>
  )
}
