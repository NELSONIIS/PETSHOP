import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/account/help_screens.dart';
import 'features/account/notifications_screen.dart';
import 'features/account/profile_screens.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/onboarding_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/billing/billing_screens.dart';
import 'features/billing/checkout_screens.dart';
import 'features/billing/plans_screen.dart';
import 'features/common.dart';
import 'features/enquiries/enquiries_screens.dart';
import 'features/favourites/favourites_screen.dart';
import 'features/home/home_screen.dart';
import 'features/pet/contact_screens.dart';
import 'features/pet/pet_detail_screen.dart';
import 'features/search/browse_screens.dart';
import 'features/search/search_screen.dart';
import 'features/seller/listing_wizard.dart';
import 'features/seller/seller_account_screens.dart';
import 'features/seller/seller_listing_screens.dart';
import 'features/setup/location_screen.dart';
import 'features/setup/notification_permission_screen.dart';
import 'features/shell/shells.dart';
import 'models/billing.dart';
import 'state/auth.dart';
import 'state/data.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

class _AuthListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

const _authPages = {'/login', '/register', '/onboarding', '/forgot', '/reset'};
const _buyerTabs = {'/', '/search', '/favourites', '/enquiries', '/profile'};
const _guestBlocked = [
  '/checkout',
  '/payment',
  '/notifications',
  '/billing',
  '/invoice',
  '/membership',
  '/profile/',
  '/enquiry/',
  '/sell',
  '/verify-email',
  '/setup/notifications',
  '/staff',
];

