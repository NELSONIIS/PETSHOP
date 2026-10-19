import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:petora/app.dart';
import 'package:petora/core/api_client.dart';
import 'package:petora/core/config.dart';
import 'package:petora/core/token_store.dart';
import 'package:petora/data/media_picker.dart';
import 'package:petora/data/repositories.dart';
import 'package:petora/features/billing/payment_launcher.dart';
import 'package:petora/models/billing.dart';
import 'package:petora/state/providers.dart';
import 'package:petora/ui/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeResponse {
  FakeResponse(this.status, this.body);
  final int status;
  final Object? body;
}

FakeResponse ok(Object? data, {Map<String, dynamic>? meta}) => FakeResponse(200, {'data': data, 'meta': ?meta});
FakeResponse okPaged(List<Object?> items, {int total = -1}) =>
    ok(items, meta: {'page': 1, 'per_page': 20, 'total': total < 0 ? items.length : total, 'total_pages': 1});
FakeResponse noContent() => FakeResponse(204, null);
FakeResponse err(
  int status,
  String code,
  String message, {
  Map<String, dynamic>? extra,
  List<Map<String, String>>? details,
}) => FakeResponse(status, {
  'error': {'code': code, 'message': message, 'request_id': 'req-test', 'extra': ?extra, 'details': ?details},
});

typedef Handler = FutureOr<FakeResponse> Function(RequestOptions o);

/// Dio adapter that serves canned API responses; unmatched calls return 404 `not_found` and are recorded.
class FakeBackend implements HttpClientAdapter {
  final _routes = <(String, RegExp)>[];
  final log = <RequestOptions>[];
  final unmatched = <String>[];
  Duration latency = Duration.zero;

  void on(String method, String path, Object response) {
    final re = RegExp('^${RegExp.escape(path).replaceAll(r'\*', '[^/]+')}\$');
    _routes.add((method.toUpperCase(), re));
    _handlers.add(response is Handler ? response : (_) => response as FakeResponse);
  }

  final _handlers = <Handler>[];

