import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../models/common.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  IconData _icon(String kind) {
    if (kind.contains('enquiry') || kind.contains('message')) {
      return Icons.chat_bubble_outline;
    }
    if (kind.contains('payment') || kind.contains('subscription') || kind.contains('refund')) {
      return Icons.receipt_long_outlined;
    }
    if (kind.contains('listing')) return Icons.pets;
    if (kind.contains('seller') || kind.contains('verif')) {
      return Icons.verified_outlined;
    }
    return Icons.notifications_none;
  }

  void _open(BuildContext context, WidgetRef ref, Notice n) {
    final d = n.data;
    final seller = ref.read(authProvider).user?.isSeller ?? false;
    final enq = d['enquiry_id']?.toString();
    final listing = (d['listing_slug'] ?? d['listing_id'])?.toString();
    if (enq != null && enq.isNotEmpty) {
      context.push(seller ? '/sell/enquiry/$enq' : '/enquiry/$enq');
    } else if (listing != null && listing.isNotEmpty) {
      context.push(seller ? '/sell/listing/${d['listing_id'] ?? listing}' : '/pet/$listing');
    } else if (n.kind.contains('payment') || n.kind.contains('subscription') || n.kind.contains('refund')) {
      context.push('/billing');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(notificationsProvider);
    final n = ref.read(notificationsProvider.notifier);
    return Scaffold(
      appBar: petoraAppBar(
        context,
        'Notifications',
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref.read(accountRepoProvider).markAllRead();
                await n.refresh();
                ref.invalidate(unreadCountProvider);
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: s.loading && s.items.isEmpty
          ? const ListSkeleton()
          : s.error != null && s.items.isEmpty
          ? ErrorState(error: s.error!, onRetry: n.refresh)
          : s.items.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'All caught up',
              message: 'Replies, approvals and billing updates will appear here.',
            )
          : RefreshIndicator(
              onRefresh: n.refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (x) {
                  if (x.metrics.extentAfter < 400 && s.loadMoreError == null) n.loadMore();
                  return false;
                },
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: s.items.length + 1,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, i) {
                    if (i == s.items.length) {
                      return LoadMoreFooter(
                        loading: s.loadingMore,
                        hasMore: s.hasMore,
                        onLoadMore: n.loadMore,
                        error: s.loadMoreError,
                      );
                    }
                    final x = s.items[i];
                    return ListTile(
                      tileColor: x.read ? null : context.cs.primaryContainer.withValues(alpha: 0.35),
                      leading: Icon(_icon(x.kind), color: context.cs.primary),
                      title: Text(
                        x.title,
                        style: context.tt.titleSmall?.copyWith(fontWeight: x.read ? FontWeight.w500 : FontWeight.w700),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (x.body.isNotEmpty) Text(x.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                          Text(
                            timeAgo(x.createdAt),
                            style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (!x.read) {
                          try {
                            await ref.read(accountRepoProvider).markRead(x.id);
                            n.mutate(
                              (l) => [
                                for (final e in l)
                                  e.id == x.id
                                      ? Notice(
                                          id: e.id,
                                          kind: e.kind,
                                          title: e.title,
                                          body: e.body,
                                          read: true,
                                          createdAt: e.createdAt,
                                          data: e.data,
                                        )
                                      : e,
                              ],
                            );
                            ref.invalidate(unreadCountProvider);
                          } catch (_) {}
                        }
                        if (context.mounted) _open(context, ref, x);
                      },
                    );
                  },
                ),
              ),
            ),
    );
  }
}
