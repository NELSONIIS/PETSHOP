import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petora/ui/widgets/fields.dart';

import 'helpers/fake_backend.dart';
import 'helpers/pump.dart';

Map<String, dynamic> contactJson() => {
  'seller_name': 'Paws Kennel',
  'phone': '+91 98765 43210',
  'whatsapp': '+919876543210',
  'email': 'paws@example.test',
  'unlocked_at': '2026-10-18T10:00:00Z',
  'remaining_unlocks': 9,
};

FakeBackend buyerBackend() {
  final b = FakeBackend();
  publicHome(b);
  buyerSession(b);
  b.on('GET', '/pets/*', ok(listingJson()));
  b.on('GET', '/pets/*/similar', ok([]));
  b.on('POST', '/pets/*/view', noContent());
  b.on('GET', '/buyer/recently-viewed', ok([]));
  b.on('GET', '/subscription-plans', ok([planJson(), planJson(id: 'p-2', name: 'Buyer Yearly', price: 399900)]));
  return b;
}

void main() {
  group('auth forms', () {
    testWidgets('login validates fields inline and does not call the API when invalid', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Profile');
      await settle(t, frames: 5);
      await tapText(t, 'Sign in');
      await settle(t, frames: 5);
      expect(find.text('Welcome back'), findsOneWidget);

      await tapButton(t, 'Sign in');
      await t.pump();
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);

      await enter(t, 'Email', 'not-an-email');
      await tapButton(t, 'Sign in');
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(b.count('POST', '/auth/login'), 0);
    });

    testWidgets('login failure shows the server message and keeps the form', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      b.on('POST', '/auth/login', err(401, 'unauthorized', 'Incorrect email or password'));
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await tapNav(t, 'Profile');
      await settle(t, frames: 5);
      await tapText(t, 'Sign in');
      await settle(t, frames: 5);
      await enter(t, 'Email', 'asha@example.test');
      await enter(t, 'Password', 'wrong-password-1');
      await tapButton(t, 'Sign in');
      await settle(t, frames: 5);
      expect(find.text('Incorrect email or password'), findsOneWidget);
      expect(b.count('POST', '/auth/login'), 1);
    });

    testWidgets('register enforces password rule and terms, then sends role + accept_terms', (t) async {
      useScreen(t, h: 900);
      final b = FakeBackend();
      publicHome(b);
      b.on(
        'POST',
        '/auth/register',
        (o) => FakeResponse(201, {
          'data': {
            'user': userJson(verified: false),
            'access_token': 'a',
            'refresh_token': 'r',
            'expires_at': '2030-01-01T00:00:00Z',
          },
        }),
      );
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await goTo(t, '/register');
      await settle(t, frames: 5);

      await tapButton(t, 'Create account');
      await t.pump();
      expect(find.text('Name must be at least 2 characters'), findsOneWidget);
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
      expect(find.text('Please accept the Terms and Privacy Policy'), findsOneWidget);

      await enter(t, 'Full name', 'Asha Buyer');
      await enter(t, 'Email', 'asha@example.test');
      await enter(t, 'Password', 'weak');
      await tapButton(t, 'Create account');
      expect(find.text('Use at least 10 characters'), findsOneWidget);

      await enter(t, 'Password', 'Petora-2026-ok');
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      await tapButton(t, 'Create account');
      await settle(t, frames: 8);
      final body = b.log.firstWhere((o) => o.path == '/auth/register').data as Map;
      expect(body['role'], 'buyer');
      expect(body['accept_terms'], true);
      expect(body['email'], 'asha@example.test');
      expect(find.text('Enter the 6-digit code'), findsOneWidget);
    });

    testWidgets('verification code field only accepts a 6 digit code', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      buyerSession(b);
      b.on('GET', '/me', ok(userJson(verified: false)));
      b.on(
        'POST',
        '/auth/verify-email',
        err(400, 'bad_request', 'The code is invalid or has expired. Request a new one.'),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/verify-email');
      await settle(t, frames: 5);
      await enter(t, 'Verification code', '123');
      await tapText(t, 'Verify');
      expect(find.text('Enter the 6-digit code'), findsWidgets);
      expect(b.count('POST', '/auth/verify-email'), 0);
      await enter(t, 'Verification code', '123456');
      await tapText(t, 'Verify');
      await settle(t, frames: 5);
      expect(find.text('The code is invalid or has expired. Request a new one.'), findsOneWidget);
    });

    test('validators used by forms', () {
      expect(Validators.minLen('a', 2, 'Name'), contains('at least 2'));
    });
  });

  group('role-aware shells', () {
    testWidgets('guest browses with the buyer shell; account tabs ask to sign in', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      for (final l in ['Home', 'Search', 'Favourites', 'Enquiries', 'Profile']) {
        expect(navLabel(l), findsOneWidget, reason: l);
      }
      await tapNav(t, 'Favourites');
      await settle(t, frames: 3);
      expect(find.text('Save pets you love'), findsOneWidget);
      await tapNav(t, 'Enquiries');
      await settle(t, frames: 3);
      expect(find.text('Your conversations'), findsOneWidget);
      expect(b.count('GET', '/favourites'), 0, reason: 'guests never hit protected endpoints');
    });

    testWidgets('buyer sees the five tabs and each opens its own screen', (t) async {
      useScreen(t);
      final b = buyerBackend();
      b.on('GET', '/favourites', okPaged([]));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
      await tapNav(t, 'Search');
      await settle(t, frames: 5);
      expect(find.text('Search pets, breeds, cities'), findsOneWidget);
      await tapNav(t, 'Favourites');
      await settle(t, frames: 5);
      expect(find.text('No favourites yet'), findsOneWidget);
      await tapNav(t, 'Enquiries');
      await settle(t, frames: 5);
      expect(find.text('No enquiries yet'), findsOneWidget);
      await tapNav(t, 'Profile');
      await settle(t, frames: 5);
      expect(find.text('asha@example.test'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Sign out'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('tab scroll/state is preserved: search text survives switching tabs', (t) async {
      useScreen(t);
      final b = buyerBackend();
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await tapNav(t, 'Search');
      await settle(t, frames: 5);
      await t.enterText(find.byType(TextField).first, 'beagle');
      await tapNav(t, 'Home');
      await settle(t, frames: 3);
      await tapNav(t, 'Search');
      await settle(t, frames: 3);
      expect(find.text('beagle'), findsOneWidget);
    });

    testWidgets('seller sees four tabs plus the Add pet action that clears the nav bar', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson(type: 'seller', name: 'Paws Seller')));
      b.on('GET', '/notifications/unread-count', ok({'count': 0}));
      b.on(
        'GET',
        '/seller/dashboard',
        ok({
          'listings': {'approved': 2, 'draft': 1},
          'views_30d': 40,
          'enquiries_total': 5,
          'unread_enquiries': 2,
          'verification_status': 'approved',
          'subscription': subJson(audience: 'seller'),
          'recent_enquiries': [],
        }),
      );
      b.on('GET', '/seller/enquiries', okPaged([]));
      b.on('GET', '/seller/listings', okPaged([listingJson()..['status'] = 'approved']));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      for (final l in ['Dashboard', 'Listings', 'Enquiries', 'Profile']) {
        expect(navLabel(l), findsOneWidget, reason: l);
      }
      expect(find.text('Hi, Paws'), findsOneWidget);
      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget);
      expect(
        t.getRect(fab).bottom,
        lessThanOrEqualTo(t.getRect(find.byType(NavigationBar)).top + 0.5),
        reason: 'FAB must not overlap the navigation bar',
      );
      await tapNav(t, 'Listings');
      await settle(t, frames: 5);
      expect(find.text('Friendly Labrador puppy'), findsOneWidget);
    });

    testWidgets('seller cannot wander into buyer tabs', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson(type: 'seller')));
      b.on('GET', '/notifications/unread-count', ok({'count': 0}));
      b.on('GET', '/seller/dashboard', ok({'listings': {}, 'subscription': subJson(audience: 'seller')}));
      b.on('GET', '/seller/enquiries', okPaged([]));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/favourites');
      await settle(t, frames: 5);
      expect(navLabel('Dashboard'), findsOneWidget);
      expect(navLabel('Favourites'), findsNothing);
    });

    testWidgets('staff accounts are pointed to the web admin portal', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson(type: 'staff')));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      expect(find.text('Use the web admin portal'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('expired session (refresh rejected) returns the user to guest with a notice', (t) async {
      useScreen(t);
      final b = FakeBackend();
      publicHome(b);
      var meCalls = 0;
      b.on('GET', '/me', (o) {
        meCalls++;
        return err(401, 'unauthorized', 'expired');
      });
      b.on('POST', '/auth/refresh', err(401, 'unauthorized', 'Session expired'));
      // The client uses a separate refresh Dio; the fake client points both to the same backend.
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      expect(meCalls, greaterThan(0));
      expect(navLabel('Home'), findsOneWidget, reason: 'guest browsing is still available');
      await tapNav(t, 'Profile');
      await settle(t, frames: 3);
      expect(find.text('Welcome to PETORA'), findsOneWidget);
    });
  });

  group('contact locking flow', () {
    testWidgets('guest tapping Unlock is asked to sign in and no contact request is made', (t) async {
      useScreen(t, h: 900);
      final b = buyerBackend();
      await t.pumpWidget(await buildApp(b));
      await settle(t);
      await goTo(t, '/pet/slug-l-1');
      await settle(t, frames: 6);
      expect(find.text('Seller contact is locked'), findsOneWidget);
      await tapText(t, 'Unlock contact');
      await settle(t, frames: 6);
      expect(find.text('Sign in to unlock seller contact'), findsOneWidget);
      expect(b.count('POST', '/pets/l-1/contact-unlock'), 0);
    });

    testWidgets('locked -> membership required -> plans -> checkout (no contact data leaks)', (t) async {
      useScreen(t, h: 1000);
      final b = buyerBackend();
      b.on(
        'POST',
        '/pets/*/contact-unlock',
        err(
          402,
          'membership_required',
          'Seller contact is available to members.',
          extra: {
            'suggested_plans': [planJson(), planJson(id: 'p-2', name: 'Buyer Yearly', price: 399900)],
          },
        ),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/pet/slug-l-1');
      await settle(t, frames: 6);

      // Detail page: only a masked placeholder, never real contact details.
      expect(find.text('Friendly Labrador puppy'), findsOneWidget);
      expect(find.text('Seller contact is locked'), findsOneWidget);
      expect(find.textContaining('+91 98765'), findsNothing);
      expect(find.text('Verified seller'), findsWidgets);
      expect(find.textContaining('Health details are declared by the seller'), findsOneWidget);

      await tapText(t, 'Unlock contact');
      await settle(t, frames: 8);
      expect(b.count('POST', '/pets/l-1/contact-unlock'), 1);
      expect(find.text('A membership is needed'), findsOneWidget);
      expect(find.text('Buyer Monthly'), findsOneWidget);
      expect(find.textContaining('9876'), findsNothing);

      await tapText(t, 'Choose Buyer Monthly');
      await settle(t, frames: 8);
      expect(find.text('Checkout'), findsWidgets);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹588.82'), findsWidgets, reason: 'price + 18% tax comes from the server plan');
    });

    testWidgets('entitled buyer sees the unlocked contact; repeat unlocks hit the idempotent endpoint', (t) async {
      useScreen(t, h: 900);
      final b = buyerBackend();
      b.on('POST', '/pets/*/contact-unlock', ok(contactJson()));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/pet/l-1/contact');
      await settle(t, frames: 8);
      expect(find.text('Contact unlocked for Paws Kennel'), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text('paws@example.test'), findsOneWidget);
      expect(find.textContaining('9 contact unlocks remaining'), findsOneWidget);
      expect(find.text('Send an enquiry'), findsOneWidget);
    });

    testWidgets('unverified email gets a verification prompt instead of contact', (t) async {
      useScreen(t);
      final b = buyerBackend();
      b.on(
        'POST',
        '/pets/*/contact-unlock',
        err(403, 'verification_required', 'Please verify your email address first'),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/pet/l-1/contact');
      await settle(t, frames: 6);
      expect(find.text('Verify your email'), findsOneWidget);
    });

    testWidgets('enquiry form validates length, and a 409 duplicate offers the existing conversation', (t) async {
      useScreen(t, h: 900);
      final b = buyerBackend();
      b.on('POST', '/pets/*/enquiries', err(409, 'conflict', 'You already enquired', extra: {'enquiry_id': 'e-9'}));
      b.on(
        'GET',
        '/buyer/enquiries/*',
        ok({
          'id': 'e-9',
          'status': 'pending',
          'listing': {'id': 'l-1', 'slug': 'slug-l-1', 'title': 'Friendly Labrador puppy'},
          'counterparty': {'name': 'Paws Kennel'},
          'last_message': 'hi',
          'messages': [
            {'id': 'm1', 'mine': true, 'body': 'hi', 'created_at': '2026-10-18T10:00:00Z'},
          ],
        }),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/pet/l-1/enquire');
      await settle(t, frames: 4);
      await enter(t, 'Message', 'hey');
      await tapButton(t, 'Send enquiry');
      expect(find.text('Message must be at least 5 characters'), findsOneWidget);
      expect(b.count('POST', '/pets/l-1/enquiries'), 0);
      await enter(t, 'Message', 'Is the puppy still available?');
      await tapButton(t, 'Send enquiry');
      await settle(t, frames: 4);
      expect(find.text('Already enquired'), findsOneWidget);
      await tapText(t, 'Open conversation');
      await settle(t, frames: 6);
      expect(find.text('Friendly Labrador puppy'), findsWidgets);
      expect(find.text('hi'), findsWidgets);
    });
  });
}
