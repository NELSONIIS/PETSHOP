import { useState } from 'react'
import { useGet } from '@/api/hooks'
import type { AdminDashboard } from '@/api/types'
import { useAuth } from '@/auth/AuthContext'
import { BarChart, dayLabel } from '@/components/Chart'
import { PageHeader, Stat } from '@/components/Section'
import { Alert, ErrorState, Skeleton } from '@/components/ui/Feedback'
import { Select } from '@/components/ui/Form'
import { formatMoney } from '@/lib/utils'

export default function AdminOverview() {
  const { can, user } = useAuth()
  const q = useGet<AdminDashboard>(can('dashboard.view') ? '/admin/dashboard' : null)
  const [days, setDays] = useState('30')
  const rev = useGet<{ date: string; revenue_minor: number; payments: number }[]>(can('payments.view') ? '/admin/analytics/revenue' : null, { days })
  const d = q.items
  const cur = d?.currency ?? 'INR'
  return (
    <div className="space-y-4">
      <PageHeader title="Overview" subtitle={`Signed in as ${user?.name} · ${user?.roles.join(', ')}`} />
      {q.error ? <ErrorState error={q.error} onRetry={() => q.refetch()} /> : q.isLoading || !d ? <div className="grid grid-cols-2 gap-3 md:grid-cols-4">{Array.from({ length: 8 }).map((_, i) => <Skeleton key={i} className="h-20" />)}</div> : (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Total users" value={d.users_total} to="/admin/users" /><Stat label="Active buyers" value={d.active_buyers} /><Stat label="Active sellers" value={d.active_sellers} />
            <Stat label="Pending verifications" value={d.pending_verifications} to="/admin/verifications" tone={d.pending_verifications ? 'warn' : undefined} />
            <Stat label="Total listings" value={d.listings_total} hint={`${d.listings_approved} live`} /><Stat label="Pending moderation" value={d.pending_moderation} to="/admin/listings" tone={d.pending_moderation ? 'warn' : undefined} />
            <Stat label="Active subscriptions" value={d.active_subscriptions} to="/admin/subscriptions" /><Stat label="Monthly recurring revenue" value={formatMoney(d.monthly_recurring_revenue_minor, cur)} hint="Excl. tax, normalised" />
            <Stat label="Successful payments" value={d.payments_succeeded} to="/admin/payments" /><Stat label="Failed payments" value={d.payments_failed} tone={d.payments_failed ? 'warn' : undefined} />
            <Stat label="Revenue (30 days)" value={formatMoney(d.revenue_30d_minor, cur)} /><Stat label="Refunds issued" value={formatMoney(d.refunds_total_minor, cur)} />
            <Stat label="Open reports" value={d.open_reports} to="/admin/reports" tone={d.open_reports ? 'warn' : undefined} /><Stat label="Open disputes" value={d.open_disputes} to="/admin/reports" />
            <Stat label="Dead jobs" value={d.dead_jobs} to="/admin/jobs" tone={d.dead_jobs ? 'warn' : undefined} />
          </div>
          {d.dead_jobs > 0 && <Alert tone="warning">Some background jobs failed permanently. Review them under Background jobs.</Alert>}
        </>
      )}
      {can('payments.view') && (
        <section className="card space-y-2 p-4" aria-label="Revenue">
          <div className="flex items-center justify-between"><h2 className="text-lg">Revenue</h2><Select aria-label="Period" className="h-10 w-auto" value={days} onChange={(e) => setDays(e.target.value)}>{['7', '30', '90', '365'].map((x) => <option key={x} value={x}>Last {x} days</option>)}</Select></div>
          {rev.error ? <ErrorState error={rev.error} onRetry={() => rev.refetch()} /> : rev.isLoading ? <Skeleton className="h-44 w-full" /> : <BarChart title={`Daily revenue, last ${days} days`} data={(rev.items ?? []).map((r) => ({ label: dayLabel(r.date), value: r.revenue_minor }))} format={(v) => formatMoney(v, cur)} />}
        </section>)}
    </div>
  )
}
