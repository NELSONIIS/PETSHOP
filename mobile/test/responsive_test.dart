import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_backend.dart';
import 'helpers/pump.dart';

FakeBackend fullBackend(String type) {
  final b = FakeBackend();
  publicHome(b);
  final seller = type == 'seller';
  b.on('GET', '/me', ok(userJson(type: type, name: 'A Very Long Display Name For Overflow Checking')));
  b.on('GET', '/notifications/unread-count', ok({'count': 12}));
  b.on(
    'GET',
    '/notifications',
    okPaged([
      {
        'id': 'n1',
        'kind': 'enquiry_reply',
        'title': 'A seller replied to your enquiry about a very long listing title',
        'body': 'Open the conversation to read the reply and respond quickly.',
        'created_at': '2026-10-18T10:00:00Z',
        'data': {},
      },
    ]),
  );
  b.on('GET', '/buyer/enquiries', okPaged([_enquiry()]));
  b.on('GET', '/buyer/enquiries/*', ok(_enquiry(withMessages: true)));
  b.on('GET', '/buyer/recently-viewed', ok([listingJson()]));
  b.on(
    'GET',
    '/favourites',
    okPaged([
      listingJson(),
      listingJson(id: 'l-2', title: 'A really long listing title that should wrap or ellipsize gracefully'),
    ]),
  );
  b.on(
    'GET',
    '/pets/*',
    ok(
      listingJson(
        title: 'An exceptionally long listing title about a lovely golden labrador puppy looking for a family',
      ),
    ),
  );
  b.on('GET', '/pets/*/similar', ok([listingJson(id: 'l-3'), listingJson(id: 'l-4')]));
  b.on('POST', '/pets/*/view', noContent());
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
  b.on(
    'GET',
    '/subscription-plans',
    ok([
      planJson(audience: seller ? 'seller' : 'buyer'),
      planJson(id: 'p-2', name: 'Yearly with a long name', price: 399900, audience: seller ? 'seller' : 'buyer'),
      planJson(id: 'p-3', name: 'Pro', price: 999900, audience: seller ? 'seller' : 'buyer'),
    ]),
  );
  b.on('GET', '/subscriptions/current', ok(subJson(audience: seller ? 'seller' : 'buyer')));
  b.on('GET', '/billing/payments', okPaged([paymentJson(status: 'succeeded', invoice: 'inv-1')]));
  b.on('GET', '/billing/invoices', okPaged([]));
  b.on('GET', '/buyer/dashboard', ok({}));
  b.on('GET', '/buyer/profile', ok({'city': 'Pune', 'state': 'Maharashtra', 'radius_km': 50}));
  b.on(
    'GET',
    '/me/sessions',
    ok([
      {
        'id': 's1',
        'client': 'mobile',
        'user_agent': 'PETORA app',
        'ip': '1.1.1.1',
        'last_used_at': '2026-10-18T10:00:00Z',
        'current': true,
      },
    ]),
  );
  b.on(
    'GET',
    '/legal/*',
    ok({
      'slug': 'terms',
      'title': 'Terms of Service',
      'version': 1,
      'body_md': '# Terms\n\n- one\n- two\n\nSome **text**.',
    }),
  );
  b.on('GET', '/disputes', ok([]));
  // seller
  b.on(
    'GET',
    '/seller/dashboard',
    ok({
      'listings': {'approved': 3, 'draft': 1, 'pending': 2, 'rejected': 1, 'sold': 1, 'expired': 1, 'suspended': 1},
      'views_30d': 1234,
      'enquiries_total': 56,
      'unread_enquiries': 7,
      'verification_status': 'pending',
      'subscription': subJson(audience: 'seller'),
      'recent_enquiries': [_enquiry()],
    }),
  );
  b.on(
    'GET',
    '/seller/listings',
    okPaged([
      {...listingJson(), 'status': 'approved'},
      {
        ...listingJson(id: 'l-2', title: 'A really long listing title that should wrap or ellipsize gracefully'),
        'status': 'pending',
      },
    ]),
  );
  b.on(
    'GET',
    '/seller/listings/*',
    ok({
      ...listingJson(),
      'status': 'rejected',
      'rejection_reason': 'Please add clearer photos of the pet',
      'missing_for_submission': ['At least one photo'],
      'moderation': [
        {'action': 'rejected', 'reason': 'x', 'created_at': '2026-10-18T10:00:00Z'},
      ],
    }),
  );
  b.on('GET', '/seller/enquiries', okPaged([_enquiry()]));
  b.on('GET', '/seller/enquiries/*', ok(_enquiry(withMessages: true)));
  b.on(
    'GET',
    '/seller/profile',
    ok({
      'id': 's-1',
      'slug': 'paws',
      'display_name': 'Paws Kennel',
      'seller_type': 'business',
      'business_name': 'Paws Kennel LLP',
      'city': 'Pune',
      'state': 'Maharashtra',
      'contact_phone': '+919876543210',
      'verification_status': 'pending',
      'verified': false,
    }),
  );
  b.on(
    'GET',
    '/seller/verification',
    ok({
      'status': 'pending',
      'documents': [
        {
          'id': 'd1',
          'kind': 'identity',
          'original_name': 'a-very-long-document-file-name-for-testing.pdf',
          'mime_type': 'application/pdf',
          'size_bytes': 2048,
          'uploaded_at': '2026-10-18T10:00:00Z',
        },
      ],
      'requirements': [],
    }),
  );
  b.on('GET', '/seller/documents', ok([]));
  b.on('GET', '/config', ok({'max_images_per_listing': 8, 'max_image_mb': 8, 'payment_provider': 'testmode'}));
  return b;
}

