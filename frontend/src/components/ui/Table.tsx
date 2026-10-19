import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'
import { EmptyState, ErrorState, Skeleton } from './Feedback'

export interface Column<T> { header: string; cell: (row: T) => ReactNode; className?: string; hideOnMobile?: boolean }

/** Responsive data table: a real <table> on md+, stacked cards on phones. */
export function DataTable<T>({ rows, columns, rowKey, loading, error, onRetry, empty, onRowClick }: {
  rows?: T[]; columns: Column<T>[]; rowKey: (r: T) => string; loading?: boolean; error?: unknown; onRetry?: () => void
  empty?: string; onRowClick?: (r: T) => void
}) {
  if (error) return <ErrorState error={error} onRetry={onRetry} />
  if (loading) return <div className="space-y-2">{Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} className="h-12 w-full" />)}</div>
  if (!rows?.length) return <EmptyState title={empty ?? 'Nothing here yet'} />
  return (
    <>
      <div className="card hidden overflow-x-auto md:block">
        <table className="w-full text-left text-sm">
          <thead className="border-b border-line bg-warm/60 text-xs uppercase tracking-wide text-muted">
            <tr>{columns.map((c) => <th key={c.header} scope="col" className={cn('px-3 py-2.5 font-semibold', c.className)}>{c.header}</th>)}</tr>
          </thead>
          <tbody className="divide-y divide-line">
            {rows.map((r) => (
              <tr key={rowKey(r)} className={cn(onRowClick && 'cursor-pointer hover:bg-warm/60')} onClick={onRowClick ? () => onRowClick(r) : undefined}>
                {columns.map((c) => <td key={c.header} className={cn('px-3 py-2.5 align-middle', c.className)}>{c.cell(r)}</td>)}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ul className="space-y-2 md:hidden">
        {rows.map((r) => (
          <li key={rowKey(r)} className={cn('card space-y-1.5 p-3', onRowClick && 'cursor-pointer')} onClick={onRowClick ? () => onRowClick(r) : undefined}>
            {columns.filter((c) => !c.hideOnMobile).map((c) => (
              <div key={c.header} className="flex items-start justify-between gap-3 text-sm">
                <span className="shrink-0 text-xs text-muted">{c.header}</span>
                <span className="min-w-0 text-right">{c.cell(r)}</span>
              </div>
            ))}
          </li>
        ))}
      </ul>
    </>
  )
}
