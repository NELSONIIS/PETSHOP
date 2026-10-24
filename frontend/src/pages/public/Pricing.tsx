import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { usePlans, useSubscription } from '@/api/hooks'
import type { Plan } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { BuyerTrustNote, CheckoutDialog, PlanCard } from '@/components/Billing'
import { Button } from '@/components/ui/Button'
import { Alert, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { TabBar } from '@/components/ui/Tabs'
import { Shell } from './Content'

/** Public pricing. Prices/entitlements come from the API only (admin-configurable). */
export default function Pricing() {
  const { user } = useAuth()
  const nav = useNavigate()
  const [aud, setAud] = useState<'buyer' | 'seller'>('buyer')
  const q = usePlans(aud)
  const sub = useSubscription(!!user && user.account_type === aud)
  const [chosen, setChosen] = useState<Plan | null>(null)
  const matches = user?.account_type === aud
  const currentPlan = sub.items?.active ? sub.items.subscription?.plan.id : undefined
  const choose = (p: Plan) => {
    if (!user) { nav(`/register${aud === 'seller' ? '/seller' : ''}?next=/pricing`); return }
    if (!matches) return
    setChosen(p)
  }
  return (
    <Shell title="Membership plans" subtitle="Browsing is always free. Plans unlock the features described below.">
      <div className="mb-4"><TabBar label="Plan audience" value={aud} onChange={(v) => setAud(v as 'buyer' | 'seller')} items={[{ value: 'buyer', label: 'For buyers' }, { value: 'seller', label: 'For sellers' }]} /></div>
      {user && !matches && <Alert tone="info" className="mb-3">You’re signed in with a {user.account_type} account, so {aud} plans can’t be purchased with it.</Alert>}
      {aud === 'seller' && <Alert tone="info" className="mb-3" title="Verification is separate">Buying a seller plan does not verify your account. You must complete seller verification before listings can be published.</Alert>}
      {q.isLoading ? <div className="grid gap-3 sm:grid-cols-2"><Skeleton className="h-64" /><Skeleton className="h-64" /></div> : q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : (
        <div className="space-y-4">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {q.items?.map((p, i) => (
              <PlanCard key={p.id} plan={p} highlight={i === 1} current={p.id === currentPlan}
                cta={<Button variant={p.id === currentPlan ? 'outline' : 'accent'} disabled={!!user && !matches} onClick={() => choose(p)}>{p.id === currentPlan ? 'Renew / extend' : user ? `Choose ${p.name}` : 'Sign up to choose'}</Button>} />
            ))}
            {q.items?.length === 0 && <p className="text-sm text-muted">No {aud} plans are available right now.</p>}
          </div>
          {aud === 'buyer' && <BuyerTrustNote />}
        </div>
      )}
      <ul className="mt-6 space-y-1 text-xs text-muted"><li>Prices are shown before tax where applicable; the checkout shows your exact total.</li>
        <li>A membership does not guarantee that a pet is available or that a transaction will succeed.</li><li>See our <a className="underline" href="/refund-policy">refund policy</a>.</li></ul>
      <CheckoutDialog plan={chosen} open={!!chosen} onOpenChange={(o) => { if (!o) setChosen(null) }} />
    </Shell>
  )
}