  int count(String method, String path) => log.where((o) => o.method == method && o.path == path).length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    log.add(options);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    // Later registrations override earlier ones.
    for (var i = _routes.length - 1; i >= 0; i--) {
      final (m, re) = _routes[i];
      if (m == options.method && re.hasMatch(options.path)) {
        final r = await _handlers[i](options);
        final body = r.body == null ? '' : jsonEncode(r.body);
        return ResponseBody.fromString(
          body,
          r.status,
          headers: {
            Headers.contentTypeHeader: ['application/json'],
          },
        );
      }
    }
    unmatched.add('${options.method} ${options.path}');
    return ResponseBody.fromString(
      jsonEncode({
        'error': {'code': 'not_found', 'message': 'no fake route', 'request_id': 'x'},
      }),
      404,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

const testConfig = AppConfig(env: AppEnv.dev, apiBaseUrl: 'http://test.local/api/v1');

ApiClient fakeClient(FakeBackend b, {TokenStore? tokens, FakeBackend? refreshBackend, void Function()? onExpired}) {
  final dio = Dio()..httpClientAdapter = b;
  final rdio = Dio()..httpClientAdapter = refreshBackend ?? b;
  return ApiClient(
    config: testConfig,
    tokens: tokens ?? MemoryTokenStore(),
    dio: dio,
    refreshDio: rdio,
    onSessionExpired: onExpired,
  );
}

// ---------- fixtures ----------

Map<String, dynamic> userJson({String type = 'buyer', bool verified = true, String name = 'Asha Buyer'}) => {
  'id': 'u-1',
  'email': 'asha@example.test',
  'name': name,
  'account_type': type,
  'roles': [type],
  'email_verified': verified,
  'mfa_enabled': false,
  'mfa_verified': false,
  'created_at': '2026-01-01T00:00:00Z',
};

Map<String, dynamic> listingJson({
  String id = 'l-1',
  String title = 'Friendly Labrador puppy',
  bool verified = true,
  int price = 1500000,
  bool unlocked = false,
  String type = 'sale',
}) => {
  'id': id,
  'slug': 'slug-$id',
  'title': title,
  'listing_type': type,
  'price_minor': price,
  'currency': 'INR',
  'age_months': 3,
  'gender': 'male',
  'city': 'Pune',
  'state': 'Maharashtra',
  'category': {'id': 'c-1', 'slug': 'dogs', 'name': 'Dogs'},
  'breed': {'id': 'b-1', 'slug': 'labrador', 'name': 'Labrador'},
  'cover': null,
  'seller': {
    'id': 's-1',
    'slug': 'paws',
    'display_name': 'Paws Kennel',
    'seller_type': 'business',
    'verified': verified,
    'city': 'Pune',
    'state': 'Maharashtra',
  },
  'availability': 'available',
  'vaccination_status': 'complete',
  'featured': false,
  'is_favourite': false,
  'published_at': '2026-10-01T00:00:00Z',
  'description': 'Playful and well socialised.',
  'colour': 'Golden',
  'vaccination_notes': 'First two rounds done',
  'health_notes': '',
  'dewormed': true,
  'microchipped': null,
  'images': [],
  'attributes': {'temperament': 'Friendly'},
  'views_count': 12,
  'seller_profile': {
    'id': 's-1',
    'slug': 'paws',
    'display_name': 'Paws Kennel',
    'seller_type': 'business',
    'verified': verified,
    'city': 'Pune',
    'state': 'Maharashtra',
    'bio': 'Family run',
    'active_listings': 3,
    'member_since': '2025-01-01T00:00:00Z',
  },
  'contact': {'unlocked': unlocked, 'requires_membership': !unlocked},
  'disclaimer': 'Health details are declared by the seller. PETORA does not certify pets.',
};

Map<String, dynamic> categoryJson() => {
  'id': 'c-1',
  'slug': 'dogs',
  'name': 'Dogs',
  'icon': 'dog',
  'description': '',
  'sort_order': 1,
  'is_active': true,
  'requires_verified_seller': false,
  'listing_count': 5,
  'breeds': [
    {'id': 'b-1', 'slug': 'labrador', 'name': 'Labrador', 'is_active': true},
  ],
};

Map<String, dynamic> planJson({
  String id = 'p-1',
  String name = 'Buyer Monthly',
  int price = 49900,
  String audience = 'buyer',
}) => {
  'id': id,
  'code': 'plan-$id',
  'audience': audience,
  'name': name,
  'description': 'Unlock seller contacts',
  'price_minor': price,
  'effective_price_minor': price,
  'tax_rate_bps': 1800,
  'tax_minor': (price * 0.18).round(),
  'total_minor': price + (price * 0.18).round(),
  'currency': 'INR',
  'billing_interval': 'month',
  'interval_count': 1,
  'trial_days': 0,
  'grace_days': 3,
  'renewal_window_days': 7,
  'auto_renew': false,
  'cancellation_policy': 'end_of_period',
  'refund_window_days': 0,
  'refund_policy': 'Refunds are reviewed case by case.',
  'is_active': true,
  'sort_order': 1,
  'features': ['Email support'],
  'entitlements': {
    'listing_limit': audience == 'seller' ? 10 : null,
    'contact_unlocks': audience == 'buyer' ? 10 : null,
    'enquiries': null,
    'analytics': false,
    'featured_slots': 0,
  },
};

Map<String, dynamic> subJson({
  String status = 'active',
  bool cancelAtEnd = false,
  bool canRenew = false,
  String audience = 'buyer',
}) => {
  'audience': audience,
  'active': status == 'active' || status == 'grace',
  'subscription': {
    'id': 'sub-1',
    'status': status,
    'plan': {'id': 'p-1', 'code': 'plan-p-1', 'name': 'Buyer Monthly'},
    'starts_at': '2026-10-01T00:00:00Z',
    'current_period_end': '2026-11-01T00:00:00Z',
    'grace_ends_at': '2026-11-04T00:00:00Z',
    'cancel_at_period_end': cancelAtEnd,
    'can_renew': canRenew,
  },
  'entitlements': {
    'listing_limit': null,
    'listings_used': 0,
    'contact_unlocks': 10,
    'contact_unlocks_used': 3,
    'enquiries': null,
    'enquiries_used': 1,
    'analytics': false,
  },
};

// ---------- pump helpers ----------

class FakePaymentLauncher implements PaymentLauncher {
  FakePaymentLauncher(this.result);
  PaymentSdkResult result;
  int calls = 0;
  @override
  Future<PaymentSdkResult> launch(Checkout c, {required String name, required String email, String? phone}) async {
    calls++;
    return result;
  }
}

class FakeMediaPicker implements MediaPicker {
  FakeMediaPicker({this.images = const [], this.document});
  List<UploadFile> images;
  UploadFile? document;
  @override
  Future<UploadFile?> pickDocument() async => document;
  @override
  Future<List<UploadFile>> pickImages({bool camera = false, int limit = 8}) async => images;
}

/// Builds the whole app on top of a fake backend.
Future<Widget> buildApp(
  FakeBackend backend, {
  TokenStore? tokens,
  Map<String, Object> prefs = const {'onboarding_seen': true},
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final client = fakeClient(backend, tokens: tokens);
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      appConfigProvider.overrideWithValue(testConfig),
      apiClientProvider.overrideWithValue(client),
      ...overrides,
    ],
    child: const PetoraApp(),
  );
}

MemoryTokenStore signedInTokens() => MemoryTokenStore(const StoredTokens(access: 'access-1', refresh: 'refresh-1'));

/// Sets a phone-sized surface (logical px) and text scale for the test.
void useScreen(WidgetTester t, {double w = 360, double h = 740, double textScale = 1.0}) {
  t.view.physicalSize = Size(w, h) * 3;
  t.view.devicePixelRatio = 3;
  t.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    t.view.reset();
    t.platformDispatcher.clearTextScaleFactorTestValue();
  });
}

