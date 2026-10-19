import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../models/billing.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';
import 'payment_launcher.dart';

/// Order summary. Prices come from the backend plan - the client never decides amounts.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.planId, this.returnTo});
  final String planId;
  final String? returnTo;
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _key = const Uuid().v4();
  bool _busy = false;
  String? _error;

  Future<void> _pay(Plan plan) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // The same key is reused for double taps; it is regenerated after a failed/aborted attempt.
      final checkout = await ref.read(billingRepoProvider).checkout(plan.id, _key);
      if (!mounted) return;
      final back = widget.returnTo == null ? '' : '?return=${Uri.encodeComponent(widget.returnTo!)}';
      context.pushReplacement('/payment/${checkout.payment.id}$back', extra: checkout);
    } on AppException catch (e) {
      if (!mounted) return;
      _key = const Uuid().v4();
      if (e.kind == ErrorKind.verificationRequired) {
        setState(() => _busy = false);
        handleActionError(context, e);
        return;
      }
      setState(() {
        _busy = false;
        _error = e.kind == ErrorKind.conflict ? e.userMessage : e.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final audience = ref.watch(authProvider).user?.isSeller ?? false ? 'seller' : 'buyer';
    final plans = ref.watch(plansProvider(audience));
    return plans.when(
      loading: () => Scaffold(appBar: petoraAppBar(context, 'Checkout'), body: const ListSkeleton()),
      error: (e, _) => Scaffold(
        appBar: petoraAppBar(context, 'Checkout'),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(plansProvider(audience))),
      ),
      data: (list) {
        final plan = list.where((p) => p.id == widget.planId).firstOrNull;
        if (plan == null) {
          return Scaffold(
            appBar: petoraAppBar(context, 'Checkout'),
            body: const EmptyState(
              icon: Icons.search_off,
              title: 'Plan not found',
              message: 'This plan is no longer available.',
            ),
          );
        }
        return FormPage(
          title: 'Checkout',
          bottom: PButton(
            'Pay ${formatMoney(plan.totalMinor, currency: plan.currency)}',
            icon: Icons.lock_outline,
            onPressed: () => _pay(plan),
            loading: _busy,
          ),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(PSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plan.name, style: context.tt.titleMedium),
                    Text(
                      '${plan.periodLabel} access',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                    const Divider(height: 24),
                    InfoRow('Plan price', formatMoney(plan.effectivePriceMinor, currency: plan.currency)),
                    if (plan.hasPromo)
                      InfoRow(
                        'Promotion',
                        '-${formatMoney(plan.priceMinor - plan.effectivePriceMinor, currency: plan.currency)}',
                      ),
                    InfoRow(
                      'Tax${plan.taxRateBps > 0 ? ' (${(plan.taxRateBps / 100).toStringAsFixed(plan.taxRateBps % 100 == 0 ? 0 : 1)}%)' : ''}',
                      formatMoney(plan.taxMinor, currency: plan.currency),
                    ),
                    const Divider(height: 20),
                    InfoRow('Total', formatMoney(plan.totalMinor, currency: plan.currency), bold: true),
                  ],
                ),
              ),
            ),
            gap12,
            if (_error != null) ...[InfoBanner(_error!, tone: BannerTone.danger), gap12],
            InfoBanner(
              plan.refundPolicy.isNotEmpty
                  ? plan.refundPolicy
                  : 'Review the refund policy before paying. Payment does not guarantee any pet is available.',
              icon: Icons.policy_outlined,
            ),
            TextButton(onPressed: () => context.push('/legal/refund-policy'), child: const Text('Read refund policy')),
          ],
        );
      },
    );
  }
}

/// Payment processing -> success / failure.
/// Success is shown ONLY after the backend reports `succeeded` (server-side verified or via verified webhook).
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.paymentId,
    this.checkout,
    this.returnTo,
    this.pollInterval = const Duration(seconds: 2),
    this.maxPolls = 30,
  });
  final String paymentId;
  final Checkout? checkout;
  final String? returnTo;
  final Duration pollInterval;
  final int maxPolls;
  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

