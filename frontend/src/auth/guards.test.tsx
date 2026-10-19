import { screen } from '@testing-library/react'
import { Route, Routes } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { RequireAuth, RequireStaff } from './guards'
import { renderWith, staff, user } from '@/test/utils'

const tree = (
  <Routes>
    <Route path="/login" element={<p>login page</p>} />
    <Route path="/buyer/*" element={<RequireAuth types={['buyer']}><p>buyer area</p></RequireAuth>} />
    <Route path="/seller/*" element={<RequireAuth types={['seller']}><p>seller area</p></RequireAuth>} />
    <Route path="/admin/mfa" element={<RequireStaff><p>mfa page</p></RequireStaff>} />
    <Route path="/admin/*" element={<RequireStaff><RequireAuth perm="payments.view"><p>payments</p></RequireAuth></RequireStaff>} />
  </Routes>
)

describe('route guards', () => {
  it('sends anonymous visitors to /login with a next param', () => {
    renderWith(tree, { route: '/buyer/enquiries?x=1', user: null })
    expect(screen.getByText('login page')).toBeInTheDocument()
    expect(screen.getByTestId('loc')).toHaveTextContent('/login?next=%2Fbuyer%2Fenquiries%3Fx%3D1')
  })
  it('lets a buyer into /buyer', () => {
    renderWith(tree, { route: '/buyer', user: user() })
    expect(screen.getByText('buyer area')).toBeInTheDocument()
  })
  it('keeps a buyer out of /seller and bounces them to their own area', () => {
    renderWith(tree, { route: '/seller', user: user() })
    expect(screen.queryByText('seller area')).not.toBeInTheDocument()
    expect(screen.getByTestId('loc')).toHaveTextContent('/buyer')
  })
  it('keeps non-staff out of /admin', () => {
    renderWith(tree, { route: '/admin/payments', user: user({ account_type: 'seller', roles: ['seller'] }) })
    expect(screen.queryByText('payments')).not.toBeInTheDocument()
    expect(screen.getByTestId('loc')).toHaveTextContent('/seller')
  })
  it('forces staff without MFA to the enrolment page', () => {
    renderWith(tree, { route: '/admin/payments', user: staff(['payments.view'], { mfa_enabled: false, mfa_verified: false }) })
    expect(screen.getByText('mfa page')).toBeInTheDocument()
  })
  it('denies staff lacking the page permission', () => {
    renderWith(tree, { route: '/admin/payments', user: staff(['users.view']) })
    expect(screen.queryByText('payments')).not.toBeInTheDocument()
  })
  it('admits staff with the permission and verified MFA', () => {
    renderWith(tree, { route: '/admin/payments', user: staff(['payments.view']) })
    expect(screen.getByText('payments')).toBeInTheDocument()
  })
})
