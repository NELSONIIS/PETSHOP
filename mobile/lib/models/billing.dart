import '../core/json.dart';

class Entitlements {
  const Entitlements({
    this.listingLimit,
    this.contactUnlocks,
    this.enquiries,
    this.analytics = false,
    this.featuredSlots,
  });
  final int? listingLimit, contactUnlocks, enquiries, featuredSlots; // null = unlimited
  final bool analytics;
  factory Entitlements.fromJson(Json j) => Entitlements(
    listingLimit: J.intN(j, 'listing_limit'),
    contactUnlocks: J.intN(j, 'contact_unlocks'),
    enquiries: J.intN(j, 'enquiries'),
    featuredSlots: J.intN(j, 'featured_slots'),
    analytics: J.boolean(j, 'analytics'),
  );
}

class Plan {
  const Plan({
    required this.id,
    required this.code,
    required this.audience,
    required this.name,
    this.description = '',
    this.priceMinor = 0,
    this.promoPriceMinor,
    this.effectivePriceMinor = 0,
    this.taxMinor = 0,
    this.totalMinor = 0,
    this.taxRateBps = 0,
    this.currency = 'INR',
    this.billingInterval = 'month',
    this.intervalCount = 1,
    this.trialDays = 0,
    this.graceDays = 0,
    this.refundPolicy = '',
    this.refundWindowDays = 0,
    this.cancellationPolicy = 'end_of_period',
    this.features = const [],
    this.entitlements = const Entitlements(),
  });
  final String id, code, audience, name, description, currency, billingInterval, refundPolicy, cancellationPolicy;
  final int priceMinor,
      effectivePriceMinor,
      taxMinor,
      totalMinor,
      taxRateBps,
      intervalCount,
      trialDays,
      graceDays,
      refundWindowDays;
  final int? promoPriceMinor;
  final List<String> features;
  final Entitlements entitlements;

  bool get hasPromo => promoPriceMinor != null && effectivePriceMinor < priceMinor;

  String get periodLabel {
    final unit = {'month': 'month', 'quarter': 'quarter', 'year': 'year'}[billingInterval] ?? billingInterval;
    return intervalCount == 1 ? unit : '$intervalCount ${unit}s';
  }

  factory Plan.fromJson(Json j) {
    final eff = J.integer(j, 'effective_price_minor', J.integer(j, 'price_minor'));
    return Plan(
      id: J.str(j, 'id'),
      code: J.str(j, 'code'),
      audience: J.str(j, 'audience'),
      name: J.str(j, 'name'),
      description: J.str(j, 'description'),
      priceMinor: J.integer(j, 'price_minor'),
      promoPriceMinor: J.intN(j, 'promo_price_minor'),
      effectivePriceMinor: eff,
      taxMinor: J.integer(j, 'tax_minor'),
      totalMinor: J.integer(j, 'total_minor', eff),
      taxRateBps: J.integer(j, 'tax_rate_bps'),
      currency: J.str(j, 'currency', 'INR'),
      billingInterval: J.str(j, 'billing_interval', 'month'),
      intervalCount: J.integer(j, 'interval_count', 1),
      trialDays: J.integer(j, 'trial_days'),
      graceDays: J.integer(j, 'grace_days'),
      refundPolicy: J.str(j, 'refund_policy'),
      refundWindowDays: J.integer(j, 'refund_window_days'),
      cancellationPolicy: J.str(j, 'cancellation_policy', 'end_of_period'),
      features: J.strings(j, 'features'),
      entitlements: Entitlements.fromJson(J.map(j, 'entitlements')),
    );
  }
}

class SubInfo {
  const SubInfo({
    required this.id,
    required this.status,
    required this.planName,
    required this.planCode,
    this.startsAt,
    this.periodEnd,
    this.graceEnds,
    this.cancelAtPeriodEnd = false,
    this.canRenew = false,
  });
  final String id, status, planName, planCode;
  final DateTime? startsAt, periodEnd, graceEnds;
  final bool cancelAtPeriodEnd, canRenew;
  factory SubInfo.fromJson(Json j) {
    final plan = J.map(j, 'plan');
    return SubInfo(
      id: J.str(j, 'id'),
      status: J.str(j, 'status'),
      planName: J.str(plan, 'name'),
      planCode: J.str(plan, 'code'),
      startsAt: J.dt(j, 'starts_at'),
      periodEnd: J.dt(j, 'current_period_end'),
      graceEnds: J.dt(j, 'grace_ends_at'),
      cancelAtPeriodEnd: J.boolean(j, 'cancel_at_period_end'),
      canRenew: J.boolean(j, 'can_renew'),
    );
  }
}

