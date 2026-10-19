// Hand-written mirror of docs/openapi.yaml schemas. Keep in sync with the contract.
export type UUID = string
export interface Meta { page: number; per_page: number; total: number; total_pages: number }
export interface Envelope<T> { data: T; meta?: Meta }
export interface FieldError { field: string; message: string }

export type AccountType = 'buyer' | 'seller' | 'staff'
export interface User {
  id: UUID; email: string; phone?: string | null; name: string; account_type: AccountType
  roles: string[]; permissions?: string[]; email_verified: boolean; mfa_enabled: boolean; mfa_verified: boolean
  avatar_url?: string | null; created_at: string
}
export interface AuthResult { user: User; expires_at?: string; csrf_token?: string }
export interface RegisterRequest { name: string; email: string; phone?: string; password: string; role: 'buyer' | 'seller'; accept_terms: boolean }
export interface SessionInfo { id: string; client: string; user_agent: string; ip: string; created_at: string; last_used_at: string; current: boolean }
export interface Notification { id: string; kind: string; title: string; body: string; data: Record<string, unknown>; read: boolean; created_at: string }

export interface PublicConfig {
  brand_name: string; currency: string; maintenance: boolean; payment_provider: 'testmode' | 'razorpay'
  razorpay_key_id?: string; max_images_per_listing: number; max_image_mb: number; settings?: Record<string, unknown>
}

export interface Breed { id: UUID; slug: string; name: string; is_active: boolean }
export interface Category {
  id: UUID; slug: string; name: string; icon: string; description: string; sort_order: number; is_active: boolean
  requires_verified_seller: boolean; listing_count?: number; breeds?: Breed[]; jurisdiction_rules?: Record<string, unknown>
}
export interface CategoryInput {
  slug?: string; name: string; icon?: string; description?: string; sort_order?: number; is_active?: boolean
  requires_verified_seller?: boolean; jurisdiction_rules?: Record<string, unknown>
}

export interface ImageVariants { thumb: string; medium: string; large: string }
export interface Image extends ImageVariants { id: UUID; width: number; height: number; position: number; is_cover: boolean; alt_text: string }
export interface SellerBadge {
  id: UUID; slug: string; display_name: string; seller_type: 'individual' | 'business'; verified: boolean
  city: string; state: string; logo_url?: string | null
}
export interface ListingCard {
  id: UUID; slug: string; title: string; listing_type: 'sale' | 'adoption'; price_minor: number; currency: string
  age_months?: number | null; gender: 'male' | 'female' | 'unknown'; city: string; state: string
  category: { id: string; slug: string; name: string }; breed?: { id: string; slug: string; name: string } | null
  cover?: ImageVariants | null; seller: SellerBadge; availability: string; vaccination_status: string
  featured: boolean; is_favourite: boolean; distance_km?: number | null; published_at?: string | null
}
export interface ListingDetail extends ListingCard {
  description: string; colour: string; vaccination_notes: string; health_notes: string
  dewormed?: boolean | null; microchipped?: boolean | null; images: Image[]; attributes: Record<string, string>
  views_count: number; seller_profile: SellerPublic; contact: { unlocked: boolean; requires_membership: boolean }; disclaimer: string
}
export interface ModerationEvent { action: string; reason?: string | null; flags: string[]; moderator?: string | null; created_at: string }
export type ListingStatus = 'draft' | 'pending' | 'approved' | 'rejected' | 'suspended' | 'expired' | 'archived'
export interface ListingOwner extends ListingDetail {
  status: ListingStatus; rejection_reason?: string | null; expired_reason?: string | null; favourites_count: number
  enquiries_count: number; expires_at?: string | null; created_at: string; updated_at: string
  moderation?: ModerationEvent[]; missing_for_submission?: string[]
}
export interface ListingInput {
  title: string; description?: string; category_id: UUID; breed_id?: UUID | null; listing_type: 'sale' | 'adoption'
  price_minor?: number; age_months?: number | null; gender?: 'male' | 'female' | 'unknown'; colour?: string
  vaccination_status?: 'unspecified' | 'none' | 'partial' | 'complete'; vaccination_notes?: string; health_notes?: string
  dewormed?: boolean | null; microchipped?: boolean | null; city?: string; state?: string; lat?: number | null; lng?: number | null
  attributes?: Record<string, string>
}
export interface ListingAnalytics {
  views_total: number; favourites_total: number; enquiries_total: number; series: { date: string; views: number }[]
}
export interface SellerPublic extends SellerBadge { bio: string; member_since: string; active_listings: number; verified_at?: string | null }
export interface SellerProfileOwner extends SellerPublic {
  business_name?: string | null; gst_number?: string | null; contact_phone?: string | null; contact_whatsapp?: string | null
  contact_email?: string | null; verification_status: 'unsubmitted' | 'pending' | 'approved' | 'rejected' | 'suspended'
  lat?: number | null; lng?: number | null
}
export interface SellerProfileInput {
  display_name?: string; seller_type?: 'individual' | 'business'; business_name?: string; gst_number?: string; bio?: string
  city?: string; state?: string; lat?: number; lng?: number; contact_phone?: string; contact_whatsapp?: string; contact_email?: string
}
export interface SellerDocument { id: string; kind: string; original_name: string; mime_type: string; size_bytes: number; uploaded_at: string }
export interface VerificationStatus {
  status: SellerProfileOwner['verification_status']; submitted_at?: string | null; reviewed_at?: string | null
  reason?: string | null; documents: SellerDocument[]; requirements: string[]
}
export interface ContactInfo {
  seller_name: string; phone?: string | null; whatsapp?: string | null; email?: string | null; unlocked_at: string
  remaining_unlocks?: number | null
}
export interface BuyerProfile {
  city: string; state: string; lat?: number | null; lng?: number | null; radius_km: number
  notify_email: boolean; notify_sms: boolean; notify_push: boolean
}
export interface Message { id: string; sender_id: string; mine: boolean; body: string; created_at: string; read_at?: string | null }
export type EnquiryStatus = 'pending' | 'viewed' | 'responded' | 'closed' | 'reported'
export interface EnquirySummary {
  id: UUID; status: EnquiryStatus
  listing: { id: string; slug: string; title: string; cover?: ImageVariants | null; availability: string }
  counterparty: { name: string; slug?: string | null; user_id?: string }; last_message: string; last_message_at: string; unread: number; created_at: string
}
export interface EnquiryDetail extends EnquirySummary { messages: Message[]; first_response_at?: string | null; contact_unlocked: boolean }

