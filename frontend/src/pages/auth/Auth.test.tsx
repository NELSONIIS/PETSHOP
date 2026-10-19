import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { axe } from 'vitest-axe'
import { describe, expect, it } from 'vitest'
import { LoginPage, RegisterPage } from './Auth'
import { changePasswordSchema, listingSchema, passwordRule, registerSchema } from '@/lib/schemas'
import { mockApi, renderWith, user } from '@/test/utils'

const login = <Routes><Route path="/login" element={<LoginPage />} /><Route path="/buyer" element={<p>buyer home</p>} /><Route path="/admin" element={<p>admin home</p>} /></Routes>
const reg = <Routes><Route path="/register" element={<RegisterPage role="buyer" />} /><Route path="/verify-email" element={<p>verify page</p>} /></Routes>

describe('login form', () => {
  it('validates required fields before calling the API', async () => {
    const api = mockApi({})
    renderWith(login, { route: '/login' })
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    expect(await screen.findByText('Enter your email')).toBeInTheDocument()
    expect(screen.getByText('Enter your password')).toBeInTheDocument()
    expect(api.fn).not.toHaveBeenCalled()
  })
  it('rejects a malformed email', async () => {
    renderWith(login, { route: '/login' })
    await userEvent.type(screen.getByLabelText(/Email/), 'not-an-email')
    await userEvent.type(screen.getByLabelText(/Password/), 'x')
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    expect(await screen.findByText('Enter a valid email')).toBeInTheDocument()
  })
  it('signs in and follows a safe ?next, ignoring open redirects', async () => {
    mockApi({ 'POST /auth/login': { data: { user: user() } } })
    renderWith(login, { route: '/login?next=//evil.example' })
    await userEvent.type(screen.getByLabelText(/Email/), 'buyer@example.com')
    await userEvent.type(screen.getByLabelText(/Password/), 'Secret12345')
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    expect(await screen.findByText('buyer home')).toBeInTheDocument()
  })
  it('asks for the authenticator code when the API says mfa_required, then resubmits with it', async () => {
    let n = 0
    const api = mockApi({ 'POST /auth/login': () => (n++ === 0 ? { status: 401, error: { code: 'mfa_required', message: 'Enter code' } } : { data: { user: user({ account_type: 'staff', roles: ['super_admin'] }) } }) })
    renderWith(login, { route: '/login?next=/admin' })
    await userEvent.type(screen.getByLabelText(/Email/), 'admin@example.com')
    await userEvent.type(screen.getByLabelText(/Password/), 'Secret12345')
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    const otp = await screen.findByLabelText(/Authenticator code/)
    await userEvent.type(otp, '123456')
    await userEvent.click(screen.getByRole('button', { name: /Verify and log in/ }))
    expect(await screen.findByText('admin home')).toBeInTheDocument()
    expect(api.find('POST', '/auth/login')[1].body).toMatchObject({ otp: '123456' })
  })
  it('shows the server error for bad credentials', async () => {
    mockApi({ 'POST /auth/login': { status: 401, error: { code: 'unauthorized', message: 'Incorrect email or password' } } })
    renderWith(login, { route: '/login' })
    await userEvent.type(screen.getByLabelText(/Email/), 'a@b.co')
    await userEvent.type(screen.getByLabelText(/Password/), 'wrong-password1')
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    expect(await screen.findByText('Incorrect email or password')).toBeInTheDocument()
  })
})

