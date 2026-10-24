import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/billing.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';

/// Membership plans (#40) with comparison (#41). Audience follows the signed-in account type.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key, this.returnTo});
  final String? returnTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).user;
    final audience = (user?.isSeller ?? false) ? 'seller' : 'buyer';
    final plans = ref.watch(plansProvider(audience));
    final sub = user == null ? null : ref.watch(subscriptionProvider).asData?.value;
    final cur = sub?.subscription;
    return Scaffold(
      appBar: petoraAppBar(
        context,
        audience == 'seller' ? 'Seller plans' : 'Membership plans',
        actions: [
          plans.maybeWhen(
            data: (l) => l.length > 1
                ? TextButton(onPressed: () => _compare(context, l), child: const Text('Compare'))
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: AsyncBody<List<Plan>>(
        value: plans,
        onRetry: () => ref.invalidate(plansProvider(audience)),
        data: (list) => list.isEmpty
            ? const EmptyState(
                icon: Icons.workspace_premium_outlined,
                title: 'No plans available',
                message: 'Plans are not available right now. Please check back soon.',
              )
            : RefreshIndicator(
                onRefresh: () async => ref.refresh(plansProvider(audience).future),
                child: ListView(
                  padding: const EdgeInsets.all(PSpace.gutter),
                  children: [
                    if (sub != null && sub.active && cur != null) ...[
                      InfoBanner(
                        'You are on ${cur.planName} until ${formatDate(cur.periodEnd)}${sub.inGrace ? ' (grace period - renew now to keep your benefits)' : ''}.',
                        tone: sub.inGrace ? BannerTone.warning : BannerTone.success,
                        icon: Icons.workspace_premium_outlined,
                      ),
                      gap12,
                    ],
                    Text(
                      audience == 'seller' ? 'Publish pets and reach buyers' : 'Unlock seller contacts',
                      style: context.tt.headlineMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      audience == 'seller'
                          ? 'Choose the plan that fits your listings. Verification is reviewed separately - payment never counts as verification.'
                          : 'Browsing is free. A membership unlocks seller phone, WhatsApp and email, and lets you send enquiries. It does not guarantee any pet is available.',
                      style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                    ),
                    gap16,
                    for (var i = 0; i < list.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: PlanCard(
                          plan: list[i],
                          highlighted: list.length > 1 && i == (list.length > 2 ? 1 : 0),
                          current: cur != null && sub!.active && cur.planCode == list[i].code,
                          ctaLabel: cur != null && sub!.active
                              ? (cur.planCode == list[i].code ? 'Renew' : 'Switch to this plan')
                              : 'Choose plan',
                          onSelect: () async {
                            if (!await ensureSignedIn(context, ref, reason: 'Sign in to choose a plan')) {
                              return;
                            }
                            if (context.mounted) {
                              context.push(
                                '/checkout/${list[i].id}${returnTo == null ? '' : '?return=${Uri.encodeComponent(returnTo!)}'}',
                              );
                            }
                          },
                        ),
                      ),
                    if (audience == 'buyer') ...[
                      const _BuyerTrustCard(),
                      gap16,
                    ],
                    Text(
                      'Prices include applicable taxes as shown at checkout. See the refund policy before purchasing.',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                    TextButton(
                      onPressed: () => context.push('/legal/refund-policy'),
                      child: const Text('Refund policy'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _compare(BuildContext context, List<Plan> plans) =>
      showPetoraSheet<void>(context, builder: (_) => PlanComparison(plans: plans));
}

class _BuyerTrustCard extends StatelessWidget {
  const _BuyerTrustCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PSpace.md),
      decoration: BoxDecoration(
        color: context.pc.bgWarm,
        borderRadius: PRadius.cardR,
        border: Border.all(color: context.pc.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18, color: PColor.primary600),
              gap8,
              Expanded(
                child: Text(
                  'Why is there a fee to unlock contacts?',
                  style: context.tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          gap8,
          Text(
            'Browsing is 100% free. We charge a nominal membership fee (from \u20B950) to protect pets and keep our community safe and spam-free:',
            style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
          ),
          gap12,
          _point(context, Icons.pets, 'Protects pets & prevents scams',
              'Stops puppy mills, commercial flippers, and automated bots from harvesting phone numbers.'),
          gap8,
          _point(context, Icons.verified_user_outlined, 'Serious adopters only',
              'Sellers know callers are genuine pet lovers, eliminating spam calls and time-wasters.'),
          gap8,
          _point(context, Icons.phone_in_talk_outlined, 'Direct, zero brokerage',
              'Talk directly via phone & WhatsApp with verified pet parents \u2014 no middlemen or hidden fees.'),
        ],
      ),
    );
  }

  Widget _point(BuildContext context, IconData icon, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: PColor.primary600),
        gap8,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
              Text(body, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
            ],
          ),
        ),
      ],
    );
  }
}

class PlanComparison extends StatelessWidget {
  const PlanComparison({super.key, required this.plans});
  final List<Plan> plans;

  @override
  Widget build(BuildContext context) {
    final seller = plans.first.audience == 'seller';
    final rows = <(String, String Function(Plan))>[
      ('Price', (p) => formatMoney(p.effectivePriceMinor, currency: p.currency)),
      ('Period', (p) => p.periodLabel),
      if (!seller) ('Contact unlocks', (p) => p.entitlements.contactUnlocks?.toString() ?? 'Unlimited'),
      if (!seller) ('Enquiries', (p) => p.entitlements.enquiries?.toString() ?? 'Unlimited'),
      if (seller) ('Listings', (p) => p.entitlements.listingLimit?.toString() ?? 'Unlimited'),
      if (seller) ('Analytics', (p) => p.entitlements.analytics ? 'Included' : '-'),
      if (seller) ('Featured slots', (p) => '${p.entitlements.featuredSlots ?? 0}'),
      ('Grace period', (p) => p.graceDays == 0 ? '-' : '${p.graceDays} days'),
      ('Refund window', (p) => p.refundWindowDays == 0 ? 'None' : '${p.refundWindowDays} days'),
    ];
    return SheetScaffold(
      title: 'Compare plans',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 44,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 52,
          columns: [
            const DataColumn(label: Text('')),
            for (final p in plans) DataColumn(label: Text(p.name, style: context.tt.titleSmall)),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  DataCell(Text(r.$1, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted))),
                  for (final p in plans) DataCell(Text(r.$2(p))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Subscription / membership management (summary, renew, upgrade, cancel) - buyers and sellers.
class MembershipScreen extends ConsumerWidget {
  const MembershipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(subscriptionProvider);
    final user = ref.watch(authProvider).user;
    final seller = user?.isSeller ?? false;
    return Scaffold(
      appBar: petoraAppBar(context, seller ? 'Subscription' : 'Membership'),
      body: AsyncBody<SubscriptionStatus>(
        value: v,
        onRetry: () => ref.invalidate(subscriptionProvider),
        data: (s) {
          final sub = s.subscription;
          final e = s.entitlements;
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(subscriptionProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(PSpace.gutter),
              children: [
                if (sub == null || (!s.active))
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(PSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub == null ? 'No active plan' : 'Your plan has ${sub.status}',
                            style: context.tt.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            seller
                                ? 'Subscribe to publish listings. Your existing listings follow the expiry policy and return when you renew.'
                                : 'Choose a membership to unlock seller contacts.',
                            style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                          ),
                          gap12,
                          PButton(sub == null ? 'View plans' : 'Renew', onPressed: () => context.push('/plans')),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(PSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(sub.planName, style: context.tt.titleMedium)),
                              StatusBadge.status(sub.status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          InfoRow('Started', formatDate(sub.startsAt)),
                          InfoRow(sub.cancelAtPeriodEnd ? 'Ends' : 'Renews / ends', formatDate(sub.periodEnd)),
                          if (sub.status == 'grace') InfoRow('Grace period ends', formatDate(sub.graceEnds)),
                          const Divider(height: 20),
                          if (seller) ...[
                            InfoRow('Listings used', '${e.listingsUsed} of ${e.listingLimit ?? 'unlimited'}'),
                            InfoRow('Analytics', e.analytics ? 'Included' : 'Not included'),
                          ] else ...[
                            InfoRow(
                              'Contact unlocks used',
                              '${e.contactUnlocksUsed} of ${e.contactUnlocks ?? 'unlimited'}',
                            ),
                            InfoRow('Enquiries used', '${e.enquiriesUsed} of ${e.enquiries ?? 'unlimited'}'),
                          ],
                          if (sub.cancelAtPeriodEnd) ...[
                            gap8,
                            const InfoBanner(
                              'Cancellation scheduled - benefits continue until the end date.',
                              tone: BannerTone.warning,
                            ),
                          ],
                          gap12,
                          Row(
                            children: [
                              Expanded(
                                child: PButton(
                                  sub.canRenew || sub.status == 'grace' ? 'Renew' : 'Change plan',
                                  onPressed: () => context.push('/plans'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              if (!sub.cancelAtPeriodEnd)
                                Expanded(
                                  child: PButton(
                                    'Cancel',
                                    kind: PButtonKind.outline,
                                    onPressed: () async {
                                      final ok = await confirmDialog(
                                        context,
                                        title: 'Cancel subscription?',
                                        message: 'Cancellation follows the plan policy. Refunds are not automatic - see the refund policy.',
                                        confirmLabel: 'Cancel plan',
                                        destructive: true,
                                      );
                                      if (!ok || !context.mounted) return;
                                      try {
                                        await ref.read(billingRepoProvider).cancel(sub.id);
                                        ref.invalidate(subscriptionProvider);
                                        if (context.mounted) {
                                          showSnack(context, 'Cancellation recorded');
                                        }
                                      } catch (err) {
                                        if (context.mounted) {
                                          showError(context, err);
                                        }
                                      }
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                gap16,
                MenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Billing history & invoices',
                  onTap: () => context.push('/billing'),
                ),
                MenuTile(
                  icon: Icons.policy_outlined,
                  title: 'Refund policy',
                  onTap: () => context.push('/legal/refund-policy'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
