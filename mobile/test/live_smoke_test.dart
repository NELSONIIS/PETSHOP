// Opt-in smoke test against a running backend:
//   SMOKE_API_URL=http://localhost:8080/api/v1 SMOKE_LOG=/home/user/.devsvc/worker.log flutter test test/live_smoke_test.dart
// It registers a fresh buyer (so demo accounts are not altered), verifies email using the DEV EMAIL code from the
// API log, then walks locked-contact -> checkout (test mode) -> unlock -> enquiry -> seller reply.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petora/core/api_client.dart';
import 'package:petora/core/config.dart';
import 'package:petora/core/errors.dart';
import 'package:petora/core/token_store.dart';
import 'package:petora/data/repositories.dart';
import 'package:petora/models/listing.dart';

ApiClient _client(String base) => ApiClient(
  config: AppConfig(env: AppEnv.dev, apiBaseUrl: base),
  tokens: MemoryTokenStore(),
);

Future<String> _codeFromLog(String log, String email) async {
  for (var i = 0; i < 20; i++) {
    final text = await File(log).readAsString();
    final lines = text.split('\n').where((l) => l.contains('DEV EMAIL') && l.contains(email)).toList();
    if (lines.isNotEmpty) {
      final m = RegExp(r'verification code is (\d{6})').firstMatch(lines.last);
      if (m != null) return m.group(1)!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('no verification code in log for $email');
}

void main() {
  final base = Platform.environment['SMOKE_API_URL'];
  final logPath = Platform.environment['SMOKE_LOG'] ?? '/home/user/.devsvc/worker.log';
  if (base == null) {
    test('live smoke (skipped: set SMOKE_API_URL)', () {}, skip: 'SMOKE_API_URL not set');
    return;
  }

  // flutter_test_config.dart initialises the widget binding, which stubs HttpClient; use the real one here.
  setUpAll(() => HttpOverrides.global = null);

  test('public catalogue parses', () async {
    final api = _client(base);
    final cat = CatalogRepository(api);
    final cfg = await cat.config();
    expect(cfg.paymentProvider, isNotEmpty);
    final cats = await cat.categories();
    expect(cats, isNotEmpty);
    final page = await cat.pets(const PetFilter(), perPage: 5);
    expect(page.items, isNotEmpty);
    final l = page.items.first;
    expect(l.title, isNotEmpty);
    final d = await cat.pet(l.slug);
    expect(d.id, l.id);
    expect(d.contactUnlocked, isFalse);
    await cat.similar(l.id);
    final plans = await cat.plans('buyer');
    expect(plans, isNotEmpty);
    expect(plans.first.totalMinor, greaterThan(0));
    final sellers = await cat.sellers();
    expect(sellers.items, isNotEmpty);
    final filtered = await cat.pets(PetFilter(category: cats.first.slug, minPrice: 0, sort: 'price_asc'), perPage: 5);
    expect(filtered.meta.total, greaterThanOrEqualTo(0));
  });

  test('buyer journey: locked -> pay (test mode) -> unlock -> enquire -> seller reply', () async {
    final email = 'smoke+${DateTime.now().millisecondsSinceEpoch}@example.test';
    final api = _client(base);
    final auth = AuthRepository(api);
    final cat = CatalogRepository(api);
    final buyer = BuyerRepository(api);
    final billing = BillingRepository(api);

    final reg = await auth.register(name: 'Smoke Buyer', email: email, password: 'SmokeTest-2026x', role: 'buyer');
    expect(reg.user.isBuyer, isTrue);
    expect(reg.access, isNotNull);
    expect(reg.refresh, isNotNull);

    // Before verification, protected buyer actions are refused with verification_required.
    final listings = await cat.pets(const PetFilter(listingType: 'sale'), perPage: 10);
    final pet = listings.items.firstWhere((l) => l.seller.verified, orElse: () => listings.items.first);
    await expectLater(
      buyer.unlockContact(pet.id),
      throwsA(isA<AppException>().having((e) => e.kind, 'kind', ErrorKind.verificationRequired)),
    );

    await auth.verifyEmail(await _codeFromLog(logPath, email));
    expect((await auth.me()).emailVerified, isTrue);

    // Locked: 402 membership_required, with no contact data in the error.
    try {
      await buyer.unlockContact(pet.id);
      fail('expected membership_required');
    } on AppException catch (e) {
      expect(e.kind, ErrorKind.membershipRequired);
      expect(e.message.contains('+91'), isFalse);
    }

    // Favourites round trip.
    await buyer.addFavourite(pet.id);
    expect((await buyer.favourites()).items.any((l) => l.id == pet.id), isTrue);
    await buyer.removeFavourite(pet.id);

    // Checkout in test mode, then server-side verification via test-complete.
    final plan = (await cat.plans('buyer')).first;
    final key = 'smoke-key-${DateTime.now().microsecondsSinceEpoch}';
    final co = await billing.checkout(plan.id, key);
    expect(co.testMode || co.provider == 'testmode', isTrue);
    final again = await billing.checkout(plan.id, key); // idempotent replay
    expect(again.payment.id, co.payment.id);
    expect((await billing.payment(co.payment.id)).succeeded, isFalse);
    final done = await billing.testComplete(co.payment.id, true);
    expect(done.status, 'succeeded');
    final sub = await billing.current();
    expect(sub.active, isTrue);
    expect((await billing.invoices()).items, isNotEmpty);

    // Now the contact unlock is authorised.
    final c = await buyer.unlockContact(pet.id);
    expect(c.sellerName, isNotEmpty);
    expect((c.phone ?? c.whatsapp ?? c.email ?? '').isNotEmpty, isTrue);
    final c2 = await buyer.unlockContact(pet.id); // idempotent, no extra allowance used
    expect(c2.phone, c.phone);

    // Enquiry + duplicate detection.
    final enq = await buyer.createEnquiry(pet.id, 'Hello, is this pet still available?');
    expect(enq.id, isNotEmpty);
    try {
      await buyer.createEnquiry(pet.id, 'Hello again, same pet');
      fail('expected conflict');
    } on AppException catch (e) {
      expect(e.kind, ErrorKind.conflict);
      expect(e.extra?['enquiry_id'], enq.id, reason: 'OpenAPI: duplicate returns extra.enquiry_id');
    }
    expect((await buyer.enquiries()).items.any((e) => e.id == enq.id), isTrue);
    final detail = await buyer.enquiry(enq.id);
    expect(detail.messages, isNotEmpty);

    // Seller side: demo seller replies. (Demo seller is not the seller of every listing, so use the listing owner.)
    final sellerAuth = AuthRepository(_client(base));
    final sellerApi = _client(base);
    final sRepo = SellerRepository(sellerApi);
    final sellerLogin = await AuthRepository(sellerApi).login('seller@demo.petora.test', 'PetoraDemo2026!');
    expect(sellerLogin.user.isSeller, isTrue);
    expect(sellerAuth, isNotNull);
    final inbox = await sRepo.enquiries();
    final mine = inbox.items.where((e) => e.id == enq.id).toList();
    if (mine.isNotEmpty) {
      final seen = await sRepo.enquiry(enq.id);
      expect(seen.messages, isNotEmpty);
      await sRepo.sendMessage(enq.id, 'Yes, still available!');
      final back = await buyer.enquiry(enq.id);
      expect(back.messages.length, greaterThan(1));
    }

    // A different buyer must not read this enquiry (IDOR).
    final other = _client(base);
    final otherAuth = AuthRepository(other);
    await otherAuth.login('buyer@demo.petora.test', 'PetoraDemo2026!');
    await expectLater(
      BuyerRepository(other).enquiry(enq.id),
      throwsA(isA<AppException>().having((e) => e.kind, 'kind', ErrorKind.notFound)),
    );
  });

  test('token refresh: a tampered access token is transparently refreshed once', () async {
    final api = _client(base);
    final auth = AuthRepository(api);
    final r = await auth.login('buyer@demo.petora.test', 'PetoraDemo2026!');
    await api.setTokens(StoredTokens(access: 'invalid.access.token', refresh: r.refresh!));
    final results = await Future.wait([auth.me(), auth.me(), auth.me()]);
    expect(results.every((u) => u.email == 'buyer@demo.petora.test'), isTrue);
    expect(api.refreshCalls, 1, reason: 'concurrent 401s share one refresh (single-flight)');
  });

  test('seller read paths', () async {
    final api = _client(base);
    await AuthRepository(api).login('seller@demo.petora.test', 'PetoraDemo2026!');
    final s = SellerRepository(api);
    final dash = await s.dashboard();
    expect(dash.verificationStatus, isNotEmpty);
    final prof = await s.profile();
    expect(prof.slug, isNotEmpty);
    final v = await s.verification();
    expect(v.status, isNotEmpty);
    final l = await s.listings();
    expect(l.items, isNotEmpty);
    final one = await s.listing(l.items.first.id);
    expect(one.status, isNotEmpty);
    final bill = BillingRepository(api);
    final sub = await bill.current();
    expect(sub.audience, 'seller');
    await s.analytics(one.id);
  });
}
