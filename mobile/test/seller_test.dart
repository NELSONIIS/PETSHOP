import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petora/data/media_picker.dart';
import 'package:petora/data/repositories.dart';

import 'helpers/fake_backend.dart';
import 'helpers/pump.dart';

Map<String, dynamic> ownerListing({
  String id = 'l-9',
  String status = 'draft',
  List<String> missing = const [],
  String? reason,
}) => {
  ...listingJson(id: id, title: 'Beagle puppy ready for home'),
  'status': status,
  'rejection_reason': reason,
  'missing_for_submission': missing,
  'moderation': [
    {'action': 'submitted', 'created_at': '2026-10-17T10:00:00Z'},
    if (reason != null) {'action': 'rejected', 'reason': reason, 'created_at': '2026-10-18T10:00:00Z'},
  ],
  'favourites_count': 2,
  'enquiries_count': 1,
};

Map<String, dynamic> imageJson(String id, {bool cover = false}) => {
  'id': id,
  'thumb': '',
  'medium': '',
  'large': '',
  'width': 800,
  'height': 600,
  'position': 0,
  'is_cover': cover,
  'alt_text': '',
};

FakeBackend sellerBackend() {
  final b = FakeBackend();
  b.on('GET', '/me', ok(userJson(type: 'seller', name: 'Paws Seller')));
  b.on('GET', '/notifications/unread-count', ok({'count': 0}));
  b.on(
    'GET',
    '/seller/dashboard',
    ok({
      'listings': {},
      'verification_status': 'approved',
      'subscription': subJson(audience: 'seller'),
      'recent_enquiries': [],
    }),
  );
  b.on('GET', '/seller/enquiries', okPaged([]));
  b.on('GET', '/categories', ok([categoryJson()]));
  b.on('GET', '/config', ok({'max_images_per_listing': 4, 'max_image_mb': 8, 'payment_provider': 'testmode'}));
  return b;
}

UploadFile jpeg(String name, {int size = 1000}) =>
    UploadFile(name: name, mime: 'image/jpeg', bytes: Uint8List.fromList(List.filled(16, 1)), size: size);

