import { useState, type ComponentType } from 'react'
import { Link, NavLink, Outlet, useLocation } from 'react-router-dom'
import {
  BarChart3, Bell, BookOpen, ClipboardList, Crown, Flag, Heart, Home, LayoutDashboard, ListChecks, Menu, MessageSquare, PawPrint,
  Receipt, ScrollText, Search, Settings, ShieldCheck, Tags, Timer, User, Users, Wallet, BadgeCheck, Mail, Plus,
} from 'lucide-react'
import { useAuth } from '@/auth/AuthContext'
import { Logo } from '@/components/Brand'
import { NotificationBell, ThemeToggle, UserMenu } from '@/components/Header'
import { Alert } from '@/components/ui/Feedback'
import { Button } from '@/components/ui/Button'
import { Dialog } from '@/components/ui/Dialog'
import { cn } from '@/lib/utils'

interface NavItem { to: string; label: string; icon: ComponentType<{ className?: string }>; end?: boolean; perm?: string }

export const buyerNav: NavItem[] = [
  { to: '/buyer', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/buyer/favourites', label: 'Favourites', icon: Heart },
  { to: '/buyer/enquiries', label: 'Enquiries', icon: MessageSquare },
  { to: '/buyer/membership', label: 'Membership', icon: Crown },
  { to: '/buyer/billing', label: 'Billing', icon: Receipt },
  { to: '/buyer/notifications', label: 'Notifications', icon: Bell },
  { to: '/buyer/profile', label: 'Profile & security', icon: User },
]
const buyerBottom: NavItem[] = [
  { to: '/buyer', label: 'Home', icon: Home, end: true }, { to: '/pets', label: 'Search', icon: Search },
  { to: '/buyer/favourites', label: 'Saved', icon: Heart }, { to: '/buyer/enquiries', label: 'Enquiries', icon: MessageSquare }, { to: '/buyer/profile', label: 'Profile', icon: User },
]
export const sellerNav: NavItem[] = [
  { to: '/seller', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/seller/listings', label: 'Pet listings', icon: PawPrint },
  { to: '/seller/enquiries', label: 'Enquiry inbox', icon: MessageSquare },
  { to: '/seller/analytics', label: 'Analytics', icon: BarChart3 },
  { to: '/seller/membership', label: 'Membership', icon: Crown },
  { to: '/seller/billing', label: 'Billing', icon: Receipt },
  { to: '/seller/verification', label: 'Verification', icon: BadgeCheck },
  { to: '/seller/notifications', label: 'Notifications', icon: Bell },
  { to: '/seller/profile', label: 'Profile & settings', icon: User },
]
const sellerBottom: NavItem[] = [
  { to: '/seller', label: 'Dashboard', icon: LayoutDashboard, end: true }, { to: '/seller/listings', label: 'Listings', icon: PawPrint },
  { to: '/seller/enquiries', label: 'Enquiries', icon: MessageSquare }, { to: '/seller/profile', label: 'Profile', icon: User },
]
export const adminNav: NavItem[] = [
  { to: '/admin', label: 'Overview', icon: LayoutDashboard, end: true, perm: 'dashboard.view' },
  { to: '/admin/users', label: 'Users', icon: Users, perm: 'users.view' },
  { to: '/admin/verifications', label: 'Seller verification', icon: BadgeCheck, perm: 'sellers.verify' },
  { to: '/admin/listings', label: 'Listing moderation', icon: ListChecks, perm: 'listings.moderate' },
  { to: '/admin/categories', label: 'Categories & breeds', icon: Tags, perm: 'catalog.manage' },
  { to: '/admin/plans', label: 'Subscription plans', icon: Crown, perm: 'plans.manage' },
  { to: '/admin/subscriptions', label: 'Subscriptions', icon: ClipboardList, perm: 'subscriptions.view' },
  { to: '/admin/payments', label: 'Payments & refunds', icon: Wallet, perm: 'payments.view' },
  { to: '/admin/reports', label: 'Reports & disputes', icon: Flag, perm: 'reports.manage' },
  { to: '/admin/enquiries', label: 'Enquiry abuse review', icon: MessageSquare, perm: 'reports.manage' },
  { to: '/admin/templates', label: 'Notification templates', icon: Mail, perm: 'content.manage' },
  { to: '/admin/content', label: 'Content & legal', icon: BookOpen, perm: 'content.manage' },
  { to: '/admin/settings', label: 'Platform settings', icon: Settings, perm: 'settings.manage' },
  { to: '/admin/security', label: 'Security & permissions', icon: ShieldCheck },
  { to: '/admin/audit', label: 'Audit logs', icon: ScrollText, perm: 'audit.view' },
  { to: '/admin/jobs', label: 'Background jobs', icon: Timer, perm: 'settings.manage' },
]

function SideLink({ it, onClick }: { it: NavItem; onClick?: () => void }) {
  return (
    <NavLink to={it.to} end={it.end} onClick={onClick}
      className={({ isActive }) => cn('flex h-11 items-center gap-2.5 rounded-ctl px-3 text-sm font-medium transition-colors hover:bg-warm', isActive && 'bg-primary-50 text-primary-700')}>
      <it.icon className="h-[18px] w-[18px]" aria-hidden />{it.label}
    </NavLink>
  )
}

export function PortalLayout({ kind }: { kind: 'buyer' | 'seller' | 'admin' }) {
  const { user, can } = useAuth()
  const loc = useLocation()
  const [menu, setMenu] = useState(false)
  const items = (kind === 'buyer' ? buyerNav : kind === 'seller' ? sellerNav : adminNav).filter((i) => !i.perm || can(i.perm))
  const bottom = kind === 'buyer' ? buyerBottom : kind === 'seller' ? sellerBottom : null
  const title = { buyer: 'Buyer', seller: 'Seller', admin: 'Admin' }[kind]
  const hideFab = loc.pathname.startsWith('/seller/listings/new') || /\/seller\/listings\/[^/]+\/edit/.test(loc.pathname)
  return (
    <div className="min-h-dvh bg-warm">
      <header className="sticky top-0 z-40 border-b border-line bg-bg/95 backdrop-blur">
        <div className="flex h-14 items-center gap-2 px-3 md:px-5">
          {(kind === 'admin' || !bottom) && <Button variant="ghost" size="icon" className="lg:hidden" aria-label="Open navigation" onClick={() => setMenu(true)}><Menu className="h-5 w-5" /></Button>}
          <Logo />
          <span className="rounded-chip bg-primary-100 px-2 py-0.5 text-xs font-semibold text-primary-700">{title}</span>
          <div className="ml-auto flex items-center gap-1">
            <Link to="/pets" className="mr-1 hidden h-10 items-center rounded-ctl px-3 text-sm font-medium hover:bg-warm sm:inline-flex">Marketplace</Link>
            <ThemeToggle /><NotificationBell /><UserMenu />
          </div>
        </div>
      </header>
      <div className="mx-auto flex max-w-[1400px]">
        <aside className="sticky top-14 hidden h-[calc(100dvh-56px)] w-60 shrink-0 overflow-y-auto border-r border-line bg-bg p-3 lg:block">
          <nav aria-label={`${title} navigation`} className="space-y-0.5">{items.map((i) => <SideLink key={i.to} it={i} />)}</nav>
        </aside>
        <main id="main" className={cn('min-w-0 flex-1 px-3 py-4 md:px-6 md:py-6', bottom && 'pb-24 lg:pb-6')}>
          {user && !user.email_verified && kind !== 'admin' && (
            <Alert tone="warning" className="mb-4" title="Verify your email" action={<Link to="/verify-email" className="shrink-0 text-sm font-semibold text-primary-600 underline">Verify now</Link>}>
              You need a verified email to unlock contacts, send enquiries, purchase plans and submit listings.
            </Alert>
          )}
          <Outlet />
        </main>
      </div>
      {bottom && (
        <nav aria-label={`${title} bottom navigation`} className="safe-bottom fixed inset-x-0 bottom-0 z-40 border-t border-line bg-bg/95 backdrop-blur lg:hidden">
          <ul className={cn('mx-auto grid max-w-lg', bottom.length === 5 ? 'grid-cols-5' : 'grid-cols-4')}>
            {bottom.map((i) => (
              <li key={i.to}>
                <NavLink to={i.to} end={i.end} className={({ isActive }) => cn('flex h-14 flex-col items-center justify-center gap-0.5 text-[11px] font-medium', isActive ? 'text-primary-600' : 'text-muted')}>
                  <i.icon className="h-5 w-5" aria-hidden />{i.label}
                </NavLink>
              </li>
            ))}
          </ul>
        </nav>
      )}
      {kind === 'seller' && !hideFab && (
        <Link to="/seller/listings/new" aria-label="Add a pet listing"
          className="fixed bottom-[calc(72px+env(safe-area-inset-bottom))] right-4 z-40 grid h-14 w-14 place-items-center rounded-full bg-accent-600 text-white shadow-raised lg:bottom-6 lg:right-6 lg:h-auto lg:w-auto lg:grid-flow-col lg:gap-2 lg:px-5 lg:py-3">
          <Plus className="h-6 w-6 lg:h-5 lg:w-5" aria-hidden /><span className="hidden text-sm font-semibold lg:inline">Add pet</span>
        </Link>
      )}
      <Dialog open={menu} onOpenChange={setMenu} title={`${title} menu`} sheetOnly>
        <nav aria-label={`${title} menu`} className="space-y-0.5">{items.map((i) => <SideLink key={i.to} it={i} onClick={() => setMenu(false)} />)}</nav>
      </Dialog>
    </div>
  )
}