describe('register form', () => {
  it('enforces password strength, confirmation and terms', async () => {
    const api = mockApi({})
    renderWith(reg, { route: '/register' })
    await userEvent.type(screen.getByLabelText(/Full name/), 'Asha')
    await userEvent.type(screen.getByLabelText(/^Email/), 'asha@example.com')
    await userEvent.type(screen.getByLabelText(/^Password/), 'short')
    await userEvent.type(screen.getByLabelText(/Confirm password/), 'different')
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }))
    expect(await screen.findByText('Use at least 10 characters')).toBeInTheDocument()
    expect(screen.getByText('Passwords do not match')).toBeInTheDocument()
    expect(screen.getByText('You must accept the Terms and Privacy Policy')).toBeInTheDocument()
    expect(api.fn).not.toHaveBeenCalled()
  })
  it('submits role=buyer and continues to email verification', async () => {
    const api = mockApi({ 'POST /auth/register': { status: 201, data: { user: user({ email_verified: false }) } } })
    renderWith(reg, { route: '/register' })
    await userEvent.type(screen.getByLabelText(/Full name/), 'Asha Buyer')
    await userEvent.type(screen.getByLabelText(/^Email/), 'asha@example.com')
    await userEvent.type(screen.getByLabelText(/^Password/), 'Correct-horse-9')
    await userEvent.type(screen.getByLabelText(/Confirm password/), 'Correct-horse-9')
    await userEvent.click(screen.getByRole('checkbox'))
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }))
    expect(await screen.findByText('verify page')).toBeInTheDocument()
    expect(api.find('POST', '/auth/register')[0].body).toMatchObject({ role: 'buyer', email: 'asha@example.com', accept_terms: true })
  })
  it('maps server-side field errors onto the form', async () => {
    mockApi({ 'POST /auth/register': { status: 422, error: { code: 'validation_failed', message: 'Some fields are invalid', details: [{ field: 'email', message: 'is already registered' }] } } })
    renderWith(reg, { route: '/register' })
    await userEvent.type(screen.getByLabelText(/Full name/), 'Asha Buyer')
    await userEvent.type(screen.getByLabelText(/^Email/), 'asha@example.com')
    await userEvent.type(screen.getByLabelText(/^Password/), 'Correct-horse-9')
    await userEvent.type(screen.getByLabelText(/Confirm password/), 'Correct-horse-9')
    await userEvent.click(screen.getByRole('checkbox'))
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }))
    await waitFor(() => expect(screen.getByText('is already registered')).toBeInTheDocument())
  })
})

describe('schemas', () => {
  it('password rule needs 10+ chars with a letter and a digit', () => {
    expect(passwordRule.safeParse('abcdefghij').success).toBe(false)
    expect(passwordRule.safeParse('1234567890').success).toBe(false)
    expect(passwordRule.safeParse('abcdefghi1').success).toBe(true)
  })
  it('registerSchema and changePasswordSchema reject weak input', () => {
    expect(registerSchema.safeParse({ name: 'A', email: 'x', password: 'a', confirm: 'b', accept_terms: false }).success).toBe(false)
    expect(changePasswordSchema.safeParse({ current_password: '', new_password: 'weak' }).success).toBe(false)
  })
  it('listing schema requires a price for sale but not for adoption', () => {
    const base = { title: 'Labrador puppy', category_id: 'c', listing_type: 'sale', gender: 'male', vaccination_status: 'none', dewormed: '', microchipped: '', city: 'Pune', state: 'MH', availability: 'available' }
    expect(listingSchema.safeParse({ ...base, price: '' }).success).toBe(false)
    expect(listingSchema.safeParse({ ...base, price: '15000' }).success).toBe(true)
    expect(listingSchema.safeParse({ ...base, listing_type: 'adoption', price: '' }).success).toBe(true)
    expect(listingSchema.safeParse({ ...base, title: 'Pup', price: '1' }).success).toBe(false)
  })
})

describe('a11y', () => {
  it('login page has no axe violations', async () => {
    const { container } = renderWith(login, { route: '/login' })
    expect(await axe(container)).toHaveNoViolations()
  })
  it('register page has no axe violations', async () => {
    const { container } = renderWith(reg, { route: '/register' })
    expect(await axe(container)).toHaveNoViolations()
  })
})

describe('staff login', () => {
  it('re-reads /me so session-level MFA state is authoritative', async () => {
    const api = mockApi({
      'POST /auth/login': { data: { user: user({ account_type: 'staff', roles: ['super_admin'], mfa_enabled: true, mfa_verified: false }) } },
      'GET /me': { data: user({ account_type: 'staff', roles: ['super_admin'], mfa_enabled: true, mfa_verified: true }) },
    })
    renderWith(login, { route: '/login?next=/admin' })
    await userEvent.type(screen.getByLabelText(/Email/), 'admin@example.com')
    await userEvent.type(screen.getByLabelText(/Password/), 'Secret12345')
    await userEvent.click(screen.getByRole('button', { name: 'Log in' }))
    expect(await screen.findByText('admin home')).toBeInTheDocument()
    expect(api.find('GET', '/me')).toHaveLength(1)
  })
})