void main() {
  group('add pet wizard - step validation', () {
    testWidgets('title, category and price are validated per step; draft is created after species', (t) async {
      useScreen(t, h: 900);
      final b = sellerBackend();
      b.on('POST', '/seller/listings', (o) => FakeResponse(201, {'data': ownerListing(id: 'l-new')}));
      b.on('PUT', '/seller/listings/l-new', ok(ownerListing(id: 'l-new')));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await t.tap(find.byType(FloatingActionButton));
      await settle(t, frames: 6);
      expect(find.text('Add a pet'), findsWidgets);
      expect(find.textContaining('Step 1 of 10'), findsOneWidget);

      // Step 1: basics
      await tapButton(t, 'Continue');
      expect(find.text('Title must be at least 5 characters'), findsOneWidget);
      expect(find.textContaining('Step 1 of 10'), findsOneWidget);
      await enter(t, 'Title', 'Beagle puppy ready for home');
      await tapButton(t, 'Continue');
      await settle(t, frames: 3);
      expect(find.textContaining('Step 2 of 10'), findsOneWidget);
      expect(b.count('POST', '/seller/listings'), 0, reason: 'nothing is saved before species is chosen');

      // Step 2: species requires a category
      await tapButton(t, 'Save draft & continue');
      await settle(t, frames: 3);
      expect(find.text('Choose a category'), findsOneWidget);
      expect(find.textContaining('Step 2 of 10'), findsOneWidget);
      await tapText(t, 'Dogs');
      await t.pump();
      await tapButton(t, 'Save draft & continue');
      await settle(t, frames: 5);
      expect(b.count('POST', '/seller/listings'), 1);
      final created = b.log.firstWhere((o) => o.method == 'POST' && o.path == '/seller/listings').data as Map;
      expect(created['title'], 'Beagle puppy ready for home');
      expect(created['category_id'], 'c-1');
      expect(created['listing_type'], 'sale');
      expect(find.textContaining('Step 3 of 10'), findsOneWidget);

      // Step 3: age - months must be 0-11
      await enter(t, 'Months', '15');
      await tapButton(t, 'Continue');
      expect(find.text('0-11'), findsOneWidget);
      await enter(t, 'Months', '3');
      await tapButton(t, 'Continue');
      await settle(t, frames: 5);
      expect(find.textContaining('Step 4 of 10'), findsOneWidget);
      expect(b.count('PUT', '/seller/listings/l-new'), 1);
      expect((b.log.lastWhere((o) => o.method == 'PUT').data as Map)['age_months'], 3);

      // Step 4: price required for sale, must be > 0
      await tapButton(t, 'Continue');
      expect(find.text('Enter a valid amount'), findsOneWidget);
      await enter(t, 'Price (₹)', '0');
      await tapButton(t, 'Continue');
      expect(find.text('Price must be greater than zero'), findsOneWidget);
      await enter(t, 'Price (₹)', '15,000');
      await tapButton(t, 'Continue');
      await settle(t, frames: 5);
      expect(find.textContaining('Step 5 of 10'), findsOneWidget);
      expect((b.log.lastWhere((o) => o.method == 'PUT').data as Map)['price_minor'], 1500000);
    });

    testWidgets('adoption listings need no price and always send 0', (t) async {
      useScreen(t, h: 900);
      final b = sellerBackend();
      b.on('POST', '/seller/listings', (o) => FakeResponse(201, {'data': ownerListing(id: 'l-new')}));
      b.on('PUT', '/seller/listings/l-new', ok(ownerListing(id: 'l-new')));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await t.tap(find.byType(FloatingActionButton));
      await settle(t, frames: 6);
      await tapText(t, 'Adoption / rehoming');
      await enter(t, 'Title', 'Two kittens need a home');
      await tapButton(t, 'Continue');
      await settle(t, frames: 3);
      await tapText(t, 'Dogs');
      await tapButton(t, 'Save draft & continue');
      await settle(t, frames: 5);
      await tapButton(t, 'Continue'); // age
      await settle(t, frames: 5);
      expect(find.textContaining('Adoption listings cannot have a price'), findsOneWidget);
      await tapButton(t, 'Continue');
      await settle(t, frames: 5);
      expect(find.textContaining('Step 5 of 10'), findsOneWidget);
      expect((b.log.lastWhere((o) => o.method == 'PUT').data as Map)['price_minor'], 0);
    });

    testWidgets('plan limit from the server opens an upgrade prompt', (t) async {
      useScreen(t, h: 900);
      final b = sellerBackend();
      b.on('POST', '/seller/listings', err(409, 'limit_reached', 'Your plan allows 10 listings.'));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await t.tap(find.byType(FloatingActionButton));
      await settle(t, frames: 6);
      await enter(t, 'Title', 'Beagle puppy ready for home');
      await tapButton(t, 'Continue');
      await settle(t, frames: 3);
      await tapText(t, 'Dogs');
      await tapButton(t, 'Save draft & continue');
      await settle(t, frames: 6);
      expect(find.text('Listing limit reached'), findsOneWidget);
      expect(find.text('View seller plans'), findsOneWidget);
      expect(find.textContaining('Step 2 of 10'), findsOneWidget, reason: 'stays on the step so nothing is lost');
    });
  });

  group('photo upload', () {
    Future<void> toPhotos(WidgetTester t, FakeBackend b, FakeMediaPicker picker) async {
      useScreen(t, h: 1000);
      b.on(
        'GET',
        '/seller/listings/l-9',
        ok({...ownerListing(), 'city': 'Pune', 'state': 'Maharashtra', 'images': []}),
      );
      b.on('PUT', '/seller/listings/l-9', ok(ownerListing()));
      await t.pumpWidget(
        await buildApp(b, tokens: signedInTokens(), overrides: [mediaPickerProvider.overrideWithValue(picker)]),
      );
      await settle(t);
      await goTo(t, '/sell/listing/l-9/edit');
      await settle(t, frames: 8);
      for (var i = 0; i < 6; i++) {
        await tapButton(t, 'Continue');
        await settle(t, frames: 4);
      }
      expect(find.textContaining('Step 7 of 10'), findsOneWidget);
    }

    testWidgets('failed upload shows Retry and succeeds on retry; first photo can be made cover', (t) async {
      final b = sellerBackend();
      var posts = 0;
      b.on('POST', '/seller/listings/l-9/images', (o) {
        posts++;
        return posts == 1
            ? err(500, 'internal_error', 'storage down')
            : FakeResponse(201, {'data': imageJson('img-1', cover: true)});
      });
      await toPhotos(t, b, FakeMediaPicker(images: [jpeg('a.jpg')]));
      // Cannot continue without a photo.
      await tapButton(t, 'Continue');
      expect(find.text('Add at least one photo'), findsOneWidget);

      await tapButton(t, 'Choose photos');
      await settle(t, frames: 6);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Uploading'), findsOneWidget);
      await tapText(t, 'Retry');
      await settle(t, frames: 8);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Your photos (1)'), findsOneWidget);
      expect(find.text('Cover photo'), findsOneWidget);
      expect(posts, 2);
      await tapButton(t, 'Continue');
      await settle(t, frames: 4);
      expect(find.textContaining('Step 8 of 10'), findsOneWidget);
    });

    testWidgets('unsupported types and oversized files are rejected before upload', (t) async {
      final b = sellerBackend();
      b.on('POST', '/seller/listings/l-9/images', (o) => FakeResponse(201, {'data': imageJson('img-1')}));
      await toPhotos(
        t,
        b,
        FakeMediaPicker(
          images: [
            const UploadFile(name: 'doc.pdf', mime: 'application/pdf', size: 100),
            jpeg('huge.jpg', size: 9 * 1024 * 1024),
          ],
        ),
      );
      await tapButton(t, 'Choose photos');
      await settle(t, frames: 4);
      expect(b.count('POST', '/seller/listings/l-9/images'), 0);
      expect(find.textContaining('larger than 8 MB'), findsOneWidget);
    });

    testWidgets('removing an uploaded photo calls the API', (t) async {
      final b = sellerBackend();
      b.on('POST', '/seller/listings/l-9/images', ok(imageJson('img-1', cover: true)));
      b.on('DELETE', '/seller/listings/l-9/images/img-1', noContent());
      await toPhotos(t, b, FakeMediaPicker(images: [jpeg('a.jpg')]));
      await tapButton(t, 'Choose photos');
      await settle(t, frames: 6);
      await t.tap(find.byTooltip('Remove photo').first);
      await settle(t, frames: 4);
      expect(b.count('DELETE', '/seller/listings/l-9/images/img-1'), 1);
      expect(find.text('Your photos (0)'), findsOneWidget);
    });
  });

  group('seller listing detail', () {
    testWidgets('rejected listing shows the moderator reason and can be resubmitted', (t) async {
      useScreen(t, h: 1000);
      final b = sellerBackend();
      b.on('GET', '/seller/listings/l-9', ok(ownerListing(status: 'rejected', reason: 'Photos do not show the pet')));
      b.on('POST', '/seller/listings/l-9/submit', ok(ownerListing(status: 'pending')));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/sell/listing/l-9');
      await settle(t, frames: 8);
      expect(find.textContaining('Photos do not show the pet'), findsWidgets);
      expect(find.text('Rejected'), findsWidgets);
      await tapButton(t, 'Submit for moderation');
      await settle(t, frames: 5);
      expect(b.count('POST', '/seller/listings/l-9/submit'), 1);
    });

    testWidgets('submitting without an active plan explains why and links to plans', (t) async {
      useScreen(t, h: 1000);
      final b = sellerBackend();
      b.on('GET', '/seller/listings/l-9', ok(ownerListing()));
      b.on(
        'POST',
        '/seller/listings/l-9/submit',
        err(402, 'subscription_required', 'An active seller subscription is required to publish.'),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/sell/listing/l-9');
      await settle(t, frames: 8);
      await tapButton(t, 'Submit for moderation');
      await settle(t, frames: 5);
      expect(find.text('An active plan is required'), findsOneWidget);
      expect(find.text('View seller plans'), findsOneWidget);
    });

    testWidgets('server checklist of missing items is displayed for drafts', (t) async {
      useScreen(t, h: 1000);
      final b = sellerBackend();
      b.on('GET', '/seller/listings/l-9', ok(ownerListing(missing: ['At least one photo', 'City and state'])));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/sell/listing/l-9');
      await settle(t, frames: 8);
      expect(find.textContaining('At least one photo'), findsOneWidget);
    });
  });

  group('verification & documents', () {
    testWidgets('submit stays disabled until a document exists; upload progress then submit', (t) async {
      useScreen(t, h: 1000);
      final b = sellerBackend();
      var docs = <Map<String, dynamic>>[];
      b.on(
        'GET',
        '/seller/verification',
        (o) => ok({
          'status': 'unsubmitted',
          'documents': docs,
          'requirements': docs.isEmpty ? ['An identity document'] : [],
        }),
      );
      b.on(
        'GET',
        '/seller/profile',
        ok({
          'id': 's-1',
          'slug': 'paws',
          'display_name': 'Paws',
          'state': 'Maharashtra',
          'verification_status': 'unsubmitted',
        }),
      );
      b.on('POST', '/seller/documents', (o) {
        docs = [
          {
            'id': 'd-1',
            'kind': 'identity',
            'original_name': 'aadhaar.pdf',
            'mime_type': 'application/pdf',
            'size_bytes': 2048,
            'uploaded_at': '2026-10-18T10:00:00Z',
          },
        ];
        return FakeResponse(201, {'data': docs.first});
      });
      b.on('POST', '/seller/verification/submit', ok({'status': 'pending', 'documents': docs, 'requirements': []}));
      final picker = FakeMediaPicker(
        document: UploadFile(name: 'aadhaar.pdf', mime: 'application/pdf', bytes: Uint8List(8), size: 2048),
      );
      await t.pumpWidget(
        await buildApp(b, tokens: signedInTokens(), overrides: [mediaPickerProvider.overrideWithValue(picker)]),
      );
      await settle(t);
      await goTo(t, '/sell/verification');
      await settle(t, frames: 8);
      expect(find.text('Not submitted'), findsWidgets);
      expect(find.text('An identity document'), findsOneWidget);
      expect(find.textContaining('Buying a plan does not verify you'), findsOneWidget);
      final submit = find.widgetWithText(FilledButton, 'Submit for verification');
      expect(t.widget<FilledButton>(submit).onPressed, isNull);

      await tapButton(t, 'Upload document');
      await settle(t, frames: 8);
      expect(find.text('aadhaar.pdf'), findsOneWidget);
      expect(t.widget<FilledButton>(submit).onPressed, isNotNull);
      await tapButton(t, 'Submit for verification');
      await settle(t, frames: 6);
      expect(b.count('POST', '/seller/verification/submit'), 1);
    });
  });

  group('seller onboarding profile', () {
    testWidgets('business sellers must give a name; contact phone is required in step 2', (t) async {
      useScreen(t, h: 1000);
      final b = sellerBackend();
      b.on(
        'GET',
        '/seller/profile',
        ok({
          'id': 's-1',
          'slug': 'paws',
          'display_name': '',
          'seller_type': 'individual',
          'verification_status': 'unsubmitted',
        }),
      );
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/sell/onboarding');
      await settle(t, frames: 8);
      await tapText(t, 'Business / breeder / shop');
      await tapButton(t, 'Continue');
      expect(find.text('Name must be at least 2 characters'), findsOneWidget);
      expect(find.text('Business name is required'), findsOneWidget);
      await enter(t, 'Public name', 'Paws Kennel');
      await enter(t, 'Registered business name', 'Paws Kennel LLP');
      await tapButton(t, 'Continue');
      await settle(t, frames: 3);
      expect(find.text('Step 2 of 2'), findsOneWidget);
      await tapButton(t, 'Save profile');
      expect(find.text('City must be at least 2 characters'), findsOneWidget);
      expect(find.text('Phone number is required'), findsOneWidget);
      expect(find.text('Select a state'), findsOneWidget);
      expect(b.count('PUT', '/seller/profile'), 0);
    });
  });
}
