import { z } from 'zod'

export const passwordRule = z
  .string()
  .min(10, 'Use at least 10 characters')
  .max(128, 'Use at most 128 characters')
  .refine((v) => /[A-Za-z]/.test(v) && /\d/.test(v), 'Include at least one letter and one number')

export const loginSchema = z.object({
  email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email'),
  password: z.string().min(1, 'Enter your password'),
  otp: z.string().optional(),
})
export type LoginForm = z.infer<typeof loginSchema>

export const registerSchema = z
  .object({
    name: z.string().trim().min(2, 'Enter your full name').max(120),
    email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email'),
    phone: z.string().trim().optional().refine((v) => !v || /^\+?[0-9 ]{10,16}$/.test(v), 'Enter a valid phone number'),
    password: passwordRule,
    confirm: z.string(),
    accept_terms: z.boolean().refine((v) => v, 'You must accept the Terms and Privacy Policy'),
  })
  .refine((v) => v.password === v.confirm, { path: ['confirm'], message: 'Passwords do not match' })
export type RegisterForm = z.infer<typeof registerSchema>

export const forgotSchema = z.object({ email: z.string().trim().min(1, 'Enter your email').email('Enter a valid email') })
export const resetSchema = z.object({
  email: z.string().trim().email('Enter a valid email'),
  code: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code'),
  password: passwordRule,
})
export const codeSchema = z.object({ code: z.string().trim().regex(/^\d{6}$/, 'Enter the 6-digit code') })
export const changePasswordSchema = z.object({
  current_password: z.string().min(1, 'Enter your current password'),
  new_password: passwordRule,
})

// ---- listing wizard ----
// All rules live in ONE superRefine on a type-only object: zod skips object-level refinements when a property
// fails, which would hide e.g. a missing price while later steps' fields are still empty.
const listingBase = z.object({
  title: z.string(), category_id: z.string(), breed_id: z.string().optional(), listing_type: z.enum(['sale', 'adoption']), price: z.string().optional(),
  age_years: z.string().optional(), age_extra_months: z.string().optional(), gender: z.enum(['male', 'female', 'unknown']), colour: z.string().optional(),
  description: z.string().optional(), vaccination_status: z.enum(['unspecified', 'none', 'partial', 'complete']), vaccination_notes: z.string().optional(),
  health_notes: z.string().optional(), dewormed: z.enum(['', 'yes', 'no']), microchipped: z.enum(['', 'yes', 'no']), city: z.string(), state: z.string(),
  availability: z.enum(['available', 'reserved']),
})
export const listingSchema = listingBase.superRefine((v, ctx) => {
  const bad = (path: keyof z.infer<typeof listingBase>, message: string) => ctx.addIssue({ code: 'custom', path: [path], message })
  const t = v.title.trim()
  if (t.length < 5) bad('title', 'Title needs at least 5 characters')
  else if (t.length > 140) bad('title', 'Title is too long (max 140)')
  if (!v.category_id) bad('category_id', 'Choose a species')
  const whole = (x: string | undefined, max: number) => !x || (/^\d+$/.test(x) && Number(x) <= max)
  if (!whole(v.age_years, 50)) bad('age_years', 'Enter a whole number up to 50')
  if (!whole(v.age_extra_months, 11)) bad('age_extra_months', 'Enter a whole number up to 11')
  if ((v.description ?? '').length > 5000) bad('description', 'Description is too long')
  if (v.city.trim().length < 2) bad('city', 'Enter the city')
  if (v.state.trim().length < 2) bad('state', 'Enter the state')
  if (v.listing_type === 'sale') {
    const price = (v.price ?? '').replace(/,/g, '')
    if (!/^\d+(\.\d{1,2})?$/.test(price)) bad('price', 'Enter a price in ₹ (e.g. 15000)')
    else if (Number(price) < 1) bad('price', 'Price must be at least ₹1')
    else if (Number(price) > 100_000_000) bad('price', 'Price is too high')
  }
})
export type ListingForm = z.infer<typeof listingSchema>
export const WIZARD_STEPS: { id: string; title: string; fields: (keyof ListingForm)[] }[] = [
  { id: 'basic', title: 'Basics', fields: ['title'] },
  { id: 'species', title: 'Species & breed', fields: ['category_id', 'breed_id'] },
  { id: 'age', title: 'Age & gender', fields: ['age_years', 'age_extra_months', 'gender', 'colour'] },
  { id: 'price', title: 'Price & type', fields: ['listing_type', 'price'] },
  { id: 'desc', title: 'Description', fields: ['description'] },
  { id: 'health', title: 'Health', fields: ['vaccination_status', 'vaccination_notes', 'health_notes', 'dewormed', 'microchipped'] },
  { id: 'photos', title: 'Photos', fields: [] },
  { id: 'location', title: 'Location', fields: ['city', 'state'] },
  { id: 'availability', title: 'Availability', fields: ['availability'] },
  { id: 'preview', title: 'Preview & submit', fields: [] },
]