/// Pumps frames without waiting for infinite animations (skeletons) to finish.
Future<void> settle(WidgetTester t, {int frames = 25, int ms = 100}) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(Duration(milliseconds: ms));
  }
}

/// Registers the routes every signed-in buyer session needs.
void buyerSession(FakeBackend b) {
  b.on('GET', '/me', ok(userJson()));
  b.on('GET', '/notifications/unread-count', ok({'count': 0}));
  b.on('GET', '/buyer/enquiries', okPaged([]));
  b.on(
    'GET',
    '/subscriptions/current',
    ok(subJson(status: 'none').map((k, v) => MapEntry(k, k == 'subscription' ? null : (k == 'active' ? false : v)))),
  );
}

/// Registers public home-screen routes.
void publicHome(FakeBackend b, {List<Map<String, dynamic>>? pets}) {
  b.on('GET', '/categories', ok([categoryJson()]));
  b.on('GET', '/pets', okPaged(pets ?? [listingJson(), listingJson(id: 'l-2', title: 'Persian kitten')]));
  b.on(
    'GET',
    '/sellers',
    okPaged([
      {
        'id': 's-1',
        'slug': 'paws',
        'display_name': 'Paws Kennel',
        'seller_type': 'business',
        'verified': true,
        'city': 'Pune',
        'state': 'Maharashtra',
      },
    ]),
  );
}

/// Wraps a single screen in the providers it needs (no router) for focused widget tests.
Future<Widget> buildScreen(
  Widget screen,
  FakeBackend backend, {
  TokenStore? tokens,
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({'onboarding_seen': true});
  final sp = await SharedPreferences.getInstance();
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      sharedPrefsProvider.overrideWithValue(sp),
      appConfigProvider.overrideWithValue(testConfig),
      apiClientProvider.overrideWithValue(fakeClient(backend, tokens: tokens)),
      ...overrides,
    ],
    child: MaterialApp(theme: PetoraTheme.light(), home: screen),
  );
}

Map<String, dynamic> paymentJson({
  String id = 'pay-1',
  String status = 'created',
  String provider = 'testmode',
  String? invoice,
}) => {
  'id': id,
  'status': status,
  'plan': {'id': 'p-1', 'name': 'Buyer Monthly', 'audience': 'buyer'},
  'subtotal_minor': 49900,
  'tax_minor': 8982,
  'amount_minor': 58882,
  'refunded_minor': 0,
  'currency': 'INR',
  'provider': provider,
  'invoice_id': invoice,
  'created_at': '2026-10-18T10:00:00Z',
  'paid_at': status == 'succeeded' ? '2026-10-18T10:00:05Z' : null,
};

Map<String, dynamic> checkoutJson({String provider = 'testmode'}) => {
  'payment': paymentJson(provider: provider),
  'provider': provider,
  'provider_order_id': 'order_123',
  'provider_key_id': provider == 'razorpay' ? 'rzp_test_key' : '',
  'amount_minor': 58882,
  'currency': 'INR',
  'test_mode': provider == 'testmode',
};
