import { Fragment, type ReactNode } from 'react'

// Minimal, XSS-safe markdown → React (no innerHTML). Supports headings, lists, bold, italic, links, rules, paragraphs.
const safeHref = (u: string) => (/^(https?:|mailto:|\/)/i.test(u) ? u : '#')

function inline(text: string, keyBase: string): ReactNode[] {
  const out: ReactNode[] = []
  const re = /(\*\*[^*]+\*\*|\*[^*]+\*|\[[^\]]+\]\([^)]+\))/g
  let last = 0
  let m: RegExpExecArray | null
  let i = 0
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(text.slice(last, m.index))
    const tok = m[0]
    const k = `${keyBase}-${i++}`
    if (tok.startsWith('**')) out.push(<strong key={k}>{tok.slice(2, -2)}</strong>)
    else if (tok.startsWith('*')) out.push(<em key={k}>{tok.slice(1, -1)}</em>)
    else {
      const mm = /\[([^\]]+)\]\(([^)]+)\)/.exec(tok)!
      out.push(<a key={k} href={safeHref(mm[2])} className="text-primary-600 underline underline-offset-2" rel="noopener noreferrer">{mm[1]}</a>)
    }
    last = m.index + tok.length
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}

export function Markdown({ source }: { source: string }) {
  const lines = source.replace(/\r\n/g, '\n').split('\n')
  const blocks: ReactNode[] = []
  let para: string[] = []
  let list: { ordered: boolean; items: string[] } | null = null
  let n = 0
  const flushPara = () => { if (para.length) { blocks.push(<p key={n++} className="my-3 leading-relaxed">{inline(para.join(' '), `p${n}`)}</p>); para = [] } }
  const flushList = () => {
    if (!list) return
    const Tag = list.ordered ? 'ol' : 'ul'
    blocks.push(<Tag key={n++} className={`my-3 space-y-1 pl-5 ${list.ordered ? 'list-decimal' : 'list-disc'}`}>{list.items.map((it, i) => <li key={i}>{inline(it, `l${n}-${i}`)}</li>)}</Tag>)
    list = null
  }
  for (const raw of lines) {
    const line = raw.trimEnd()
    let m: RegExpMatchArray | null
    if (!line.trim()) { flushPara(); flushList(); continue }
    if ((m = line.match(/^(#{1,3})\s+(.*)$/))) {
      flushPara(); flushList()
      const lvl = m[1].length
      const cls = lvl === 1 ? 'mt-6 text-2xl' : lvl === 2 ? 'mt-5 text-xl' : 'mt-4 text-lg'
      const Tag = (`h${lvl + 1 > 4 ? 4 : lvl + 1}`) as 'h2' | 'h3' | 'h4'
      blocks.push(<Tag key={n++} className={cls}>{inline(m[2], `h${n}`)}</Tag>)
    } else if ((m = line.match(/^\s*[-*]\s+(.*)$/))) {
      flushPara()
      if (!list || list.ordered) { flushList(); list = { ordered: false, items: [] } }
      list.items.push(m[1])
    } else if ((m = line.match(/^\s*\d+[.)]\s+(.*)$/))) {
      flushPara()
      if (!list || !list.ordered) { flushList(); list = { ordered: true, items: [] } }
      list.items.push(m[1])
    } else if (/^---+$/.test(line.trim())) {
      flushPara(); flushList(); blocks.push(<hr key={n++} className="my-5 border-line" />)
    } else {
      flushList(); para.push(line.trim())
    }
  }
  flushPara(); flushList()
  return <Fragment>{blocks}</Fragment>
}
