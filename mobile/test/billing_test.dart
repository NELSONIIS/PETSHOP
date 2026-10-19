import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petora/features/billing/checkout_screens.dart';
import 'package:petora/features/billing/payment_launcher.dart';
import 'package:petora/models/billing.dart';

import 'helpers/fake_backend.dart';
import 'helpers/pump.dart';

Map<String, dynamic> noSub() => {
  'audience': 'buyer',
  'active': false,
  'subscription': null,
  'entitlements': {
    'listing_limit': null,
    'listings_used': 0,
    'contact_unlocks': null,
    'contact_unlocks_used': 0,
    'enquiries': null,
    'enquiries_used': 0,
    'analytics': false,
  },
};

FakeBackend signedInBuyer() {
  final b = FakeBackend();
  publicHome(b);
  b.on('GET', '/me', ok(userJson()));
  b.on('GET', '/notifications/unread-count', ok({'count': 0}));
  b.on('GET', '/buyer/enquiries', okPaged([]));
  b.on('GET', '/subscription-plans', ok([planJson(), planJson(id: 'p-2', name: 'Buyer Yearly', price: 399900)]));
  return b;
}

void main() {
  group('subscription states (MembershipScreen)', () {
    Future<void> open(WidgetTester t, Map<String, dynamic> sub) async {
      useScreen(t, h: 900);
      final b = signedInBuyer();
      b.on('GET', '/subscriptions/current', ok(sub));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/membership');
      await settle(t, frames: 8);
    }

    testWidgets('no plan: prompts to view plans', (t) async {
      await open(t, noSub());
      expect(find.text('No active plan'), findsOneWidget);
      expect(find.text('View plans'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('active: shows plan, dates, usage and renew/cancel', (t) async {
      await open(t, subJson());
      expect(find.text('Buyer Monthly'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('3 of 10'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Change plan'), findsOneWidget);
      expect(find.textContaining('Grace period ends'), findsNothing);
    });

    testWidgets('grace period: warns and offers renew', (t) async {
      await open(t, subJson(status: 'grace'));
      expect(find.text('Grace'), findsOneWidget);
      expect(find.text('Grace period ends'), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
    });

    testWidgets('cancel scheduled: explains benefits last until period end', (t) async {
      await open(t, subJson(cancelAtEnd: true));
      expect(find.textContaining('Cancellation scheduled'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('expired: shows the lapsed state and a Renew action', (t) async {
      await open(t, subJson(status: 'expired'));
      expect(find.text('Your plan has expired'), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
    });

    testWidgets('cancelling asks for confirmation and calls the API', (t) async {
      useScreen(t, h: 900);
      final b = signedInBuyer();
      b.on('GET', '/subscriptions/current', ok(subJson()));
      b.on('POST', '/subscriptions/sub-1/cancel', ok(subJson(cancelAtEnd: true)));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/membership');
      await settle(t, frames: 8);
      await tapButton(t, 'Cancel');
      await settle(t, frames: 4);
      expect(find.text('Cancel subscription?'), findsOneWidget);
      expect(b.count('POST', '/subscriptions/sub-1/cancel'), 0);
      await tapButton(t, 'Cancel plan');
      await settle(t, frames: 6);
      expect(b.count('POST', '/subscriptions/sub-1/cancel'), 1);
    });
  });

  group('plans', () {
    testWidgets('shows server prices with tax, marks current plan and opens the comparison', (t) async {
      useScreen(t, h: 1200);
      final b = signedInBuyer();
      b.on('GET', '/subscriptions/current', ok(subJson()));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/plans');
      await settle(t, frames: 8);
      expect(find.text('Buyer Monthly'), findsWidgets);
      expect(find.text('Buyer Yearly'), findsOneWidget);
      expect(find.text('₹499'), findsOneWidget);
      expect(find.text('₹3,999'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      await tapText(t, 'Compare');
      await settle(t, frames: 6);
      expect(find.text('Compare plans'), findsOneWidget);
      expect(find.text('Contact unlocks'), findsOneWidget);
    });
  });

  group('checkout', () {
    testWidgets('double tapping Pay creates one order; a failed attempt uses a fresh idempotency key', (t) async {
      useScreen(t, h: 900);
      final b = signedInBuyer();
      b.on('GET', '/subscriptions/current', ok(noSub()));
      final keys = <String>[];
      var n = 0;
      b.on('POST', '/subscriptions/checkout', (o) {
        keys.add((o.data as Map)['idempotency_key'] as String);
        return ++n == 1
            ? err(409, 'conflict', 'You already hold this plan')
            : FakeResponse(201, {'data': checkoutJson()});
      });
      b.on('GET', '/payments/pay-1', ok(paymentJson(status: 'created')));
      await t.pumpWidget(await buildApp(b, tokens: signedInTokens()));
      await settle(t);
      await goTo(t, '/checkout/p-1');
      await settle(t, frames: 8);
      expect(find.text('Pay ₹588.82'), findsOneWidget);

      b.latency = const Duration(milliseconds: 200);
      await tapButton(t, 'Pay ₹588.82');
      await tapButton(t, 'Pay ₹588.82'); // ignored: button is busy
      await settle(t, frames: 6);
      expect(b.count('POST', '/subscriptions/checkout'), 1, reason: 'no duplicate submission while busy');
      expect(find.text('You already hold this plan'), findsOneWidget);

      b.latency = Duration.zero;
      await tapButton(t, 'Pay ₹588.82');
      await settle(t, frames: 8);
      expect(keys, hasLength(2));
      expect(keys[0], isNot(keys[1]), reason: 'a new attempt gets a new idempotency key');
      expect(find.text('Test payment'), findsOneWidget);
      expect(find.text('TEST MODE – no real charge'), findsOneWidget);
    });
  });

  group('payment verification', () {
    Future<Widget> screen(FakeBackend b, Checkout co, FakePaymentLauncher l, {int maxPolls = 3}) => buildScreen(
      PaymentScreen(
        paymentId: 'pay-1',
        checkout: co,
        pollInterval: const Duration(milliseconds: 10),
        maxPolls: maxPolls,
      ),
      b,
      tokens: signedInTokens(),
      overrides: [paymentLauncherProvider.overrideWithValue(l)],
    );
    Checkout co(String provider) => Checkout.fromJson(checkoutJson(provider: provider));

    testWidgets('test mode: success is shown only after the backend reports succeeded', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson()));
      b.on('POST', '/payments/pay-1/test-complete', ok(paymentJson(status: 'succeeded', invoice: 'inv-1')));
      b.on('GET', '/payments/pay-1', ok(paymentJson(status: 'succeeded', invoice: 'inv-1')));
      await t.pumpWidget(
        await screen(b, co('testmode'), FakePaymentLauncher(const PaymentSdkResult.failure('unused'))),
      );
      await settle(t, frames: 4);
      expect(find.text('TEST MODE – no real charge'), findsOneWidget);
      expect(find.text('Payment successful'), findsNothing);
      await tapButton(t, 'Simulate successful payment');
      await settle(t, frames: 8);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(b.count('POST', '/payments/pay-1/test-complete'), 1);
    });

    testWidgets('test mode: simulated failure shows a failure state, never success', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson()));
      b.on(
        'POST',
        '/payments/pay-1/test-complete',
        ok(paymentJson(status: 'failed')..['failure_reason'] = 'Card declined'),
      );
      b.on('GET', '/payments/pay-1', ok(paymentJson(status: 'failed')..['failure_reason'] = 'Card declined'));
      await t.pumpWidget(await screen(b, co('testmode'), FakePaymentLauncher(const PaymentSdkResult.failure('x'))));
      await settle(t, frames: 4);
      await tapButton(t, 'Simulate failed payment');
      await settle(t, frames: 8);
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(find.text('Card declined'), findsOneWidget);
      expect(find.text('Payment successful'), findsNothing);
    });

    testWidgets('SDK success callback alone is NOT proof: pending server state never shows success', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson()));
      b.on('POST', '/payments/pay-1/verify', ok(paymentJson(status: 'pending', provider: 'razorpay')));
      b.on('GET', '/payments/pay-1', ok(paymentJson(status: 'pending', provider: 'razorpay')));
      final launcher = FakePaymentLauncher(
        const PaymentSdkResult.success(paymentId: 'pay_abc', orderId: 'order_123', signature: 'sig'),
      );
      await t.pumpWidget(await screen(b, co('razorpay'), launcher));
      await settle(t, frames: 30, ms: 20);
      expect(launcher.calls, 1);
      expect(find.text('Payment successful'), findsNothing);
      expect(find.text('Still confirming'), findsOneWidget);
      final verifyBody = b.log.firstWhere((o) => o.path == '/payments/pay-1/verify').data as Map;
      expect(verifyBody, {'provider_payment_id': 'pay_abc', 'provider_order_id': 'order_123', 'signature': 'sig'});
    });

    testWidgets('SDK success + backend verification succeeded -> success', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson()));
      b.on(
        'POST',
        '/payments/pay-1/verify',
        ok(paymentJson(status: 'succeeded', provider: 'razorpay', invoice: 'inv-1')),
      );
      b.on('GET', '/payments/pay-1', ok(paymentJson(status: 'succeeded', provider: 'razorpay', invoice: 'inv-1')));
      await t.pumpWidget(
        await screen(
          b,
          co('razorpay'),
          FakePaymentLauncher(
            const PaymentSdkResult.success(paymentId: 'pay_abc', orderId: 'order_123', signature: 'sig'),
          ),
        ),
      );
      await settle(t, frames: 10, ms: 20);
      expect(find.text('Payment successful'), findsOneWidget);
      expect(find.text('View invoice'), findsOneWidget);
    });

    testWidgets('user cancels in the SDK: reassuring failure, no verification call', (t) async {
      useScreen(t);
      final b = FakeBackend();
      b.on('GET', '/me', ok(userJson()));
      await t.pumpWidget(
        await screen(
          b,
          co('razorpay'),
          FakePaymentLauncher(const PaymentSdkResult.failure('cancelled', cancelled: true)),
        ),
      );
      await settle(t, frames: 6, ms: 20);
      expect(find.text('Payment not completed'), findsOneWidget);
      expect(find.textContaining('You have not been charged'), findsOneWidget);
      expect(b.count('POST', '/payments/pay-1/verify'), 0);
    });
  });
}