enum _Phase { awaitingPayment, processing, success, failed, timedOut }

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  _Phase _phase = _Phase.processing;
  Payment? _payment;
  String? _message;
  bool _busy = false, _polling = false;

  Checkout? get _co => widget.checkout;
  bool get _isTest => _co?.provider == 'testmode' || (_co?.testMode ?? false);

  @override
  void initState() {
    super.initState();
    _payment = _co?.payment;
    if (_co != null && _co!.provider == 'razorpay') {
      _phase = _Phase.awaitingPayment;
      WidgetsBinding.instance.addPostFrameCallback((_) => _launchSdk());
    } else if (_isTest) {
      _phase = _Phase.awaitingPayment;
    } else {
      _poll();
    }
  }

  Future<void> _launchSdk() async {
    final co = _co!;
    final user = ref.read(authProvider).user;
    setState(() => _phase = _Phase.awaitingPayment);
    final r = await ref
        .read(paymentLauncherProvider)
        .launch(co, name: user?.name ?? '', email: user?.email ?? '', phone: user?.phone);
    if (!mounted) return;
    if (r.success) {
      setState(() => _phase = _Phase.processing);
      try {
        // Never trust the SDK callback alone: ask the backend to verify with the provider.
        _payment = await ref
            .read(billingRepoProvider)
            .verify(
              widget.paymentId,
              providerPaymentId: r.paymentId,
              providerOrderId: r.orderId,
              signature: r.signature,
            );
      } on AppException catch (e) {
        if (mounted) _message = e.userMessage;
      }
      if (mounted) _poll();
    } else {
      setState(() {
        _phase = _Phase.failed;
        _message = r.cancelled ? 'Payment was cancelled. You have not been charged.' : (r.message ?? 'Payment failed');
      });
    }
  }

  Future<void> _testComplete(bool success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      _payment = await ref.read(billingRepoProvider).testComplete(widget.paymentId, success);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _Phase.processing;
      });
      _poll();
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showError(context, e);
      }
    }
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    setState(() => _phase = _Phase.processing);
    for (var i = 0; i < widget.maxPolls && mounted; i++) {
      try {
        final p = i == 0 && (_payment?.isFinal ?? false)
            ? _payment!
            : await ref.read(billingRepoProvider).payment(widget.paymentId);
        _payment = p;
        if (p.isFinal) {
          if (!mounted) return;
          _polling = false;
          if (p.succeeded) {
            ref.invalidate(subscriptionProvider);
            ref.invalidate(buyerDashboardProvider);
            ref.invalidate(paymentsProvider);
            ref.invalidate(invoicesProvider);
            ref.invalidate(petDetailProvider);
            await ref.read(authProvider.notifier).refreshUser();
          }
          setState(() {
            _phase = p.succeeded ? _Phase.success : _Phase.failed;
            _message = p.failureReason ?? (p.status == 'cancelled' ? 'The payment was cancelled.' : null);
          });
          return;
        }
      } on AppException catch (e) {
        if (e.kind == ErrorKind.unauthorized) break;
      }
      await Future<void>.delayed(widget.pollInterval);
    }
    _polling = false;
    if (mounted) setState(() => _phase = _Phase.timedOut);
  }

  void _continue() {
    final to = widget.returnTo;
    context.go(to != null && to.startsWith('/') ? to : homeFor(ref.read(authProvider).user));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.processing,
      child: Scaffold(
        appBar: AppBar(title: const Text('Payment'), automaticallyImplyLeading: _phase != _Phase.processing),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(PSpace.xl),
            child: switch (_phase) {
              _Phase.awaitingPayment => _awaiting(context),
              _Phase.processing => _processing(context),
              _Phase.success => _success(context),
              _Phase.failed => _failed(context),
              _Phase.timedOut => _timedOut(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _awaiting(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      if (_isTest) ...[
        const TestModeBanner(),
        gap16,
        Text('Test payment', style: context.tt.headlineMedium),
        const SizedBox(height: 6),
        Text(
          'No real money moves in test mode. Choose an outcome to simulate - the backend still verifies and activates (or not) exactly as in production.',
          textAlign: TextAlign.center,
          style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
        ),
        gap24,
        PButton(
          'Simulate successful payment',
          icon: Icons.check_circle_outline,
          loading: _busy,
          onPressed: () => _testComplete(true),
        ),
        gap8,
        PButton(
          'Simulate failed payment',
          kind: PButtonKind.outline,
          onPressed: _busy ? null : () => _testComplete(false),
        ),
      ] else ...[
        const CircularProgressIndicator(),
        gap16,
        Text('Opening secure payment...', style: context.tt.titleMedium),
        gap16,
        PButton('Reopen payment', kind: PButtonKind.outline, onPressed: _launchSdk, expand: false),
      ],
    ],
  );

  Widget _processing(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 4)),
      gap24,
      Text('Confirming your payment', style: context.tt.headlineMedium),
      const SizedBox(height: 8),
      Text(
        'Please keep this screen open. We are verifying the result with the payment provider.',
        textAlign: TextAlign.center,
        style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
      ),
    ],
  );

  Widget _success(BuildContext context) {
    final p = _payment;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(color: context.pc.successBg, shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 52, color: context.pc.success),
        ),
        gap24,
        Text('Payment successful', style: context.tt.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '${p?.planName ?? 'Your plan'} is now active.',
          style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
        ),
        if (p != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(formatMoney(p.amountMinor, currency: p.currency), style: context.tt.titleMedium),
          ),
        gap24,
        PButton('Continue', onPressed: _continue),
        if (p?.invoiceId != null)
          PButton('View invoice', kind: PButtonKind.ghost, onPressed: () => context.push('/invoice/${p!.invoiceId}')),
      ],
    );
  }

  Widget _failed(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(color: context.pc.dangerBg, shape: BoxShape.circle),
        child: Icon(Icons.close_rounded, size: 52, color: context.pc.danger),
      ),
      gap24,
      Text('Payment not completed', style: context.tt.headlineMedium),
      const SizedBox(height: 6),
      Text(
        _message ?? 'Your payment did not go through. You have not been charged for an active plan.',
        textAlign: TextAlign.center,
        style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
      ),
      gap24,
      PButton('Try again', onPressed: () => context.pop()),
      PButton('Back', kind: PButtonKind.ghost, onPressed: _continue),
    ],
  );

  Widget _timedOut(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.hourglass_bottom_rounded, size: 56, color: context.pc.warning),
      gap16,
      Text('Still confirming', style: context.tt.headlineMedium),
      const SizedBox(height: 6),
      Text(
        'Your bank has not confirmed yet. If you were charged, your plan activates automatically once confirmed - check Billing history shortly. You will not be charged twice.',
        textAlign: TextAlign.center,
        style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
      ),
      gap24,
      PButton('Check again', onPressed: _poll),
      PButton('Billing history', kind: PButtonKind.outline, onPressed: () => context.go('/billing')),
    ],
  );
}
