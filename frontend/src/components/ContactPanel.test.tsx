import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { axe } from 'vitest-axe'
import { describe, expect, it } from 'vitest'
import PetDetail from '@/pages/public/PetDetail'
import { card, detail, mockApi, plan, renderWith, user } from '@/test/utils'

const pet = detail()
const page = <Routes><Route path="/pets/:slug" element={<PetDetail />} /><Route path="/login" element={<p>login page</p>} /></Routes>
const cfg = { data: { brand_name: 'PETORA', currency: 'INR', maintenance: false, payment_provider: 'testmode', max_images_per_listing: 8, max_image_mb: 8 } }
const base = () => ({
  'GET /pets/labrador-puppy': { data: pet }, 'GET /pets/p1/similar': { data: [card({ id: 'p2', slug: 'other', title: 'Another pup' })] },
  'POST /pets/p1/view': { status: 204 }, 'GET /config': cfg, 'GET /subscription-plans': { data: [plan()] },
})
const contact = { seller_name: 'Happy Paws', phone: '+919800000001', whatsapp: '+919800000001', email: 'seller@example.com', unlocked_at: '2026-10-18T00:00:00Z', remaining_unlocks: 9 }

describe('pet detail: contact locking', () => {
  it('never renders seller contact details before an authorised unlock', async () => {
    mockApi(base())
    const { container } = renderWith(page, { route: '/pets/labrador-puppy', user: null })
    await screen.findByRole('heading', { name: 'Labrador puppy' })
    expect(screen.getByText(/locked/)).toBeInTheDocument()
    expect(container.innerHTML).not.toMatch(/\+91|@example\.com|wa\.me|tel:/)
    expect(screen.getByRole('button', { name: /Unlock seller contact/ })).toBeInTheDocument()
    // trust copy: no licensing / medical-verification claims
    expect(container.textContent).not.toMatch(/licensed|health verified|medically verified/i)
    expect(screen.getByText(/not verified by PETORA/)).toBeInTheDocument()
  })

  it('anonymous visitors are sent to log in (no unlock request is made)', async () => {
    const api = mockApi(base())
    renderWith(page, { route: '/pets/labrador-puppy', user: null })
    await userEvent.click(await screen.findByRole('button', { name: /Unlock seller contact/ }))
    expect(await screen.findByText('login page')).toBeInTheDocument()
    expect(screen.getByTestId('loc')).toHaveTextContent('/login?next=%2Fpets%2Flabrador-puppy')
    expect(api.find('POST', '/pets/p1/contact-unlock')).toHaveLength(0)
  })

  it('402 membership_required opens the plan picker from the API plans', async () => {
    mockApi({ ...base(), 'POST /pets/p1/contact-unlock': { status: 402, error: { code: 'membership_required', message: 'A buyer membership is required' } } })
    const { baseElement } = renderWith(page, { route: '/pets/labrador-puppy', user: user() })
    await userEvent.click(await screen.findByRole('button', { name: /Unlock seller contact/ }))
    expect(await screen.findByText('Choose a membership')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Choose Buyer Monthly/ })).toBeInTheDocument()
    expect(baseElement.innerHTML).not.toMatch(/\+919800000001/)
  })

  it('plan picker shows full prices even though the 402 only carries a slim suggested_plans summary', async () => {
    mockApi({ ...base(), 'POST /pets/p1/contact-unlock': { status: 402, error: { code: 'membership_required', message: 'x', extra: { suggested_plans: [{ id: 'pl1', name: 'Buyer Monthly', total_minor: 58882, currency: 'INR' }] } } } })
    renderWith(page, { route: '/pets/labrador-puppy', user: user() })
    await userEvent.click(await screen.findByRole('button', { name: /Unlock seller contact/ }))
    expect(await screen.findByText('Choose a membership')).toBeInTheDocument()
    expect(await screen.findByText(/\+ 18% tax · total ₹588\.82/)).toBeInTheDocument()
  })

  it('shows contact only after the API grants it, and the enquiry form is available', async () => {
    const api = mockApi({ ...base(), 'POST /pets/p1/contact-unlock': { data: contact } })
    renderWith(page, { route: '/pets/labrador-puppy', user: user() })
    await userEvent.click(await screen.findByRole('button', { name: /Unlock seller contact/ }))
    expect(await screen.findByRole('link', { name: '+919800000001' })).toHaveAttribute('href', 'tel:+919800000001')
    expect(screen.getByText(/9 contact unlocks left/)).toBeInTheDocument()
    expect(api.find('POST', '/pets/p1/contact-unlock')).toHaveLength(1)
    expect(screen.getByRole('button', { name: 'Send enquiry' })).toBeInTheDocument()
  })

  it('unverified email → prompts to verify instead of showing contact', async () => {
    mockApi({ ...base(), 'POST /pets/p1/contact-unlock': { status: 403, error: { code: 'verification_required', message: 'Please verify your email address first' } } })
    renderWith(page, { route: '/pets/labrador-puppy', user: user({ email_verified: false }) })
    await userEvent.click(await screen.findByRole('button', { name: /Unlock seller contact/ }))
    expect(await screen.findByText('Verify your email first')).toBeInTheDocument()
  })

  it('submitting an enquiry posts the message; duplicates link to the existing thread', async () => {
    let n = 0
    const api = mockApi({ ...base(), 'POST /pets/p1/enquiries': () => (n++ === 0 ? { status: 409, error: { code: 'conflict', message: 'You already enquired about this pet', extra: { enquiry_id: 'e9' } } } : { status: 201, data: { id: 'e1' } }) })
    renderWith(page, { route: '/pets/labrador-puppy', user: user() })
    await userEvent.type(await screen.findByLabelText('Send an enquiry'), 'Is the puppy still available?')
    await userEvent.click(screen.getByRole('button', { name: 'Send enquiry' }))
    expect(await screen.findByRole('link', { name: 'Open your conversation' })).toHaveAttribute('href', '/buyer/enquiries/e9')
    expect(api.find('POST', '/pets/p1/enquiries')[0].body).toEqual({ message: 'Is the puppy still available?' })
    await userEvent.click(screen.getByRole('button', { name: 'Send enquiry' }))
    expect(await screen.findByText('Enquiry sent')).toBeInTheDocument()
  })

  it('seller accounts are told contact unlocking is for buyers', async () => {
    const api = mockApi(base())
    renderWith(page, { route: '/pets/labrador-puppy', user: user({ account_type: 'seller', roles: ['seller'] }) })
    await screen.findByRole('heading', { name: 'Labrador puppy' })
    expect(screen.getByText(/available to buyer accounts/)).toBeInTheDocument()
    expect(api.find('POST', '/pets/p1/contact-unlock')).toHaveLength(0)
  })

  it('records a view once and has no axe violations in the locked state', async () => {
    const api = mockApi(base())
    const { container } = renderWith(page, { route: '/pets/labrador-puppy', user: user() })
    await screen.findByRole('heading', { name: 'Labrador puppy' })
    await waitFor(() => expect(api.find('POST', '/pets/p1/view')).toHaveLength(1))
    expect(await axe(container)).toHaveNoViolations()
  })
})