Map<String, dynamic> _enquiry({bool withMessages = false}) => {
  'id': 'e-1',
  'status': 'responded',
  'listing': {
    'id': 'l-1',
    'slug': 'slug-l-1',
    'title': 'Friendly Labrador puppy with an extremely long title to test wrapping',
  },
  'counterparty': {'name': 'Paws Kennel and Boarding Services Pvt Ltd'},
  'last_message': 'Yes, the puppy is still available. You can visit us this weekend between 10 and 5.',
  'last_message_at': '2026-10-18T10:00:00Z',
  'unread': 3,
  'created_at': '2026-10-18T09:00:00Z',
  if (withMessages)
    'messages': [
      {
        'id': 'm1',
        'mine': true,
        'body': 'Hello, is this pet still available? ' * 4,
        'created_at': '2026-10-18T09:00:00Z',
      },
      {'id': 'm2', 'mine': false, 'body': 'Yes it is. ' * 12, 'created_at': '2026-10-18T10:00:00Z'},
    ],
};

const sizes = [(320.0, 568.0, 1.6), (360.0, 740.0, 0.85), (411.0, 891.0, 1.3), (800.0, 1280.0, 1.0)];

const guestPaths = [
  '/',
  '/search',
  '/favourites',
  '/profile',
  '/pet/slug-l-1',
  '/login',
  '/register',
  '/forgot',
  '/plans',
  '/legal/terms',
  '/help',
  '/setup/location',
  '/category/dogs',
  '/sellers',
  '/s/paws',
  '/onboarding',
];
const buyerPaths = [
  '/',
  '/search',
  '/favourites',
  '/enquiries',
  '/profile',
  '/pet/slug-l-1',
  '/pet/l-1/contact',
  '/pet/l-1/enquire',
  '/membership',
  '/checkout/p-1',
  '/billing',
  '/notifications',
  '/enquiry/e-1',
  '/profile/security',
  '/profile/privacy',
  '/profile/delete',
  '/pets/recently-viewed',
];
const sellerPaths = [
  '/sell',
  '/sell/listings',
  '/sell/enquiries',
  '/sell/profile',
  '/sell/listing/l-9',
  '/sell/listing/new',
  '/sell/verification',
  '/sell/onboarding',
  '/sell/enquiry/e-1',
  '/plans',
  '/membership',
];

void main() {
  for (final s in sizes) {
    final label = '${s.$1.toInt()}x${s.$2.toInt()} @${s.$3}x';
    for (final entry in {'guest': guestPaths, 'buyer': buyerPaths, 'seller': sellerPaths}.entries) {
      testWidgets('no overflow/exception: ${entry.key} screens at $label', (t) async {
        useScreen(t, w: s.$1, h: s.$2, textScale: s.$3);
        final type = entry.key == 'seller' ? 'seller' : 'buyer';
        final b = fullBackend(type);
        await t.pumpWidget(
          await buildApp(
            b,
            tokens: entry.key == 'guest' ? null : signedInTokens(),
            prefs: {'onboarding_seen': entry.key != 'guest' || true},
          ),
        );
        await settle(t, frames: 12);
        final failures = <String>[];
        for (final path in entry.value) {
          await goTo(t, path);
          await settle(t, frames: 10);
          Object? ex;
          while ((ex = t.takeException()) != null) {
            failures.add('$path: ${ex.toString().split('\n').first}');
          }
        }
        expect(failures, isEmpty, reason: 'at $label');
      });
    }
  }
}
