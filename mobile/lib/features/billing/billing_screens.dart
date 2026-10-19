import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/billing.dart';
import '../../state/data.dart';
import '../../state/paged.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../../ui/widgets/buttons.dart';

/// Billing history (payments + invoices tabs).
class BillingHistoryScreen extends ConsumerWidget {
  const BillingHistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: petoraAppBar(
        context,
        'Billing',
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Payments'),
            Tab(text: 'Invoices'),
          ],
        ),
      ),
      body: const TabBarView(children: [_PaymentsTab(), _InvoicesTab()]),
    ),
  );
}

Widget _pagedList<T>(
  BuildContext context,
  PagedState<T> s, {
  required Future<void> Function() refresh,
  required VoidCallback more,
  required Widget Function(T) item,
  required String emptyTitle,
  required String emptyMsg,
  required IconData icon,
}) {
  if (s.loading && s.items.isEmpty) return const ListSkeleton();
  if (s.error != null && s.items.isEmpty) {
    return ErrorState(error: s.error!, onRetry: refresh);
  }
  if (s.items.isEmpty) {
    return EmptyState(icon: icon, title: emptyTitle, message: emptyMsg);
  }
  return RefreshIndicator(
    onRefresh: refresh,
    child: ListView.separated(
      padding: const EdgeInsets.all(PSpace.gutter),
      itemCount: s.items.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => i == s.items.length
          ? LoadMoreFooter(loading: s.loadingMore, hasMore: s.hasMore, onLoadMore: more, error: s.loadMoreError)
          : item(s.items[i]),
    ),
  );
}

class _PaymentsTab extends ConsumerWidget {
  const _PaymentsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(paymentsProvider);
    final n = ref.read(paymentsProvider.notifier);
    return _pagedList<Payment>(
      context,
      s,
      refresh: n.refresh,
      more: n.loadMore,
      emptyTitle: 'No payments yet',
      emptyMsg: 'Your plan purchases will appear here.',
      icon: Icons.receipt_long_outlined,
      item: (p) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: p.invoiceId != null ? () => context.push('/invoice/${p.invoiceId}') : null,
          child: Padding(
            padding: const EdgeInsets.all(PSpace.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.planName.isEmpty ? 'Plan purchase' : p.planName, style: context.tt.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        formatDateTime(p.paidAt ?? p.createdAt),
                        style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatMoney(p.amountMinor, currency: p.currency), style: PType.price.copyWith(fontSize: 14)),
                    const SizedBox(height: 4),
                    StatusBadge.status(p.status),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoicesTab extends ConsumerWidget {
  const _InvoicesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(invoicesProvider);
    final n = ref.read(invoicesProvider.notifier);
    return _pagedList<Invoice>(
      context,
      s,
      refresh: n.refresh,
      more: n.loadMore,
      emptyTitle: 'No invoices yet',
      emptyMsg: 'An invoice is issued after each successful payment.',
      icon: Icons.description_outlined,
      item: (i) => Card(
        child: ListTile(
          onTap: () => context.push('/invoice/${i.id}'),
          title: Text(i.number),
          subtitle: Text(formatDate(i.issuedAt)),
          trailing: Text(formatMoney(i.totalMinor, currency: i.currency), style: PType.price.copyWith(fontSize: 14)),
        ),
      ),
    );
  }
}

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.invoiceId});
  final String invoiceId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(invoiceProvider(invoiceId));
    return Scaffold(
      appBar: petoraAppBar(context, 'Invoice'),
      body: AsyncBody<Invoice>(
        value: v,
        onRetry: () => ref.invalidate(invoiceProvider(invoiceId)),
        data: (i) => ListView(
          padding: const EdgeInsets.all(PSpace.gutter),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(PSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PETORA', style: context.tt.titleLarge),
                    Text('Tax invoice', style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
                    const Divider(height: 24),
                    InfoRow('Invoice no.', i.number, bold: true),
                    InfoRow('Date', formatDate(i.issuedAt)),
                    InfoRow('Billed to', i.billToName),
                    InfoRow('Email', i.billToEmail),
                    const Divider(height: 24),
                    for (final l in i.lines) InfoRow(l.description, formatMoney(l.amountMinor, currency: i.currency)),
                    const Divider(height: 24),
                    InfoRow('Subtotal', formatMoney(i.subtotalMinor, currency: i.currency)),
                    InfoRow('Tax', formatMoney(i.taxMinor, currency: i.currency)),
                    InfoRow('Total paid', formatMoney(i.totalMinor, currency: i.currency), bold: true),
                  ],
                ),
              ),
            ),
            gap12,
            Text(
              'Need help with this invoice? Open a payment dispute from Help & support.',
              style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
            ),
            PButton('Help & support', kind: PButtonKind.ghost, onPressed: () => context.push('/help')),
          ],
        ),
      ),
    );
  }
}