export interface PlanEntitlements {
  listing_limit?: number | null; contact_unlocks?: number | null; enquiries?: number | null; analytics?: boolean; featured_slots?: number | null
}
export interface Plan {
  id: UUID; code: string; audience: 'buyer' | 'seller'; name: string; description: string; price_minor: number
  promo_price_minor?: number | null; promo_ends_at?: string | null; effective_price_minor: number; tax_rate_bps: number
  tax_minor: number; total_minor: number; currency: string; billing_interval: 'month' | 'quarter' | 'year'; interval_count: number
  trial_days: number; grace_days: number; renewal_window_days: number; auto_renew: boolean
  cancellation_policy: 'end_of_period' | 'immediate'; refund_window_days: number; refund_policy: string; is_active: boolean
  sort_order: number; features: string[]; entitlements: PlanEntitlements
  promo_starts_at?: string | null
}
export interface PlanInput {
  code: string; audience: 'buyer' | 'seller'; name: string; description?: string; price_minor: number; currency?: string
  promo_price_minor?: number | null; promo_starts_at?: string | null; promo_ends_at?: string | null
  billing_interval: 'month' | 'quarter' | 'year'; interval_count?: number; tax_rate_bps?: number; trial_days?: number
  grace_days?: number; renewal_window_days?: number; auto_renew?: boolean; cancellation_policy?: string
  refund_window_days?: number; refund_policy?: string; is_active?: boolean; sort_order?: number; features?: string[]
  entitlements?: Record<string, unknown>
}
export interface SubscriptionStatus {
  audience: 'buyer' | 'seller'; active: boolean
  subscription?: {
    id: UUID; status: 'active' | 'grace' | 'expired' | 'cancelled' | 'superseded' | 'refunded'
    plan: { id: string; code: string; name: string }; starts_at: string; current_period_end: string; grace_ends_at: string
    cancel_at_period_end: boolean; can_renew: boolean
  } | null
  entitlements: {
    listing_limit?: number | null; listings_used?: number; contact_unlocks?: number | null; contact_unlocks_used?: number
    enquiries?: number | null; enquiries_used?: number; analytics?: boolean
  }
}
export type PaymentStatus = 'created' | 'pending' | 'succeeded' | 'failed' | 'cancelled' | 'refunded' | 'partially_refunded'
export interface Payment {
  id: UUID; status: PaymentStatus; plan: { id: string; name: string; audience: string }; subtotal_minor: number; tax_minor: number
  amount_minor: number; refunded_minor: number; currency: string; provider: string; failure_reason?: string | null
  invoice_id?: string | null; created_at: string; paid_at?: string | null
}
export interface Checkout {
  payment: Payment; provider: 'testmode' | 'razorpay'; provider_order_id: string; provider_key_id?: string
  amount_minor: number; currency: string; test_mode: boolean
}
export interface Invoice {
  id: string; number: string; payment_id: string; bill_to_name: string; bill_to_email: string
  lines: { description: string; amount_minor: number }[]; subtotal_minor: number; tax_minor: number; total_minor: number
  currency: string; issued_at: string
}
export interface Refund { id: string; payment_id: string; amount_minor: number; reason: string; status: string; created_at: string }
export interface Report {
  id: string; reporter: string; target_type: string; target_id: string; target_label: string; reason: string
  details: string; status: string; resolution?: string | null; created_at: string
}
export interface Dispute {
  id: string; opened_by: string; kind: string; subject: string; message: string; status: string
  resolution?: string | null; listing_id?: string | null; payment_id?: string | null; created_at: string
}
export interface LegalPage { slug: string; title: string; version: number; body_md: string; published_at: string }
export interface Setting { key: string; value: unknown; is_public: boolean; updated_at: string }
export interface AuditLog {
  id: number; actor_id?: string | null; actor_email?: string | null; actor_roles: string[]; action: string
  entity_type: string; entity_id: string; metadata: Record<string, unknown>; ip: string; request_id: string; created_at: string
}
export interface AdminUser extends User { status: 'active' | 'suspended' | 'deleted'; last_login_at?: string | null; suspended_reason?: string | null }
export interface AdminVerification {
  id: string; seller_id: string; seller: SellerProfileOwner; user_email: string; status: string; jurisdiction_state: string
  submitted_at: string; reviewed_at?: string | null; reason?: string | null; documents: SellerDocument[]
}
export interface AdminSubscription {
  id: string; user_email: string; user_name: string; audience: string; plan_name: string; status: string
  starts_at: string; current_period_end: string
}
export interface AdminPayment extends Payment {
  user_email: string; user_name: string; provider_order_id?: string | null; provider_payment_id?: string | null; refunds: Refund[]
}
export interface AdminDashboard {
  users_total: number; active_buyers: number; active_sellers: number; pending_verifications: number; listings_total: number
  listings_approved: number; pending_moderation: number; active_subscriptions: number; monthly_recurring_revenue_minor: number
  payments_succeeded: number; payments_failed: number; revenue_30d_minor: number; refunds_total_minor: number
  open_reports: number; open_disputes: number; dead_jobs: number; currency: string
}
export interface BuyerDashboard {
  favourites: number; enquiries: number; unread_replies: number; unlocked_contacts: number
  subscription: SubscriptionStatus; recent_enquiries: EnquirySummary[]
}
export interface SellerDashboard {
  listings: Record<'draft' | 'pending' | 'approved' | 'rejected' | 'suspended' | 'expired' | 'sold', number>
  views_30d: number; enquiries_total: number; unread_enquiries: number; verification_status: string
  subscription: SubscriptionStatus; recent_enquiries: EnquirySummary[]
}
// Shapes below are not fully specified in openapi.yaml; see "contract questions" in the frontend report.
export interface RoleInfo { code: string; name?: string; description?: string; is_staff?: boolean; permissions?: string[] }
export interface NotificationTemplate { key: string; channel: 'in_app' | 'email' | 'sms'; subject?: string; body: string; is_active?: boolean; updated_at?: string }
export interface JobRow {
  id: string; kind: string; status: string; attempts: number; max_attempts?: number; last_error?: string | null
  run_at?: string; created_at?: string
}
export interface BlockedUser { user_id: string; name: string; created_at: string }
export interface AbuseEnquiry {
  id: string; status: string; listing_title: string; buyer_email: string; seller_email: string; created_at: string
  messages: { sender: 'buyer' | 'seller'; body: string; created_at: string }[]
}
export interface LegalVersion { slug: string; version: number; title: string; body_md?: string; is_current?: boolean; published_at?: string | null }