/// Pure redirect logic (unit-tested).
String? redirectFor({required AuthState auth, required String location, required bool onboardingSeen}) {
  final path = Uri.parse(location).path;
  if (auth.status == AuthStatus.unknown) {
    return path == '/splash' ? null : '/splash';
  }
  if (path == '/splash') {
    if (auth.isAuthed) return homeFor(auth.user);
    return onboardingSeen ? '/' : '/onboarding';
  }
  final user = auth.user;
  if (auth.isAuthed && user != null) {
    if (user.isStaff) {
      return path == '/staff' || path.startsWith('/legal') || path == '/help' ? null : '/staff';
    }
    if (_authPages.contains(path)) return homeFor(user);
    if (path == '/staff') return homeFor(user);
    if (user.isSeller && _buyerTabs.contains(path)) return '/sell';
    if (!user.isSeller && path.startsWith('/sell')) return '/';
    return null;
  }
  // guest
  if (_guestBlocked.any(
    (p) => path == p || path.startsWith(p.endsWith('/') ? p : '$p/') || (p == '/sell' && path.startsWith('/sell')),
  )) {
    return path.startsWith('/sell') ? '/login' : '/login?from=${Uri.encodeComponent(location)}';
  }
  return null;
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable();
  ref.listen(authProvider, (_, _) => listenable.ping());
  ref.onDispose(listenable.dispose);

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: listenable,
    redirect: (context, state) => redirectFor(
      auth: ref.read(authProvider),
      location: state.uri.toString(),
      onboardingSeen: ref.read(onboardingSeenProvider),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/login',
        builder: (_, s) => LoginScreen(from: s.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/register',
        builder: (_, s) =>
            RegisterScreen(initialRole: s.uri.queryParameters['role'] ?? 'buyer', from: s.uri.queryParameters['from']),
      ),
      GoRoute(
        path: '/verify-email',
        builder: (_, s) => VerifyEmailScreen(next: s.uri.queryParameters['next']),
      ),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset',
        builder: (_, s) => ResetPasswordScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(
        path: '/setup/location',
        builder: (_, s) => LocationScreen(next: s.uri.queryParameters['next']),
      ),
      GoRoute(path: '/setup/notifications', builder: (_, _) => const NotificationPermissionScreen()),
      GoRoute(path: '/staff', builder: (_, _) => const StaffScreen()),

      // ---- buyer shell (guests can browse) ----
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => BuyerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/search', builder: (_, _) => const SearchScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/favourites', builder: (_, _) => const FavouritesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/enquiries', builder: (_, _) => const BuyerEnquiriesScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen())],
          ),
        ],
      ),

      // ---- seller shell ----
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => SellerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/sell', builder: (_, _) => const SellerDashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/sell/listings',
                builder: (_, s) => SellerListingsScreen(initialTab: s.uri.queryParameters['tab']),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/sell/enquiries', builder: (_, _) => const SellerInboxScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/sell/profile', builder: (_, _) => const SellerProfileTab())],
          ),
        ],
      ),

      // ---- full-screen routes above the shells ----
      GoRoute(
        path: '/pet/:id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (_, s) => PetDetailScreen(idOrSlug: s.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'contact',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => ContactScreen(listingId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'enquire',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) => EnquiryFormScreen(listingId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: 'enquiry-sent',
            parentNavigatorKey: rootNavigatorKey,
            builder: (_, s) =>
                EnquirySentScreen(listingId: s.pathParameters['id']!, enquiryId: s.uri.queryParameters['eid']),
          ),
        ],
      ),
      GoRoute(
        path: '/s/:slug',
        builder: (_, s) => SellerPublicScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(path: '/sellers', builder: (_, _) => const VerifiedSellersScreen()),
      GoRoute(
        path: '/category/:slug',
        builder: (_, s) => CategoryScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/pets/:kind',
        builder: (_, s) => ListingListScreen(kind: s.pathParameters['kind']!),
      ),
      GoRoute(
        path: '/enquiry/:id',
        builder: (_, s) => EnquiryThreadScreen(id: s.pathParameters['id']!, seller: false),
      ),
      GoRoute(
        path: '/plans',
        builder: (_, s) => PlansScreen(returnTo: s.uri.queryParameters['return']),
      ),
      GoRoute(
        path: '/checkout/:planId',
        builder: (_, s) =>
            CheckoutScreen(planId: s.pathParameters['planId']!, returnTo: s.uri.queryParameters['return']),
      ),
      GoRoute(
        path: '/payment/:id',
        builder: (_, s) => PaymentScreen(
          paymentId: s.pathParameters['id']!,
          checkout: s.extra is Checkout ? s.extra as Checkout : null,
          returnTo: s.uri.queryParameters['return'],
        ),
      ),
      GoRoute(path: '/membership', builder: (_, _) => const MembershipScreen()),
      GoRoute(path: '/billing', builder: (_, _) => const BillingHistoryScreen()),
      GoRoute(
        path: '/invoice/:id',
        builder: (_, s) => InvoiceScreen(invoiceId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      GoRoute(
        path: '/legal/:slug',
        builder: (_, s) => LegalScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(path: '/profile/edit', builder: (_, _) => const EditProfileScreen()),
      GoRoute(path: '/profile/security', builder: (_, _) => const SecurityScreen()),
      GoRoute(path: '/profile/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/profile/delete', builder: (_, _) => const DeleteAccountScreen()),
      GoRoute(path: '/profile/appearance', builder: (_, _) => const AppearanceScreen()),

      // seller full-screen
      GoRoute(path: '/sell/onboarding', builder: (_, _) => const SellerOnboardingScreen()),
      GoRoute(path: '/sell/profile/edit', builder: (_, _) => const SellerOnboardingScreen(edit: true)),
      GoRoute(
        path: '/sell/verification',
        builder: (_, s) => VerificationScreen(setup: s.uri.queryParameters['setup'] == '1'),
      ),
      GoRoute(path: '/sell/listing/new', builder: (_, _) => const ListingWizardScreen()),
      GoRoute(
        path: '/sell/listing/:id',
        builder: (_, s) => SellerListingDetailScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sell/listing/:id/edit',
        builder: (_, s) => ListingWizardScreen(listingId: s.pathParameters['id']),
      ),
      GoRoute(
        path: '/sell/listing/:id/analytics',
        builder: (_, s) => ListingAnalyticsScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sell/listing/:id/submitted',
        builder: (_, s) => ListingSubmittedScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/sell/enquiry/:id',
        builder: (_, s) => EnquiryThreadScreen(id: s.pathParameters['id']!, seller: true),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Page not found'),
            TextButton(onPressed: () => context.go('/'), child: const Text('Go home')),
          ],
        ),
      ),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
});
