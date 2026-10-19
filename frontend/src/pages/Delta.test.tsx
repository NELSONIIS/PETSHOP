import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import { EnquiryThread } from './shared/Enquiries'
import { ProfileSecurityPage } from './shared/Account'
import { InvoicePage } from './shared/Billing'
import { AdminEnquiries } from './admin/Trust'
import { AdminTemplates } from './admin/Platform'
import { mockApi, renderWith, staff, user } from '@/test/utils'

const enquiry = { id: 'e1', status: 'responded', listing: { id: 'p1', slug: 'pup', title: 'Labrador puppy', cover: null, availability: 'available' },
  counterparty: { name: 'Happy Paws', slug: 'happy-paws', user_id: 'u-seller' }, last_message: 'Hi', last_message_at: '2026-10-18T00:00:00Z', unread: 0, created_at: '2026-10-18T00:00:00Z',
  messages: [{ id: 'm1', sender_id: 'u1', mine: true, body: 'Hi', created_at: '2026-10-18T00:00:00Z' }], contact_unlocked: true }

describe('block user', () => {
  it('confirms before POST /blocks with the counterparty user_id', async () => {
    const api = mockApi({ 'GET /buyer/enquiries/e1': { data: enquiry }, 'POST /blocks': { status: 204 } })
    renderWith(<Routes><Route path="/buyer/enquiries/:id" element={<EnquiryThread role="buyer" />} /></Routes>, { route: '/buyer/enquiries/e1', user: user() })
    await userEvent.click(await screen.findByRole('button', { name: /Block user/ }))
    expect(api.find('POST', '/blocks')).toHaveLength(0)
    const dlg = await screen.findByRole('dialog', { name: 'Block Happy Paws?' })
    await userEvent.click(within(dlg).getByRole('button', { name: 'Block user' }))
    await waitFor(() => expect(api.find('POST', '/blocks')[0]?.body).toEqual({ user_id: 'u-seller' }))
  })
  it('profile lists blocked users and unblocks via DELETE /blocks/{userId}', async () => {
    const api = mockApi({ 'GET /me/sessions': { data: [] }, 'GET /buyer/profile': { data: { city: '', state: '', radius_km: 50, notify_email: true, notify_sms: false, notify_push: true } },
      'GET /blocks': { data: [{ user_id: 'u-seller', name: 'Happy Paws', created_at: '2026-10-18T00:00:00Z' }] }, 'DELETE /blocks/u-seller': { status: 204 } })
    renderWith(<ProfileSecurityPage />, { user: user() })
    const sec = (await screen.findByRole('heading', { name: 'Blocked users' })).closest('section')!
    await within(sec as HTMLElement).findByText('Happy Paws')
    await userEvent.click(within(sec as HTMLElement).getByRole('button', { name: 'Unblock' }))
    await waitFor(() => expect(api.find('DELETE', '/blocks/u-seller')).toHaveLength(1))
  })
})

describe('admin abuse review', () => {
  it('renders the real row shape and the transcript with sender labels', async () => {
    mockApi({ 'GET /admin/enquiries': { data: [{ id: 'e1', status: 'reported', listing_title: 'Senior dog Rani', buyer_email: 'b@x.test', seller_email: 's@x.test', created_at: '2026-10-18T00:00:00Z',
      messages: [{ sender: 'buyer', body: 'Buy now pay outside', created_at: '2026-10-18T00:00:00Z' }, { sender: 'seller', body: 'No thanks', created_at: '2026-10-18T00:01:00Z' }] }], meta: { page: 1, per_page: 20, total: 1, total_pages: 1 } } })
    renderWith(<AdminEnquiries />, { user: staff(['reports.manage']) })
    await userEvent.click((await screen.findAllByText('Senior dog Rani'))[0])
    const dlg = await screen.findByRole('dialog')
    expect(within(dlg).getByText('Buy now pay outside')).toBeInTheDocument()
    expect(within(dlg).getByText('Seller · s@x.test')).toBeInTheDocument()
  })
})

describe('notification templates', () => {
  it('lists known keys without a saved row and saves an override via PUT …/{key}/email', async () => {
    const api = mockApi({ 'GET /admin/notification-templates': { data: { templates: [], known_keys: ['email_verify', 'support_contact'] } }, 'PUT /admin/notification-templates/support_contact/email': { status: 204 } })
    renderWith(<AdminTemplates />, { user: staff(['content.manage']) })
    await userEvent.click((await screen.findAllByText('support_contact'))[0])
    const dlg = await screen.findByRole('dialog')
    expect(within(dlg).getByText(/built-in default text/)).toBeInTheDocument()
    await userEvent.type(within(dlg).getByLabelText(/Subject/), 'We got your message')
    await userEvent.type(within(dlg).getByLabelText(/Body/), 'Hi {{{{.name}}, thanks!')
    await userEvent.click(within(dlg).getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(api.find('PUT', '/admin/notification-templates/support_contact/email')[0]?.body).toMatchObject({ subject: 'We got your message', is_active: true }))
  })
})

describe('test-mode invoices', () => {
  it('shows a TEST badge when the invoice number starts with TEST-', async () => {
    mockApi({ 'GET /billing/invoices/i1': { data: { id: 'i1', number: 'TEST-PET/2026-27/000003', payment_id: 'p', bill_to_name: 'A', bill_to_email: 'a@x.test', lines: [{ description: 'Buyer Basic', amount_minor: 19900 }], subtotal_minor: 19900, tax_minor: 3582, total_minor: 23482, currency: 'INR', issued_at: '2026-10-18T00:00:00Z' } } })
    renderWith(<Routes><Route path="/buyer/billing/invoices/:id" element={<InvoicePage base="/buyer" />} /></Routes>, { route: '/buyer/billing/invoices/i1', user: user() })
    expect(await screen.findByText('TEST')).toBeInTheDocument()
    expect(screen.getByText(/no money was charged/)).toBeInTheDocument()
  })
})