class UsageEntitlements {
  const UsageEntitlements({
    this.listingLimit,
    this.listingsUsed = 0,
    this.contactUnlocks,
    this.contactUnlocksUsed = 0,
    this.enquiries,
    this.enquiriesUsed = 0,
    this.analytics = false,
  });
  final int? listingLimit, contactUnlocks, enquiries;
  final int listingsUsed, contactUnlocksUsed, enquiriesUsed;
  final bool analytics;
  int? get remainingUnlocks => contactUnlocks == null ? null : (contactUnlocks! - contactUnlocksUsed).clamp(0, 1 << 30);
  int? get remainingListings => listingLimit == null ? null : (listingLimit! - listingsUsed).clamp(0, 1 << 30);
  factory UsageEntitlements.fromJson(Json j) => UsageEntitlements(
    listingLimit: J.intN(j, 'listing_limit'),
    listingsUsed: J.integer(j, 'listings_used'),
    contactUnlocks: J.intN(j, 'contact_unlocks'),
    contactUnlocksUsed: J.integer(j, 'contact_unlocks_used'),
    enquiries: J.intN(j, 'enquiries'),
    enquiriesUsed: J.integer(j, 'enquiries_used'),
    analytics: J.boolean(j, 'analytics'),
  );
}

class SubscriptionStatus {
  const SubscriptionStatus({
    this.audience = 'buyer',
    this.active = false,
    this.subscription,
    this.entitlements = const UsageEntitlements(),
  });
  final String audience;
  final bool active;
  final SubInfo? subscription;
  final UsageEntitlements entitlements;
  bool get inGrace => subscription?.status == 'grace';
  factory SubscriptionStatus.fromJson(Json j) {
    final s = J.mapN(j, 'subscription');
    return SubscriptionStatus(
      audience: J.str(j, 'audience', 'buyer'),
      active: J.boolean(j, 'active'),
      subscription: s == null ? null : SubInfo.fromJson(s),
      entitlements: UsageEntitlements.fromJson(J.map(j, 'entitlements')),
    );
  }
}

class Payment {
  const Payment({
    required this.id,
    required this.status,
    this.planName = '',
    this.subtotalMinor = 0,
    this.taxMinor = 0,
    this.amountMinor = 0,
    this.refundedMinor = 0,
    this.currency = 'INR',
    this.provider = '',
    this.failureReason,
    this.invoiceId,
    this.createdAt,
    this.paidAt,
  });
  final String id, status, planName, currency, provider;
  final int subtotalMinor, taxMinor, amountMinor, refundedMinor;
  final String? failureReason, invoiceId;
  final DateTime? createdAt, paidAt;
  bool get isFinal => const {'succeeded', 'failed', 'cancelled', 'refunded', 'partially_refunded'}.contains(status);
  bool get succeeded => status == 'succeeded' || status == 'refunded' || status == 'partially_refunded';
  factory Payment.fromJson(Json j) => Payment(
    id: J.str(j, 'id'),
    status: J.str(j, 'status'),
    planName: J.str(J.map(j, 'plan'), 'name'),
    subtotalMinor: J.integer(j, 'subtotal_minor'),
    taxMinor: J.integer(j, 'tax_minor'),
    amountMinor: J.integer(j, 'amount_minor'),
    refundedMinor: J.integer(j, 'refunded_minor'),
    currency: J.str(j, 'currency', 'INR'),
    provider: J.str(j, 'provider'),
    failureReason: J.strN(j, 'failure_reason'),
    invoiceId: J.strN(j, 'invoice_id'),
    createdAt: J.dt(j, 'created_at'),
    paidAt: J.dt(j, 'paid_at'),
  );
}

class Checkout {
  const Checkout({
    required this.payment,
    required this.provider,
    required this.providerOrderId,
    this.providerKeyId = '',
    this.amountMinor = 0,
    this.currency = 'INR',
    this.testMode = false,
  });
  final Payment payment;
  final String provider, providerOrderId, providerKeyId, currency;
  final int amountMinor;
  final bool testMode;
  factory Checkout.fromJson(Json j) => Checkout(
    payment: Payment.fromJson(J.map(j, 'payment')),
    provider: J.str(j, 'provider'),
    providerOrderId: J.str(j, 'provider_order_id'),
    providerKeyId: J.str(j, 'provider_key_id'),
    amountMinor: J.integer(j, 'amount_minor'),
    currency: J.str(j, 'currency', 'INR'),
    testMode: J.boolean(j, 'test_mode'),
  );
}

class InvoiceLine {
  const InvoiceLine(this.description, this.amountMinor);
  final String description;
  final int amountMinor;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    this.paymentId = '',
    this.billToName = '',
    this.billToEmail = '',
    this.lines = const [],
    this.subtotalMinor = 0,
    this.taxMinor = 0,
    this.totalMinor = 0,
    this.currency = 'INR',
    this.issuedAt,
  });
  final String id, number, paymentId, billToName, billToEmail, currency;
  final List<InvoiceLine> lines;
  final int subtotalMinor, taxMinor, totalMinor;
  final DateTime? issuedAt;
  factory Invoice.fromJson(Json j) => Invoice(
    id: J.str(j, 'id'),
    number: J.str(j, 'number'),
    paymentId: J.str(j, 'payment_id'),
    billToName: J.str(j, 'bill_to_name'),
    billToEmail: J.str(j, 'bill_to_email'),
    lines: J.list(j, 'lines', (e) => InvoiceLine(J.str(e, 'description'), J.integer(e, 'amount_minor'))),
    subtotalMinor: J.integer(j, 'subtotal_minor'),
    taxMinor: J.integer(j, 'tax_minor'),
    totalMinor: J.integer(j, 'total_minor'),
    currency: J.str(j, 'currency', 'INR'),
    issuedAt: J.dt(j, 'issued_at'),
  );
}
