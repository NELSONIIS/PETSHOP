import { useState, type FormEvent } from 'react'
import { Link, NavLink, useNavigate, useSearchParams } from 'react-router-dom'
import * as DM from '@radix-ui/react-dropdown-menu'
import { Bell, ChevronDown, LayoutDashboard, LocateFixed, LogOut, MapPin, Menu, Moon, Search, Sun, User as UserIcon } from 'lucide-react'
import { useAuth, homeFor } from '@/auth/AuthContext'
import { useGet } from '@/api/hooks'
import { useTheme } from '@/lib/theme'
import { useLocationPref } from '@/lib/location'
import { cn } from '@/lib/utils'
import { Logo } from './Brand'
import { Button, LinkButton } from './ui/Button'
import { Dialog } from './ui/Dialog'
import { Field, Input } from './ui/Form'
import { useToast } from './ui/Toast'

export function ThemeToggle() {
  const { theme, toggle } = useTheme()
  return (
    <Button variant="ghost" size="icon" onClick={toggle} aria-label={theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}>
      {theme === 'dark' ? <Sun className="h-5 w-5" /> : <Moon className="h-5 w-5" />}
    </Button>
  )
}

export function SearchBar({ className, autoFocus }: { className?: string; autoFocus?: boolean }) {
  const nav = useNavigate()
  const [sp] = useSearchParams()
  const [q, setQ] = useState(sp.get('q') ?? '')
  const submit = (e: FormEvent) => { e.preventDefault(); nav(`/pets${q.trim() ? `?q=${encodeURIComponent(q.trim())}` : ''}`) }
  return (
    <form role="search" onSubmit={submit} className={cn('relative', className)}>
      <label htmlFor="global-search" className="sr-only">Search pets</label>
      <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted" aria-hidden />
      <input id="global-search" value={q} onChange={(e) => setQ(e.target.value)} autoFocus={autoFocus} placeholder="Search breeds, pets, cities…" enterKeyHint="search"
        className="h-11 w-full rounded-full border border-line bg-surface pl-9 pr-24 text-base placeholder:text-muted/70 focus-visible:border-primary" />
      <Button type="submit" size="sm" className="absolute right-1 top-1 h-9 rounded-full px-4">Search</Button>
    </form>
  )
}

export function LocationSelector() {
  const { loc, setLoc, locate } = useLocationPref()
  const [open, setOpen] = useState(false)
  const [city, setCity] = useState(loc.city && loc.city !== 'Near me' ? loc.city : '')
  const [busy, setBusy] = useState(false)
  const toast = useToast()
  const label = loc.city || 'All India'
  const useMine = async () => {
    setBusy(true)
    try { await locate(); setOpen(false); toast.success('Showing pets near you') } catch (e) { toast.error((e as Error).message) } finally { setBusy(false) }
  }
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} aria-label={`Location: ${label}. Change location`}
        className="inline-flex h-10 max-w-[150px] items-center gap-1 rounded-full border border-line bg-surface px-3 text-sm font-medium hover:bg-warm">
        <MapPin className="h-4 w-4 shrink-0 text-accent-500" aria-hidden /><span className="truncate">{label}</span><ChevronDown className="h-3.5 w-3.5 shrink-0 text-muted" aria-hidden />
      </button>
      <Dialog open={open} onOpenChange={setOpen} title="Choose your location" description="We use it to show nearby pets. Sellers never see your location."
        footer={<>
          {(loc.city || loc.lat) && <Button variant="ghost" onClick={() => { setLoc({}); setCity(''); setOpen(false) }}>Clear</Button>}
          <Button onClick={() => { setLoc({ city: city.trim() || undefined }); setOpen(false) }}>Apply</Button>
        </>}>
        <div className="space-y-3">
          <Button variant="secondary" className="w-full" loading={busy} onClick={useMine}><LocateFixed className="h-4 w-4" aria-hidden />Use my current location</Button>
          <Field label="Or enter a city"><Input value={city} onChange={(e) => setCity(e.target.value)} placeholder="e.g. Pune" autoComplete="address-level2" /></Field>
        </div>
      </Dialog>
    </>
  )
}

export function NotificationBell() {
  const { user } = useAuth()
  const { items } = useGet<{ count: number }>(user ? '/notifications/unread-count' : null, undefined, { refetchInterval: 60_000 })
  if (!user) return null
  const base = user.account_type === 'staff' ? '/admin' : user.account_type === 'seller' ? '/seller' : '/buyer'
  const count = items?.count ?? 0
  return (
    <Link to={user.account_type === 'staff' ? '/admin' : `${base}/notifications`} aria-label={count ? `Notifications, ${count} unread` : 'Notifications'}
      className="relative grid h-11 w-11 place-items-center rounded-full hover:bg-warm">
      <Bell className="h-5 w-5" aria-hidden />
      {count > 0 && <span className="absolute right-1.5 top-1.5 grid h-4 min-w-4 place-items-center rounded-full bg-accent-500 px-1 text-[10px] font-bold text-white tnum">{count > 99 ? '99+' : count}</span>}
    </Link>
  )
}

