import { Link } from 'react-router-dom'
import { cn } from '@/lib/utils'

export function LogoMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={cn('h-8 w-8', className)} aria-hidden>
      <rect width="64" height="64" rx="16" className="fill-primary-600 dark:fill-primary" />
      <g className="fill-white dark:fill-primary-fg">
        <ellipse cx="20" cy="26" rx="6" ry="8" /><ellipse cx="44" cy="26" rx="6" ry="8" /><ellipse cx="32" cy="18" rx="5.5" ry="7.5" />
        <path d="M32 30c-9 0-15 7-15 13 0 5 4 8 9 7 3-.7 4-1.5 6-1.5s3 .8 6 1.5c5 1 9-2 9-7 0-6-6-13-15-13z" />
      </g>
    </svg>
  )
}

export function Logo({ to = '/', className }: { to?: string; className?: string }) {
  return (
    <Link to={to} aria-label="PETORA home" className={cn('inline-flex items-center gap-2', className)}>
      <LogoMark />
      <span className="text-xl font-bold tracking-tight text-primary-700 dark:text-primary-700">PETORA</span>
    </Link>
  )
}
