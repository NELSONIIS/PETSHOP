import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../models/listing.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/gallery.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';

const sellerTabs = {
  null: 'All',
  'approved': 'Active',
  'draft': 'Drafts',
  'pending': 'Pending',
  'rejected': 'Rejected',
  'sold': 'Sold / unavailable',
  'expired': 'Expired',
  'suspended': 'Suspended',
};

/// Listings tab: overview + one list per status.
class SellerListingsScreen extends ConsumerStatefulWidget {
  const SellerListingsScreen({super.key, this.initialTab});
  final String? initialTab;
  @override
  ConsumerState<SellerListingsScreen> createState() => _SellerListingsScreenState();
}

class _SellerListingsScreenState extends ConsumerState<SellerListingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tc = TabController(
    length: sellerTabs.length,
    vsync: this,
    initialIndex: _indexOf(widget.initialTab),
  );

  int _indexOf(String? k) {
    final i = sellerTabs.keys.toList().indexOf(k);
    return i < 0 ? 0 : i;
  }

  @override
  void didUpdateWidget(covariant SellerListingsScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialTab != old.initialTab) {
      _tc.animateTo(_indexOf(widget.initialTab));
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My listings'),
        bottom: TabBar(
          controller: _tc,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in sellerTabs.values) Tab(text: t)],
        ),
      ),
      body: TabBarView(
        controller: _tc,
        children: [for (final k in sellerTabs.keys) _StatusList(status: k)],
      ),
    );
  }
}

class _StatusList extends ConsumerWidget {
  const _StatusList({required this.status});
  final String? status;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sellerListingsProvider(status));
    final n = ref.read(sellerListingsProvider(status).notifier);
    if (s.loading && s.items.isEmpty) return const ListSkeleton(height: 96);
    if (s.error != null && s.items.isEmpty) {
      return ErrorState(error: s.error!, onRetry: n.refresh);
    }
    if (s.items.isEmpty) {
      return EmptyState(
        icon: Icons.pets,
        title: status == null ? 'No listings yet' : 'No ${sellerTabs[status]!.toLowerCase()} listings',
        message: status == null ? 'Create your first pet listing - it only takes a few minutes.' : null,
        actionLabel: status == null ? 'Add a pet' : null,
        onAction: () => context.push('/sell/listing/new'),
      );
    }
    return RefreshIndicator(
      onRefresh: n.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (x) {
          if (x.metrics.extentAfter < 400 && s.loadMoreError == null) n.loadMore();
          return false;
        },
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(PSpace.gutter, PSpace.gutter, PSpace.gutter, 96),
          itemCount: s.items.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) => i == s.items.length
              ? LoadMoreFooter(
                  loading: s.loadingMore,
                  hasMore: s.hasMore,
                  onLoadMore: n.loadMore,
                  error: s.loadMoreError,
                )
              : SellerListingTile(listing: s.items[i]),
        ),
      ),
    );
  }
}