export function UserMenu() {
  const { user, logout } = useAuth()
  const nav = useNavigate()
  if (!user) return null
  const home = homeFor(user)
  const profile = user.account_type === 'staff' ? '/admin/security' : `${home}/profile`
  return (
    <DM.Root>
      <DM.Trigger asChild>
        <button aria-label="Account menu" className="flex h-11 items-center gap-1.5 rounded-full pl-1 pr-2 hover:bg-warm">
          <span className="grid h-8 w-8 place-items-center rounded-full bg-primary-600 text-sm font-bold text-white dark:bg-primary dark:text-primary-fg">{user.name.slice(0, 1).toUpperCase()}</span>
          <ChevronDown className="hidden h-3.5 w-3.5 text-muted sm:block" aria-hidden />
        </button>
      </DM.Trigger>
      <DM.Portal>
        <DM.Content align="end" sideOffset={6} className="z-50 min-w-[210px] rounded-card border border-line bg-surface p-1 shadow-raised">
          <div className="px-3 py-2"><p className="truncate text-sm font-semibold">{user.name}</p><p className="truncate text-xs text-muted">{user.email}</p></div>
          <DM.Separator className="my-1 h-px bg-line" />
          {[{ to: home, label: 'Dashboard', icon: LayoutDashboard }, { to: profile, label: 'Profile & security', icon: UserIcon }].map((i) => (
            <DM.Item key={i.to} onSelect={() => nav(i.to)} className="flex h-11 cursor-pointer items-center gap-2 rounded-ctl px-3 text-sm outline-none data-[highlighted]:bg-warm"><i.icon className="h-4 w-4" aria-hidden />{i.label}</DM.Item>
          ))}
          <DM.Item onSelect={async () => { await logout(); nav('/') }} className="flex h-11 cursor-pointer items-center gap-2 rounded-ctl px-3 text-sm text-danger outline-none data-[highlighted]:bg-warm"><LogOut className="h-4 w-4" aria-hidden />Sign out</DM.Item>
        </DM.Content>
      </DM.Portal>
    </DM.Root>
  )
}

const links = [{ to: '/pets', label: 'Browse pets' }, { to: '/pricing', label: 'Membership' }, { to: '/safety', label: 'Safety' }]

export function Header() {
  const { user } = useAuth()
  const [menu, setMenu] = useState(false)
  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg/95 backdrop-blur">
      <div className="container-page flex h-14 items-center gap-2 md:gap-4">
        <Button variant="ghost" size="icon" className="md:hidden" aria-label="Open menu" onClick={() => setMenu(true)}><Menu className="h-5 w-5" /></Button>
        <Logo />
        <nav aria-label="Primary" className="ml-2 hidden items-center gap-1 md:flex">
          {links.map((l) => <NavLink key={l.to} to={l.to} className={({ isActive }) => cn('rounded-ctl px-3 py-2 text-sm font-medium hover:bg-warm', isActive && 'text-primary-600')}>{l.label}</NavLink>)}
        </nav>
        <SearchBar className="mx-2 hidden max-w-md flex-1 lg:block" />
        <div className="ml-auto flex items-center gap-1">
          <LocationSelector />
          <ThemeToggle />
          {user ? <><NotificationBell /><UserMenu /></> : (
            <div className="hidden items-center gap-1.5 sm:flex">
              <LinkButton to="/login" variant="ghost" size="sm">Log in</LinkButton>
              <LinkButton to="/register" size="sm">Sign up</LinkButton>
            </div>
          )}
        </div>
      </div>
      <Dialog open={menu} onOpenChange={setMenu} title="Menu" sheetOnly>
        <nav aria-label="Mobile" className="flex flex-col">
          <SearchBar className="mb-3" />
          {[...links, { to: '/faq', label: 'FAQ' }, { to: '/support', label: 'Support' }, { to: '/register/seller', label: 'Sell your pets' }].map((l) => (
            <Link key={l.to} to={l.to} onClick={() => setMenu(false)} className="flex h-12 items-center border-b border-line text-base font-medium">{l.label}</Link>
          ))}
          {!user && <div className="mt-4 grid grid-cols-2 gap-2">
            <LinkButton to="/login" variant="outline" onClick={() => setMenu(false)}>Log in</LinkButton>
            <LinkButton to="/register" onClick={() => setMenu(false)}>Sign up</LinkButton>
          </div>}
        </nav>
      </Dialog>
    </header>
  )
}
