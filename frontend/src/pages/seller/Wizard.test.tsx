import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import ListingWizard, { formToInput, listingToForm } from './Wizard'
import { detail, mockApi, renderWith, user } from '@/test/utils'
import type { ListingOwner } from '@/api/types'

const cats = [{ id: 'c1', slug: 'dogs', name: 'Dogs', icon: 'dog', description: '', sort_order: 1, is_active: true, requires_verified_seller: false, breeds: [{ id: 'b1', slug: 'labrador', name: 'Labrador', is_active: true }] }]
const owner = (o: Partial<ListingOwner> = {}): ListingOwner => ({ ...detail(), status: 'draft', favourites_count: 0, enquiries_count: 0, created_at: '2026-10-01T00:00:00Z', updated_at: '2026-10-01T00:00:00Z', missing_for_submission: [], ...o })
const page = <Routes><Route path="/seller/listings/new" element={<ListingWizard />} /></Routes>
const seller = user({ account_type: 'seller', roles: ['seller'] })
const base = () => ({ 'GET /categories': { data: cats }, 'GET /config': { data: { brand_name: 'PETORA', currency: 'INR', maintenance: false, payment_provider: 'testmode', max_images_per_listing: 8, max_image_mb: 8 } } })

describe('listing wizard', () => {
  it('blocks step 1 until the title is long enough', async () => {
    mockApi(base())
    renderWith(page, { route: '/seller/listings/new', user: seller })
    await userEvent.type(screen.getByLabelText(/Listing title/), 'Pup')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    expect(await screen.findByText('Title needs at least 5 characters')).toBeInTheDocument()
    expect(screen.getByText(/Step 1 of 10/)).toBeInTheDocument()
  })

  it('collects the early steps locally, creates the draft after the price step, then saves with PUT', async () => {
    const api = mockApi({ ...base(), 'POST /seller/listings': { status: 201, data: owner({ id: 'new1' }) }, 'PUT /seller/listings/new1': { data: owner({ id: 'new1' }) } })
    renderWith(page, { route: '/seller/listings/new', user: seller })
    await userEvent.type(screen.getByLabelText(/Listing title/), 'Labrador puppy 3 months')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    // species step requires a category
    await userEvent.click(await screen.findByRole('button', { name: /Next/ }))
    expect(await screen.findByText('Choose a species')).toBeInTheDocument()
    await userEvent.selectOptions(screen.getByLabelText(/Species \/ category/), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 3 of 10/)
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 4 of 10/)
    expect(api.find('POST', '/seller/listings')).toHaveLength(0) // nothing saved before a valid price exists
    await userEvent.type(screen.getByLabelText(/Price \(₹\)/), '15000')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 5 of 10/)
    expect(api.find('POST', '/seller/listings')).toHaveLength(1)
    expect(api.find('POST', '/seller/listings')[0].body).toMatchObject({ title: 'Labrador puppy 3 months', category_id: 'c1', listing_type: 'sale', price_minor: 1500000 })
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 6 of 10/)
    await waitFor(() => expect(api.find('PUT', '/seller/listings/new1')).toHaveLength(1))
  })

  it('rejects prices below ₹1 on the client', async () => {
    mockApi(base())
    renderWith(page, { route: '/seller/listings/new', user: seller })
    await userEvent.type(screen.getByLabelText(/Listing title/), 'Labrador puppy 3 months')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await userEvent.selectOptions(await screen.findByLabelText(/Species \/ category/), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await userEvent.click(await screen.findByRole('button', { name: /Next/ }))
    await userEvent.type(await screen.findByLabelText(/Price \(₹\)/), '0.5')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    expect(await screen.findByText('Price must be at least ₹1')).toBeInTheDocument()
  })

  it('requires a rupee price for sale listings and none for adoption', async () => {
    mockApi({ ...base(), 'POST /seller/listings': { status: 201, data: owner({ id: 'new1' }) }, 'PUT /seller/listings/new1': { data: owner({ id: 'new1' }) } })
    renderWith(page, { route: '/seller/listings/new', user: seller })
    await userEvent.type(screen.getByLabelText(/Listing title/), 'Labrador puppy 3 months')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await userEvent.selectOptions(await screen.findByLabelText(/Species \/ category/), 'c1')
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 3 of 10/)
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    await screen.findByText(/Step 4 of 10/)
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    expect(await screen.findByText(/Enter a price in ₹/)).toBeInTheDocument()
    await userEvent.selectOptions(screen.getByLabelText('Listing type'), 'adoption')
    expect(screen.queryByLabelText(/Price \(₹\)/)).not.toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: /Next/ }))
    expect(await screen.findByText(/Step 5 of 10/)).toBeInTheDocument()
  })

  it('maps between form values and API input without float drift', () => {
    const l = owner({ price_minor: 1999900, age_months: 14, dewormed: true, microchipped: null })
    const f = listingToForm(l)
    expect(f).toMatchObject({ price: '19999', age_years: '1', age_extra_months: '2', dewormed: 'yes', microchipped: '' })
    const input = formToInput({ ...f, price: '19999.50' }, [{ key: 'temperament', value: 'calm' }, { key: '', value: 'x' }], { lat: 18.5, lng: 73.8 })
    expect(input).toMatchObject({ price_minor: 1999950, age_months: 14, dewormed: true, microchipped: null, attributes: { temperament: 'calm' }, lat: 18.5 })
    expect(formToInput({ ...f, listing_type: 'adoption', price: '500' }, [], {}).price_minor).toBe(0)
  })
})
