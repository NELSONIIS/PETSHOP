import { Link } from 'react-router-dom'
import { Logo } from './Brand'

const cols = [
  { title: 'Discover', links: [['/pets', 'Browse pets'], ['/pets?listing_type=adoption', 'Adoption'], ['/pets?verified_seller=true', 'Verified sellers'], ['/pricing', 'Membership']] },
  { title: 'Sell on PETORA', links: [['/register/seller', 'Become a seller'], ['/seller-policy', 'Seller policy'], ['/pricing', 'Seller plans']] },
  { title: 'Help', links: [['/safety', 'Safety & welfare'], ['/faq', 'FAQ'], ['/support', 'Contact support']] },
  { title: 'Legal', links: [['/terms', 'Terms of service'], ['/privacy', 'Privacy policy'], ['/refund-policy', 'Refund policy']] },
]

export function Footer() {
  return (
    <footer className="mt-12 border-t border-line bg-warm">
      <div className="container-page grid gap-8 py-10 sm:grid-cols-2 lg:grid-cols-5">
        <div className="space-y-2 lg:col-span-1">
          <Logo />
          <p className="max-w-[240px] text-sm text-muted">A marketplace for responsible pet discovery and adoption in India.</p>
        </div>
        {cols.map((c) => (
          <nav key={c.title} aria-label={c.title}>
            <h2 className="mb-2 text-xs font-semibold uppercase tracking-wider text-muted">{c.title}</h2>
            <ul className="space-y-1">{c.links.map(([to, label]) => <li key={label}><Link to={to} className="inline-flex min-h-[32px] items-center text-sm hover:text-primary-600">{label}</Link></li>)}</ul>
          </nav>
        ))}
      </div>
      <div className="border-t border-line py-4 text-center text-xs text-muted">
        <p className="container-page">© {new Date().getFullYear()} PETORA. Listings are posted by independent sellers; PETORA does not guarantee any sale, a pet’s health or a seller’s licensing status.</p>
      </div>
    </footer>
  )
}
