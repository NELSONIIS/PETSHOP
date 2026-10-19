import { useCallback, useEffect, useState } from 'react'
import { ChevronLeft, ChevronRight, Expand } from 'lucide-react'
import type { Image } from '@/api/types'
import { cn } from '@/lib/utils'
import { Dialog } from './ui/Dialog'
import { PlaceholderImage } from './Pet'

export function Gallery({ images, title, icon }: { images: Image[]; title: string; icon?: string }) {
  const [i, setI] = useState(0)
  const [full, setFull] = useState(false)
  const n = images.length
  const go = useCallback((d: number) => setI((x) => (x + d + n) % n), [n])
  useEffect(() => {
    if (!full) return
    const h = (e: KeyboardEvent) => { if (e.key === 'ArrowRight') go(1); if (e.key === 'ArrowLeft') go(-1) }
    window.addEventListener('keydown', h)
    return () => window.removeEventListener('keydown', h)
  }, [full, go])
  if (!n) return <PlaceholderImage icon={icon} className="aspect-[4/3] w-full rounded-card" />
  const cur = images[i]
  return (
    <div className="space-y-2">
      <div className="relative aspect-[4/3] overflow-hidden rounded-card bg-warm md:aspect-[16/11]">
        <img src={cur.medium || cur.large} alt={cur.alt_text || `${title} — photo ${i + 1} of ${n}`} className="h-full w-full object-cover" />
        <button type="button" onClick={() => setFull(true)} aria-label="View photos full screen" className="absolute bottom-2 right-2 grid h-10 w-10 place-items-center rounded-full bg-black/55 text-white"><Expand className="h-5 w-5" /></button>
        {n > 1 && <>
          <button type="button" onClick={() => go(-1)} aria-label="Previous photo" className="absolute left-2 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center rounded-full bg-black/45 text-white"><ChevronLeft className="h-5 w-5" /></button>
          <button type="button" onClick={() => go(1)} aria-label="Next photo" className="absolute right-2 top-1/2 grid h-10 w-10 -translate-y-1/2 place-items-center rounded-full bg-black/45 text-white"><ChevronRight className="h-5 w-5" /></button>
          <span className="absolute bottom-2 left-2 rounded-full bg-black/55 px-2 py-0.5 text-xs text-white tnum">{i + 1} / {n}</span>
        </>}
      </div>
      {n > 1 && (
        <ul className="scroll-x flex gap-2 overflow-x-auto" aria-label="Photo thumbnails">
          {images.map((im, k) => (
            <li key={im.id}>
              <button type="button" onClick={() => setI(k)} aria-label={`Show photo ${k + 1}`} aria-current={k === i}
                className={cn('block h-14 w-[72px] overflow-hidden rounded-chip border-2', k === i ? 'border-primary-600' : 'border-transparent opacity-80')}>
                <img src={im.thumb} alt="" loading="lazy" className="h-full w-full object-cover" />
              </button>
            </li>
          ))}
        </ul>
      )}
      <Dialog open={full} onOpenChange={setFull} title={`${title} — photos`} size="xl">
        <div className="relative">
          <img src={cur.large || cur.medium} alt={cur.alt_text || `${title} — photo ${i + 1}`} className="mx-auto max-h-[70dvh] w-auto rounded-card object-contain" />
          {n > 1 && <div className="mt-3 flex justify-center gap-3">
            <button type="button" onClick={() => go(-1)} aria-label="Previous photo" className="grid h-11 w-11 place-items-center rounded-full border border-line"><ChevronLeft /></button>
            <span className="grid place-items-center text-sm tnum">{i + 1} / {n}</span>
            <button type="button" onClick={() => go(1)} aria-label="Next photo" className="grid h-11 w-11 place-items-center rounded-full border border-line"><ChevronRight /></button>
          </div>}
        </div>
      </Dialog>
    </div>
  )
}
