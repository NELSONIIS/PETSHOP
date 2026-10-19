import React, { lazy, Suspense, type ReactNode } from 'react'
import { Navigate, Route, Routes } from 'react-router-dom'
import { RequireAuth, RequireStaff } from '@/auth/guards'
import { Spinner } from '@/components/ui/Spinner'
import { PortalLayout } from '@/layouts/PortalLayout'
import { PublicLayout } from '@/layouts/PublicLayout'
import { ForgotPasswordPage, LoginPage, RegisterPage, ResetPasswordPage, VerifyEmailPage } from '@/pages/auth/Auth'
import NotFound from '@/pages/NotFound'
import { FaqPage, LegalPage, SafetyPage, SupportPage } from '@/pages/public/Content'
import Home from '@/pages/public/Home'
import PetDetail from '@/pages/public/PetDetail'
import Pricing from '@/pages/public/Pricing'
import Search from '@/pages/public/Search'
import SellerProfile from '@/pages/public/SellerProfile'

const named = <M,>(loader: () => Promise<M>, key: keyof M) => lazy(() => loader().then((m) => ({ default: m[key] as unknown as React.ComponentType })))

const BuyerDashboard = named(() => import('@/pages/buyer/Buyer'), 'BuyerDashboardPage')
const Favourites = named(() => import('@/pages/buyer/Buyer'), 'FavouritesPage')
const SellerDashboard = named(() => import('@/pages/seller/Seller'), 'SellerDashboardPage')
const SellerListings = named(() => import('@/pages/seller/Seller'), 'SellerListingsPage')
const ListingWizard = lazy(() => import('@/pages/seller/Wizard'))
const SellerAnalytics = named(() => import('@/pages/seller/SellerMore'), 'SellerAnalyticsPage')
const SellerVerification = named(() => import('@/pages/seller/SellerMore'), 'SellerVerificationPage')
const SellerProfilePage = named(() => import('@/pages/seller/SellerMore'), 'SellerProfilePage')
const AdminOverview = lazy(() => import('@/pages/admin/Overview'))
const AdminUsers = lazy(() => import('@/pages/admin/Users'))
const AdminVerifications = named(() => import('@/pages/admin/Moderation'), 'AdminVerifications')
const AdminListings = named(() => import('@/pages/admin/Moderation'), 'AdminListings')
const AdminCategories = named(() => import('@/pages/admin/Catalog'), 'AdminCategories')
const AdminPlans = named(() => import('@/pages/admin/Catalog'), 'AdminPlans')
const AdminSubscriptions = named(() => import('@/pages/admin/Finance'), 'AdminSubscriptions')
const AdminPayments = named(() => import('@/pages/admin/Finance'), 'AdminPayments')
const AdminReports = named(() => import('@/pages/admin/Trust'), 'AdminReports')
const AdminEnquiries = named(() => import('@/pages/admin/Trust'), 'AdminEnquiries')
const AdminTemplates = named(() => import('@/pages/admin/Platform'), 'AdminTemplates')
const AdminContent = named(() => import('@/pages/admin/Platform'), 'AdminContent')
const AdminSettings = named(() => import('@/pages/admin/Platform'), 'AdminSettings')
const AdminSecurity = named(() => import('@/pages/admin/Platform'), 'AdminSecurity')
const AdminMfa = named(() => import('@/pages/admin/Platform'), 'AdminMfaPage')
const AdminAudit = named(() => import('@/pages/admin/Platform'), 'AdminAudit')
const AdminJobs = named(() => import('@/pages/admin/Platform'), 'AdminJobs')
const NotificationsBuyer = lazy(() => import('@/pages/shared/Account').then((m) => ({ default: () => <m.NotificationsPage base="/buyer" /> })))
const NotificationsSeller = lazy(() => import('@/pages/shared/Account').then((m) => ({ default: () => <m.NotificationsPage base="/seller" /> })))
const ProfileSecurity = named(() => import('@/pages/shared/Account'), 'ProfileSecurityPage')
const EnquiryListBuyer = lazy(() => import('@/pages/shared/Enquiries').then((m) => ({ default: () => <m.EnquiryList role="buyer" /> })))
const EnquiryListSeller = lazy(() => import('@/pages/shared/Enquiries').then((m) => ({ default: () => <m.EnquiryList role="seller" /> })))
const EnquiryThreadBuyer = lazy(() => import('@/pages/shared/Enquiries').then((m) => ({ default: () => <m.EnquiryThread role="buyer" /> })))
const EnquiryThreadSeller = lazy(() => import('@/pages/shared/Enquiries').then((m) => ({ default: () => <m.EnquiryThread role="seller" /> })))
const MembershipBuyer = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.MembershipPage audience="buyer" /> })))
const MembershipSeller = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.MembershipPage audience="seller" /> })))
const BillingBuyer = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.BillingPage base="/buyer" /> })))
const BillingSeller = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.BillingPage base="/seller" /> })))
const InvoiceBuyer = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.InvoicePage base="/buyer" /> })))
const InvoiceSeller = lazy(() => import('@/pages/shared/Billing').then((m) => ({ default: () => <m.InvoicePage base="/seller" /> })))

const L = ({ slug, title }: { slug: string; title: string }) => <LegalPage slug={slug} title={title} />
const Loading = () => <div className="grid min-h-[40vh] place-items-center"><Spinner label="Loading page" /></div>
const S = ({ children }: { children: ReactNode }) => <Suspense fallback={<Loading />}>{children}</Suspense>
/** Permission-gated admin page (UI convenience; the API enforces permissions). */
const P = ({ perm, children }: { perm: string; children: ReactNode }) => <RequireAuth perm={perm}><S>{children}</S></RequireAuth>

