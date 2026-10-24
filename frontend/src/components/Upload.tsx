import { useCallback, useRef, useState, type DragEvent } from 'react'
import { AlertCircle, CheckCircle2, RefreshCw, UploadCloud, X } from 'lucide-react'
import { upload, isApiError } from '@/api/client'
import { cn, uuid } from '@/lib/utils'
import { Button } from './ui/Button'

export interface UploadItem { id: string; file: File; progress: number; status: 'uploading' | 'error' | 'done'; error?: string }

interface Opts {
  path: string
  field?: string
  extra?: Record<string, string>
  accept: string[]
  maxBytes: number
  maxCount?: number
  currentCount?: number
  onUploaded?: (data: unknown) => void
}

/** Upload queue with client-side validation, progress, cancel and retry. The server re-validates everything. */
export function useUploads(o: Opts) {
  const [items, setItems] = useState<UploadItem[]>([])
  const [rejected, setRejected] = useState<string[]>([])
  const aborts = useRef(new Map<string, () => void>())
  const patch = useCallback((id: string, p: Partial<UploadItem>) => setItems((xs) => xs.map((x) => (x.id === id ? { ...x, ...p } : x))), [])

  const run = useCallback((item: UploadItem) => {
    const form = new FormData()
    form.append(o.field ?? 'file', item.file)
    for (const [k, v] of Object.entries(o.extra ?? {})) form.append(k, v)
    patch(item.id, { status: 'uploading', progress: 0, error: undefined })
    const h = upload<unknown>(o.path, form, (pct) => patch(item.id, { progress: pct }))
    aborts.current.set(item.id, h.abort)
    h.promise.then((data) => {
      aborts.current.delete(item.id)
      patch(item.id, { status: 'done', progress: 100 })
      o.onUploaded?.(data)
      setTimeout(() => setItems((xs) => xs.filter((x) => x.id !== item.id)), 1200)
    }).catch((e) => {
      aborts.current.delete(item.id)
      if (isApiError(e) && e.code === 'aborted') { setItems((xs) => xs.filter((x) => x.id !== item.id)); return }
      const errDetail = isApiError(e) && e.details?.length ? e.details.map((d) => d.message).join(', ') : undefined
      patch(item.id, { status: 'error', error: errDetail || (isApiError(e) ? e.message : 'Upload failed') })
    })
  }, [o, patch])

  const add = useCallback((files: FileList | File[]) => {
    const list = Array.from(files)
    const bad: string[] = []
    const ok: UploadItem[] = []
    let room = o.maxCount != null ? o.maxCount - (o.currentCount ?? 0) - items.filter((i) => i.status !== 'error').length : Infinity
    for (const f of list) {
      if (!o.accept.includes(f.type)) bad.push(`${f.name}: unsupported file type`)
      else if (f.size > o.maxBytes) bad.push(`${f.name}: larger than ${Math.round(o.maxBytes / 1048576)} MB`)
      else if (f.size === 0) bad.push(`${f.name}: file is empty`)
      else if (room <= 0) bad.push(`${f.name}: maximum number of files reached`)
      else { ok.push({ id: uuid(), file: f, progress: 0, status: 'uploading' }); room-- }
    }
    setRejected(bad)
    if (ok.length) { setItems((xs) => [...xs, ...ok]); ok.forEach(run) }
  }, [o, items, run])

  const cancel = (id: string) => { aborts.current.get(id)?.(); setItems((xs) => xs.filter((x) => x.id !== id)) }
  const retry = (id: string) => { const it = items.find((x) => x.id === id); if (it) run(it) }
  const dismiss = (id: string) => setItems((xs) => xs.filter((x) => x.id !== id))
  return { items, rejected, add, cancel, retry, dismiss, clearRejected: () => setRejected([]) }
}

export function DropZone({ label, hint, accept, multiple, onFiles, disabled }: { label: string; hint?: string; accept: string; multiple?: boolean; onFiles: (f: FileList) => void; disabled?: boolean }) {
  const [over, setOver] = useState(false)
  const drop = (e: DragEvent) => { e.preventDefault(); setOver(false); if (!disabled && e.dataTransfer.files.length) onFiles(e.dataTransfer.files) }
  return (
    <label onDragOver={(e) => { e.preventDefault(); setOver(true) }} onDragLeave={() => setOver(false)} onDrop={drop}
      className={cn('flex min-h-[112px] cursor-pointer flex-col items-center justify-center gap-1 rounded-card border-2 border-dashed p-4 text-center transition-colors focus-within:ring-2 focus-within:ring-primary',
        over ? 'border-primary-500 bg-primary-50' : 'border-line bg-warm/50 hover:bg-warm', disabled && 'pointer-events-none opacity-50')}>
      <UploadCloud className="h-6 w-6 text-primary-600" aria-hidden />
      <span className="text-sm font-semibold">{label}</span>
      {hint && <span className="text-xs text-muted">{hint}</span>}
      <input type="file" className="sr-only" accept={accept} multiple={multiple} disabled={disabled}
        onChange={(e) => { if (e.target.files?.length) onFiles(e.target.files); e.target.value = '' }} />
    </label>
  )
}

export function UploadList({ items, rejected, onCancel, onRetry, onDismiss }: { items: UploadItem[]; rejected: string[]; onCancel: (id: string) => void; onRetry: (id: string) => void; onDismiss: (id: string) => void }) {
  if (!items.length && !rejected.length) return null
  return (
    <div className="space-y-1.5" aria-live="polite">
      {rejected.map((r) => <p key={r} role="alert" className="flex items-center gap-1.5 text-sm text-danger"><AlertCircle className="h-4 w-4 shrink-0" aria-hidden />{r}</p>)}
      {items.map((i) => (
        <div key={i.id} className="flex items-center gap-2 rounded-ctl border border-line bg-surface p-2 text-sm">
          <div className="min-w-0 flex-1">
            <p className="truncate font-medium">{i.file.name}</p>
            {i.status === 'error' ? <p className="text-xs text-danger">{i.error}</p> : (
              <div className="mt-1 h-1.5 overflow-hidden rounded-full bg-line" role="progressbar" aria-label={`Uploading ${i.file.name}`} aria-valuenow={i.progress} aria-valuemin={0} aria-valuemax={100}>
                <div className="h-full rounded-full bg-primary-500 transition-all" style={{ width: `${i.progress}%` }} /></div>)}
          </div>
          {i.status === 'done' && <CheckCircle2 className="h-5 w-5 text-success" aria-label="Uploaded" />}
          {i.status === 'uploading' && <Button variant="ghost" size="icon" aria-label={`Cancel upload of ${i.file.name}`} onClick={() => onCancel(i.id)}><X className="h-4 w-4" /></Button>}
          {i.status === 'error' && <><Button variant="outline" size="sm" onClick={() => onRetry(i.id)}><RefreshCw className="h-4 w-4" aria-hidden />Retry</Button>
            <Button variant="ghost" size="icon" aria-label="Dismiss" onClick={() => onDismiss(i.id)}><X className="h-4 w-4" /></Button></>}
        </div>
      ))}
    </div>
  )
}
