import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { Route, Routes } from 'react-router-dom'
import { describe, expect, it } from 'vitest'
import Search, { filtersFromParams } from './Search'
import { card, mockApi, renderWith } from '@/test/utils'

const cats = [{ id: 'c1', slug: 'dogs', name: 'Dogs', icon: 'dog', description: '', sort_order: 1, is_active: true, requires_verified_seller: false, breeds: [{ id: 'b1', slug: 'labrador', name: 'Labrador', is_active: true }] }]
const routes = () => ({
  'GET /categories': { data: cats },
  'GET /pets': { data: [card()], meta: { page: 1, per_page: 20, total: 1, total_pages: 1 } },
})
const page = <Routes><Route path="/pets" element={<Search />} /><Route path="/categories/:slug" element={<Search />} /></Routes>

describe('search filters ↔ URL', () => {
  it('parses known filter keys only', () => {
    expect(filtersFromParams(new URLSearchParams('q=lab&gender=male&evil=1&page=3'))).toEqual({ q: 'lab', gender: 'male' })
  })

  it('sends URL filters to the API and shows active filter chips', async () => {
    const api = mockApi(routes())
    renderWith(page, { route: '/pets?category=dogs&min_price=500000&gender=male&verified_seller=true&sort=price_asc' })
    await screen.findByText('Labrador puppy')
    const call = api.find('GET', '/pets')[0].url.searchParams
    expect(call.get('category')).toBe('dogs')
    expect(call.get('min_price')).toBe('500000')
    expect(call.get('gender')).toBe('male')
    expect(call.get('verified_seller')).toBe('true')
    expect(call.get('sort')).toBe('price_asc')
    const chips = within(screen.getByRole('list', { name: 'Active filters' }))
    expect(chips.getByText('From ₹5000')).toBeInTheDocument()
    expect(chips.getByText('Verified sellers')).toBeInTheDocument()
  })

  it('removing a chip updates the URL and refetches without that filter', async () => {
    const api = mockApi(routes())
    renderWith(page, { route: '/pets?gender=male&city=Pune' })
    await screen.findByText('Labrador puppy')
    await userEvent.click(screen.getByRole('button', { name: /Remove filter Male/i }))
    await waitFor(() => expect(screen.getByTestId('loc')).toHaveTextContent('/pets?city=Pune'))
    await waitFor(() => expect(api.find('GET', '/pets').some((c) => !c.url.searchParams.has('gender') && c.url.searchParams.get('city') === 'Pune')).toBe(true))
  })

  it('applying the sidebar filters writes them to the URL (price entered in rupees → paise)', async () => {
    mockApi(routes())
    renderWith(page, { route: '/pets' })
    await screen.findByText('Labrador puppy')
    const side = within(screen.getAllByRole('complementary', { name: 'Filters' })[0])
    await userEvent.type(side.getByLabelText('Max price'), '25000')
    await userEvent.selectOptions(side.getByLabelText('Listing type'), 'adoption')
    await userEvent.click(side.getByRole('button', { name: 'Apply filters' }))
    await waitFor(() => {
      const loc = screen.getByTestId('loc').textContent ?? ''
      expect(loc).toContain('max_price=2500000')
      expect(loc).toContain('listing_type=adoption')
    })
  })

  it('category route locks the category and shows its heading', async () => {
    const api = mockApi(routes())
    renderWith(page, { route: '/categories/dogs' })
    await screen.findByRole('heading', { name: 'Dogs' })
    await waitFor(() => expect(api.find('GET', '/pets')[0].url.searchParams.get('category')).toBe('dogs'))
  })

  it('shows an empty state with a way out when nothing matches', async () => {
    mockApi({ ...routes(), 'GET /pets': { data: [], meta: { page: 1, per_page: 20, total: 0, total_pages: 0 } } })
    renderWith(page, { route: '/pets?q=zzz' })
    expect(await screen.findByText('No pets match your filters')).toBeInTheDocument()
  })

  it('shows a retryable error state when the API fails', async () => {
    mockApi({ ...routes(), 'GET /pets': { status: 500, error: { code: 'internal_error', message: 'Boom' } } })
    renderWith(page, { route: '/pets' })
    expect(await screen.findByText('Boom')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /retry/i })).toBeInTheDocument()
  })
})
