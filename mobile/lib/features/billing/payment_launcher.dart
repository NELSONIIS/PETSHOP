import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../models/billing.dart';

class PaymentSdkResult {
  const PaymentSdkResult.success({this.paymentId, this.orderId, this.signature})
    : success = true,
      cancelled = false,
      message = null;
  const PaymentSdkResult.failure(this.message, {this.cancelled = false})
    : success = false,
      paymentId = null,
      orderId = null,
      signature = null;
  final bool success, cancelled;
  final String? paymentId, orderId, signature, message;
}

/// Boundary around the provider's mobile SDK so the app logic (and tests) never depend on it.
/// A success callback from the SDK is NOT proof of payment: callers must always verify server-side.
abstract class PaymentLauncher {
  Future<PaymentSdkResult> launch(Checkout checkout, {required String name, required String email, String? phone});
}

class RazorpayLauncher implements PaymentLauncher {
  @override
  Future<PaymentSdkResult> launch(Checkout c, {required String name, required String email, String? phone}) {
    final completer = Completer<PaymentSdkResult>();
    final rz = Razorpay();
    void done(PaymentSdkResult r) {
      if (!completer.isCompleted) completer.complete(r);
      rz.clear();
    }

    rz.on(
      Razorpay.EVENT_PAYMENT_SUCCESS,
      (PaymentSuccessResponse r) =>
          done(PaymentSdkResult.success(paymentId: r.paymentId, orderId: r.orderId, signature: r.signature)),
    );
    rz.on(
      Razorpay.EVENT_PAYMENT_ERROR,
      (PaymentFailureResponse r) => done(
        PaymentSdkResult.failure(
          r.message ?? 'Payment was not completed',
          cancelled: r.code == Razorpay.PAYMENT_CANCELLED,
        ),
      ),
    );
    rz.on(
      Razorpay.EVENT_EXTERNAL_WALLET,
      (ExternalWalletResponse r) => done(
        const PaymentSdkResult.failure(
          'External wallet selected - please complete payment in the wallet app and check your billing history.',
        ),
      ),
    );
    try {
      rz.open({
        'key': c.providerKeyId, // public key id only; the secret never leaves the server
        'amount': c.amountMinor,
        'currency': c.currency,
        'order_id': c.providerOrderId,
        'name': 'PETORA',
        'description': c.payment.planName,
        'prefill': {'name': name, 'email': email, if (phone != null && phone.isNotEmpty) 'contact': phone},
        'theme': {'color': '#1E6B44'},
        'retry': {'enabled': false},
      });
    } catch (e) {
      done(PaymentSdkResult.failure('Could not open the payment screen: $e'));
    }
    return completer.future;
  }
}

final paymentLauncherProvider = Provider<PaymentLauncher>((ref) => RazorpayLauncher());