export default function App() {
  return (
    <Routes>
      <Route element={<PublicLayout />}>
        <Route index element={<Home />} />
        <Route path="pets" element={<Search />} />
        <Route path="pets/:slug" element={<PetDetail />} />
        <Route path="categories/:slug" element={<Search />} />
        <Route path="sellers/:slug" element={<SellerProfile />} />
        <Route path="pricing" element={<Pricing />} />
        <Route path="safety" element={<SafetyPage />} />
        <Route path="faq" element={<FaqPage />} />
        <Route path="support" element={<SupportPage />} />
        <Route path="privacy" element={<L slug="privacy" title="Privacy policy" />} />
        <Route path="terms" element={<L slug="terms" title="Terms of service" />} />
        <Route path="refund-policy" element={<L slug="refund-policy" title="Refund policy" />} />
        <Route path="seller-policy" element={<L slug="seller-policy" title="Seller policy" />} />
        <Route path="login" element={<LoginPage />} />
        <Route path="register" element={<RegisterPage role="buyer" />} />
        <Route path="register/seller" element={<RegisterPage role="seller" />} />
        <Route path="verify-email" element={<VerifyEmailPage />} />
        <Route path="forgot-password" element={<ForgotPasswordPage />} />
        <Route path="reset-password" element={<ResetPasswordPage />} />
        <Route path="*" element={<NotFound />} />
      </Route>

      <Route path="buyer" element={<RequireAuth types={['buyer']}><PortalLayout kind="buyer" /></RequireAuth>}>
        <Route index element={<S><BuyerDashboard /></S>} />
        <Route path="favourites" element={<S><Favourites /></S>} />
        <Route path="enquiries" element={<S><EnquiryListBuyer /></S>} />
        <Route path="enquiries/:id" element={<S><EnquiryThreadBuyer /></S>} />
        <Route path="membership" element={<S><MembershipBuyer /></S>} />
        <Route path="billing" element={<S><BillingBuyer /></S>} />
        <Route path="billing/invoices/:id" element={<S><InvoiceBuyer /></S>} />
        <Route path="notifications" element={<S><NotificationsBuyer /></S>} />
        <Route path="profile" element={<S><ProfileSecurity /></S>} />
        <Route path="*" element={<NotFound />} />
      </Route>

      <Route path="seller" element={<RequireAuth types={['seller']}><PortalLayout kind="seller" /></RequireAuth>}>
        <Route index element={<S><SellerDashboard /></S>} />
        <Route path="listings" element={<S><SellerListings /></S>} />
        <Route path="listings/new" element={<S><ListingWizard /></S>} />
        <Route path="listings/:id/edit" element={<S><ListingWizard /></S>} />
        <Route path="enquiries" element={<S><EnquiryListSeller /></S>} />
        <Route path="enquiries/:id" element={<S><EnquiryThreadSeller /></S>} />
        <Route path="analytics" element={<S><SellerAnalytics /></S>} />
        <Route path="membership" element={<S><MembershipSeller /></S>} />
        <Route path="billing" element={<S><BillingSeller /></S>} />
        <Route path="billing/invoices/:id" element={<S><InvoiceSeller /></S>} />
        <Route path="verification" element={<S><SellerVerification /></S>} />
        <Route path="notifications" element={<S><NotificationsSeller /></S>} />
        <Route path="profile" element={<S><SellerProfilePage /></S>} />
        <Route path="*" element={<NotFound />} />
      </Route>

      <Route path="admin" element={<RequireStaff><PortalLayout kind="admin" /></RequireStaff>}>
        <Route index element={<P perm="dashboard.view"><AdminOverview /></P>} />
        <Route path="users" element={<P perm="users.view"><AdminUsers /></P>} />
        <Route path="verifications" element={<P perm="sellers.verify"><AdminVerifications /></P>} />
        <Route path="listings" element={<P perm="listings.moderate"><AdminListings /></P>} />
        <Route path="categories" element={<P perm="catalog.manage"><AdminCategories /></P>} />
        <Route path="plans" element={<P perm="plans.manage"><AdminPlans /></P>} />
        <Route path="subscriptions" element={<P perm="subscriptions.view"><AdminSubscriptions /></P>} />
        <Route path="payments" element={<P perm="payments.view"><AdminPayments /></P>} />
        <Route path="reports" element={<P perm="reports.manage"><AdminReports /></P>} />
        <Route path="enquiries" element={<P perm="reports.manage"><AdminEnquiries /></P>} />
        <Route path="templates" element={<P perm="content.manage"><AdminTemplates /></P>} />
        <Route path="content" element={<P perm="content.manage"><AdminContent /></P>} />
        <Route path="settings" element={<P perm="settings.manage"><AdminSettings /></P>} />
        <Route path="security" element={<S><AdminSecurity /></S>} />
        <Route path="mfa" element={<S><AdminMfa /></S>} />
        <Route path="audit" element={<P perm="audit.view"><AdminAudit /></P>} />
        <Route path="jobs" element={<P perm="settings.manage"><AdminJobs /></P>} />
        <Route path="*" element={<NotFound />} />
      </Route>
      <Route path="/index.html" element={<Navigate to="/" replace />} />
    </Routes>
  )
}