class SellerListingTile extends StatelessWidget {
  const SellerListingTile({super.key, required this.listing});
  final Listing listing;
  @override
  Widget build(BuildContext context) {
    final l = listing;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/sell/listing/${l.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 84, height: 84, child: PNetImage(l.cover?.small, radius: 10, iconSlug: l.category?.slug)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                    PriceLabel(minor: l.priceMinor, currency: l.currency, adoption: l.isAdoption, size: 14),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        StatusBadge.status(l.status.isEmpty ? 'draft' : l.status),
                        if (l.availability != 'available') StatusBadge.status(l.availability),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${l.viewsCount} views · ${l.favouritesCount} saves · ${l.enquiriesCount} enquiries',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Owner's detail view: status, moderation feedback, stats and actions.
class SellerListingDetailScreen extends ConsumerStatefulWidget {
  const SellerListingDetailScreen({super.key, required this.id});
  final String id;
  @override
  ConsumerState<SellerListingDetailScreen> createState() => _SellerListingDetailScreenState();
}

class _SellerListingDetailScreenState extends ConsumerState<SellerListingDetailScreen> {
  bool _busy = false;

  void _refreshAll() {
    ref.invalidate(sellerListingProvider(widget.id));
    ref.invalidate(sellerListingsProvider);
    ref.invalidate(sellerDashboardProvider);
  }

  Future<void> _run(Future<void> Function() f, String ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
      _refreshAll();
      if (mounted) showSnack(context, ok);
    } on AppException catch (e) {
      if (mounted) {
        if (e.kind == ErrorKind.subscriptionRequired || e.kind == ErrorKind.membershipRequired) {
          _needPlan(e);
        } else if (e.kind == ErrorKind.verificationRequired &&
            e.fieldErrors.isEmpty &&
            e.message.toLowerCase().contains('seller')) {
          showSnack(context, e.userMessage, error: true);
        } else if (e.fieldErrors.isNotEmpty) {
          showSnack(context, e.fieldErrors.values.join('\n'), error: true);
        } else {
          handleActionError(context, e);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _needPlan(AppException e) => showPetoraSheet<void>(
    context,
    builder: (ctx) => SheetScaffold(
      title: 'An active plan is required',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.message.isNotEmpty ? e.message : 'Subscribe to a seller plan to publish listings.',
            style: ctx.tt.bodyMedium,
          ),
          const SizedBox(height: 16),
          PButton(
            'View seller plans',
            onPressed: () {
              Navigator.pop(ctx);
              context.push('/plans');
            },
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = ref.watch(sellerListingProvider(widget.id));
    return v.when(
      loading: () => Scaffold(appBar: petoraAppBar(context, 'Listing'), body: const ListSkeleton(height: 120)),
      error: (e, _) => Scaffold(
        appBar: petoraAppBar(context, 'Listing'),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(sellerListingProvider(widget.id))),
      ),
      data: (l) {
        final canEdit = l.status == 'draft' || l.status == 'rejected' || l.status == 'approved';
        final canSubmit = l.status == 'draft' || l.status == 'rejected';
        return Scaffold(
          appBar: AppBar(
            title: const Text('Listing'),
            actions: [
              if (canEdit)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push('/sell/listing/${l.id}/edit'),
                ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (a) async {
                  if (a == 'delete') {
                    final ok = await confirmDialog(
                      context,
                      title: 'Delete listing?',
                      message: 'This removes "${l.title}" from PETORA. This cannot be undone.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (!ok) return;
                    await _run(() => ref.read(sellerRepoProvider).deleteListing(l.id), 'Listing deleted');
                    if (!context.mounted) return;
                    context.pop();
                  } else if (a == 'public') {
                    context.push('/pet/${l.slug.isNotEmpty ? l.slug : l.id}');
                  }
                },
                itemBuilder: (_) => [
                  if (l.status == 'approved') const PopupMenuItem(value: 'public', child: Text('View public page')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.zero,
            children: [
              ImageGallery(images: l.images, iconSlug: l.category?.slug),
              Padding(
                padding: const EdgeInsets.all(PSpace.gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l.title, style: context.tt.titleLarge)),
                        StatusBadge.status(l.status.isEmpty ? 'draft' : l.status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    PriceLabel(minor: l.priceMinor, currency: l.currency, adoption: l.isAdoption, size: 20),
                    gap12,
                    if (l.status == 'rejected') ...[
                      InfoBanner(
                        'Not approved: ${l.rejectionReason ?? 'see moderator notes below'}. Edit the listing and resubmit.',
                        tone: BannerTone.danger,
                      ),
                      gap12,
                    ],
                    if (l.status == 'pending') ...[
                      const InfoBanner(
                        'Under review. Most listings are reviewed within 1 working day.',
                        tone: BannerTone.warning,
                        icon: Icons.hourglass_top,
                      ),
                      gap12,
                    ],
                    if (l.status == 'suspended') ...[
                      InfoBanner(
                        'Suspended by moderators${l.rejectionReason != null ? ': ${l.rejectionReason}' : ''}. Open a dispute from Support if you disagree.',
                        tone: BannerTone.danger,
                      ),
                      gap12,
                    ],
                    if (l.status == 'expired') ...[
                      InfoBanner(
                        l.expiredReason == 'subscription'
                            ? 'Hidden because your subscription ended. Renew to restore it.'
                            : 'This listing expired. Edit and resubmit, or renew to restore.',
                        tone: BannerTone.warning,
                      ),
                      gap12,
                    ],
                    if (canSubmit && l.missingForSubmission.isNotEmpty) ...[
                      InfoBanner(
                        'Before you can submit:\n• ${l.missingForSubmission.join('\n• ')}',
                        tone: BannerTone.warning,
                        icon: Icons.checklist,
                      ),
                      gap12,
                    ],
                    if (canSubmit)
                      PButton(
                        'Submit for moderation',
                        icon: Icons.send,
                        loading: _busy,
                        onPressed: () => _run(
                          () async => ref.read(sellerRepoProvider).submitListing(l.id),
                          'Submitted for moderation',
                        ),
                      ),
                    if (l.status == 'approved') ...[
                      Text('Availability', style: context.tt.titleSmall),
                      gap8,
                      SegmentRow2(
                        value: l.availability,
                        options: const {
                          'available': 'Available',
                          'reserved': 'Reserved',
                          'sold': 'Sold',
                          'unavailable': 'Unavailable',
                        },
                        onChanged: (v) => _run(
                          () async => ref.read(sellerRepoProvider).setAvailability(l.id, v),
                          'Availability updated',
                        ),
                      ),
                    ],
                    gap16,
                    Row(
                      children: [
                        Expanded(child: _Metric('Views', l.viewsCount)),
                        Expanded(child: _Metric('Saves', l.favouritesCount)),
                        Expanded(child: _Metric('Enquiries', l.enquiriesCount)),
                      ],
                    ),
                    gap8,
                    PButton(
                      'View analytics',
                      icon: Icons.insights_outlined,
                      kind: PButtonKind.outline,
                      onPressed: () => context.push('/sell/listing/${l.id}/analytics'),
                    ),
                    if (l.moderation.isNotEmpty) ...[
                      gap24,
                      Text('Moderation history', style: context.tt.titleSmall),
                      for (final m in l.moderation)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: const Icon(Icons.history, size: 18),
                          title: Text(titleCase(m.action)),
                          subtitle: Text('${formatDateTime(m.createdAt)}${m.reason != null ? '\n${m.reason}' : ''}'),
                        ),
                    ],
                    gap24,
                    Text('Details', style: context.tt.titleSmall),
                    InfoRow('Category', l.category?.name ?? '-'),
                    InfoRow('Breed', l.breed?.name ?? '-'),
                    InfoRow('Age', formatAge(l.ageMonths)),
                    InfoRow('Gender', genderLabel(l.gender)),
                    InfoRow('Location', l.location.isEmpty ? '-' : l.location),
                    InfoRow('Vaccination', vaccinationLabel(l.vaccinationStatus)),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$value', style: context.tt.headlineMedium),
      Text(label, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
    ],
  );
}

class SegmentRow2 extends StatelessWidget {
  const SegmentRow2({super.key, required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final e in options.entries)
        ChoiceChip(
          label: Text(e.value),
          selected: e.key == value,
          onSelected: (_) => e.key == value ? null : onChanged(e.key),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
    ],
  );
}

/// Listing analytics (requires a plan with the analytics entitlement).
class ListingAnalyticsScreen extends ConsumerWidget {
  const ListingAnalyticsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v = ref.watch(listingAnalyticsProvider(id));
    return Scaffold(
      appBar: petoraAppBar(context, 'Analytics'),
      body: v.when(
        loading: () => const ListSkeleton(height: 120),
        error: (e, _) =>
            e is AppException && (e.kind == ErrorKind.subscriptionRequired || e.kind == ErrorKind.membershipRequired)
            ? EmptyState(
                icon: Icons.insights_outlined,
                title: 'Analytics are not in your plan',
                message: 'Upgrade to a plan that includes listing analytics.',
                actionLabel: 'See plans',
                onAction: () => context.push('/plans'),
              )
            : ErrorState(error: e, onRetry: () => ref.invalidate(listingAnalyticsProvider(id))),
        data: (a) {
          final max = a.series.fold<int>(1, (m, e) => e.value > m ? e.value : m);
          return ListView(
            padding: const EdgeInsets.all(PSpace.gutter),
            children: [
              Row(
                children: [
                  Expanded(child: _Stat2('Views', a.views, Icons.visibility_outlined)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat2('Saves', a.favourites, Icons.favorite_border)),
                  const SizedBox(width: 10),
                  Expanded(child: _Stat2('Enquiries', a.enquiries, Icons.chat_bubble_outline)),
                ],
              ),
              gap24,
              Text('Views - last ${a.series.length} days', style: context.tt.titleSmall),
              gap12,
              if (a.series.isEmpty)
                const Text('No views recorded yet.')
              else
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final e in a.series)
                        Expanded(
                          child: Tooltip(
                            message: '${formatDate(e.key)}: ${e.value}',
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              height: 4 + 130 * (e.value / max),
                              decoration: BoxDecoration(
                                color: context.cs.primary,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat2 extends StatelessWidget {
  const _Stat2(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.cs.primary),
          const SizedBox(height: 6),
          Text('$value', style: context.tt.headlineMedium),
          Text(label, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
        ],
      ),
    ),
  );
}
