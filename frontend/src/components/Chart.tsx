import { formatDate } from '@/lib/utils'

interface Pt { label: string; value: number }

/** Dependency-free SVG charts with a visually-hidden data table for screen readers. */
export function LineChart({ data, title, color = 'rgb(var(--primary))' }: { data: Pt[]; title: string; color?: string }) {
  const w = 600, h = 180, pad = 24
  const max = Math.max(1, ...data.map((d) => d.value))
  const x = (i: number) => pad + (data.length <= 1 ? 0 : (i * (w - pad * 2)) / (data.length - 1))
  const y = (v: number) => h - pad - (v / max) * (h - pad * 2)
  const pts = data.map((d, i) => `${x(i)},${y(d.value)}`).join(' ')
  return (
    <figure>
      <svg viewBox={`0 0 ${w} ${h}`} className="h-auto w-full" role="img" aria-label={title}>
        <title>{title}</title>
        {[0, 0.5, 1].map((t) => <g key={t}><line x1={pad} x2={w - pad} y1={y(max * t)} y2={y(max * t)} stroke="rgb(var(--border))" /><text x={4} y={y(max * t) + 4} fontSize="10" fill="rgb(var(--text-muted))">{Math.round(max * t)}</text></g>)}
        {data.length > 0 && <polyline fill="none" stroke={color} strokeWidth="2.5" strokeLinejoin="round" strokeLinecap="round" points={pts} />}
        {data.length > 0 && <><text x={pad} y={h - 6} fontSize="10" fill="rgb(var(--text-muted))">{data[0].label}</text><text x={w - pad} y={h - 6} fontSize="10" textAnchor="end" fill="rgb(var(--text-muted))">{data[data.length - 1].label}</text></>}
      </svg>
      <table className="sr-only"><caption>{title}</caption><tbody>{data.map((d) => <tr key={d.label}><th scope="row">{d.label}</th><td>{d.value}</td></tr>)}</tbody></table>
    </figure>
  )
}

export function BarChart({ data, title, format }: { data: Pt[]; title: string; format?: (v: number) => string }) {
  const w = 600, h = 180, pad = 24
  const max = Math.max(1, ...data.map((d) => d.value))
  const bw = data.length ? (w - pad * 2) / data.length : 0
  return (
    <figure>
      <svg viewBox={`0 0 ${w} ${h}`} className="h-auto w-full" role="img" aria-label={title}>
        <title>{title}</title>
        <line x1={pad} x2={w - pad} y1={h - pad} y2={h - pad} stroke="rgb(var(--border))" />
        {data.map((d, i) => { const bh = (d.value / max) * (h - pad * 2); return <rect key={d.label} x={pad + i * bw + 1} y={h - pad - bh} width={Math.max(1, bw - 2)} height={bh} rx="2" fill="rgb(var(--secondary))"><title>{`${d.label}: ${format ? format(d.value) : d.value}`}</title></rect> })}
        {data.length > 0 && <><text x={pad} y={h - 6} fontSize="10" fill="rgb(var(--text-muted))">{data[0].label}</text><text x={w - pad} y={h - 6} fontSize="10" textAnchor="end" fill="rgb(var(--text-muted))">{data[data.length - 1].label}</text></>}
      </svg>
      <table className="sr-only"><caption>{title}</caption><tbody>{data.map((d) => <tr key={d.label}><th scope="row">{d.label}</th><td>{format ? format(d.value) : d.value}</td></tr>)}</tbody></table>
    </figure>
  )
}
export const dayLabel = (iso: string) => formatDate(iso).replace(/ \d{4}$/, '')
