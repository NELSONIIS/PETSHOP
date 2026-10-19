import { useState, type ReactNode } from 'react'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { Field, Textarea } from '@/components/ui/Form'
import { Pagination } from '@/components/ui/Pagination'
import { DataTable, type Column } from '@/components/ui/Table'
import { useGet } from '@/api/hooks'
import type { Envelope } from '@/api/types'

/** Paged admin list: owns page + filters, feeds a DataTable and Pagination. */
export function usePagedList<T>(path: string | null, initial: Record<string, string> = {}, perPage = 20) {
  const [filters, setFilters] = useState<Record<string, string>>(initial)
  const [page, setPage] = useState(1)
  const q = useGet<T[]>(path, { ...filters, page, per_page: perPage }, { keepPrevious: true })
  const set = (k: string, v: string) => { setFilters((f) => ({ ...f, [k]: v })); setPage(1) }
  return { q, filters, set, page, setPage }
}

export function AdminTable<T>({ list, columns, rowKey, empty, onRowClick }: { list: ReturnType<typeof usePagedList<T>>; columns: Column<T>[]; rowKey: (r: T) => string; empty?: string; onRowClick?: (r: T) => void }) {
  const { q } = list
  return (
    <>
      <DataTable rows={q.items} loading={q.isLoading} error={q.error} onRetry={() => q.refetch()} columns={columns} rowKey={rowKey} empty={empty} onRowClick={onRowClick} />
      <Pagination meta={q.meta} onPage={list.setPage} />
    </>
  )
}

export function FilterBar({ children }: { children: ReactNode }) {
  return <div className="flex flex-wrap items-end gap-2" role="search">{children}</div>
}

/** Dialog that requires a typed reason before confirming a sensitive action. */
export function ReasonDialog({ open, onOpenChange, title, label = 'Reason', confirmLabel, destructive, loading, optional, onConfirm, help }: {
  open: boolean; onOpenChange: (o: boolean) => void; title: string; label?: string; confirmLabel: string; destructive?: boolean; loading?: boolean
  optional?: boolean; onConfirm: (reason: string) => void; help?: string
}) {
  const [reason, setReason] = useState('')
  const [err, setErr] = useState('')
  return (
    <Dialog open={open} onOpenChange={(o) => { onOpenChange(o); if (!o) { setReason(''); setErr('') } }} title={title} size="sm"
      footer={<><Button variant="outline" onClick={() => onOpenChange(false)}>Cancel</Button>
        <Button variant={destructive ? 'destructive' : 'primary'} loading={loading} onClick={() => { if (!optional && reason.trim().length < 3) { setErr('Please enter a reason (at least 3 characters).'); return } onConfirm(reason.trim()) }}>{confirmLabel}</Button></>}>
      <Field label={label} error={err} hint={help} required={!optional}><Textarea value={reason} onChange={(e) => setReason(e.target.value)} rows={3} maxLength={1000} /></Field>
    </Dialog>
  )
}

export const unwrap = <T,>(e?: Envelope<T>) => e?.data
export const shortId = (id: string) => id.slice(0, 8)
