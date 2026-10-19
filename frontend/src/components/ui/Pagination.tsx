import { ChevronLeft, ChevronRight } from 'lucide-react'
import type { Meta } from '@/api/types'
import { Button } from './Button'

export function Pagination({ meta, onPage }: { meta?: Meta; onPage: (p: number) => void }) {
  if (!meta || meta.total_pages <= 1) return null
  return (
    <nav aria-label="Pagination" className="flex items-center justify-between gap-3 pt-3">
      <p className="text-sm text-muted tnum">Page {meta.page} of {meta.total_pages} · {meta.total} results</p>
      <div className="flex gap-2">
        <Button variant="outline" size="sm" disabled={meta.page <= 1} onClick={() => onPage(meta.page - 1)} aria-label="Previous page"><ChevronLeft className="h-4 w-4" />Prev</Button>
        <Button variant="outline" size="sm" disabled={meta.page >= meta.total_pages} onClick={() => onPage(meta.page + 1)} aria-label="Next page">Next<ChevronRight className="h-4 w-4" /></Button>
      </div>
    </nav>
  )
}
