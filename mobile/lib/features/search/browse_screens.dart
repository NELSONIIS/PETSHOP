import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/listing.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/dialogs.dart';
import '../../state/providers.dart';
import '../common.dart';
import 'listing_views.dart';

/// Category page with breed browsing chips.
class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  String? _breed;

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider);
    final cat = cats.asData?.value.where((c) => c.slug == widget.slug).firstOrNull;
    final filter = PetFilter(category: widget.slug, breed: _breed);
    final state = ref.watch(petsProvider(filter));
    final n = ref.read(petsProvider(filter).notifier);
    return Scaffold(
      appBar: petoraAppBar(
        context,
        cat?.name ?? 'Category',
        actions: [
          IconButton(
            tooltip: 'Search with filters',
            icon: const Icon(Icons.tune),
            onPressed: () {
              ref.read(searchFilterProvider.notifier).set(PetFilter(category: widget.slug, breed: _breed));
              context.go('/search');
            },
          ),
        ],
      ),
      body: PagedListingGrid(
        state: state,
        onRefresh: n.refresh,
        onLoadMore: n.loadMore,
        emptyTitle: 'No pets listed yet',
        emptyMessage: 'New listings in ${cat?.name ?? 'this category'} appear here as sellers publish them.',
        header: (cat == null || cat.breeds.isEmpty)
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 4),
                child: ChipRow(
                  children: [
                    PFilterChip(
                      label: 'All breeds',
                      selected: _breed == null,
                      onTap: () => setState(() => _breed = null),
                    ),
                    for (final b in cat.breeds)
                      PFilterChip(
                        label: b.name,
                        selected: _breed == b.slug,
                        onTap: () => setState(() => _breed = b.slug),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Featured / recent / nearby / recently-viewed full lists.
class ListingListScreen extends ConsumerWidget {
  const ListingListScreen({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kind == 'recently-viewed') {
      final v = ref.watch(recentlyViewedProvider);
      return Scaffold(
        appBar: petoraAppBar(context, 'Recently viewed'),
        body: AsyncBody<List<Listing>>(
          value: v,
          onRetry: () => ref.invalidate(recentlyViewedProvider),
          loading: const GridSkeleton(),
          data: (l) => l.isEmpty
              ? const EmptyState(
                  icon: Icons.history,
                  title: 'Nothing viewed yet',
                  message: 'Pets you open will show up here.',
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(PSpace.gutter),
                  gridDelegate: listingGridDelegate(context),
                  itemCount: l.length,
                  itemBuilder: (_, i) => ListingTile(listing: l[i]),
                ),
        ),
      );
    }
    final loc = ref.watch(locationProvider);
    final (title, filter) = switch (kind) {
      'featured' => ('Featured pets', const PetFilter(featured: true)),
      'nearby' => (
        'Nearby pets',
        loc.hasCoords
            ? PetFilter(lat: loc.lat, lng: loc.lng, radiusKm: loc.radiusKm, sort: 'nearest')
            : PetFilter(city: loc.city),
      ),
      _ => ('Recently added', const PetFilter()),
    };
    final state = ref.watch(petsProvider(filter));
    final n = ref.read(petsProvider(filter).notifier);
    return Scaffold(
      appBar: petoraAppBar(context, title),
      body: PagedListingGrid(state: state, onRefresh: n.refresh, onLoadMore: n.loadMore),
    );
  }
}

class VerifiedSellersScreen extends ConsumerWidget {
  const VerifiedSellersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(sellersProvider);
    final n = ref.read(sellersProvider.notifier);
    return Scaffold(
      appBar: petoraAppBar(context, 'Verified sellers'),
      body: s.loading && s.items.isEmpty
          ? const ListSkeleton()
          : s.error != null && s.items.isEmpty
          ? ErrorState(error: s.error!, onRetry: n.refresh)
          : s.items.isEmpty
          ? const EmptyState(
              icon: Icons.verified_outlined,
              title: 'No verified sellers yet',
              message: 'Sellers appear here after our team verifies their documents.',
            )
          : RefreshIndicator(
              onRefresh: n.refresh,
              child: ListView.separated(
                padding: const EdgeInsets.all(PSpace.gutter),
                itemCount: s.items.length + 1,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                  return Card(
                    child: ListTile(
                      onTap: () => context.push('/s/${x.slug}'),
                      leading: PAvatar(url: x.logoUrl, name: x.displayName),
                      title: Text(x.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          x.location,
                          '${x.activeListings} listings',
                        ].where((e) => e.isNotEmpty && !e.startsWith('0')).join(' · '),
                      ),
                      trailing: x.verified ? const VerifiedBadge(compact: true) : null,
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Public seller profile with their listings.
class SellerPublicScreen extends ConsumerWidget {
  const SellerPublicScreen({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerPublicProvider(slug));
    final pets = ref.watch(sellerPetsProvider(slug));
    final n = ref.read(sellerPetsProvider(slug).notifier);
    return Scaffold(
      appBar: petoraAppBar(
        context,
        'Seller',
        actions: [
          IconButton(
            tooltip: 'Report seller',
            icon: const Icon(Icons.flag_outlined),
            onPressed: () async {
              if (!await ensureSignedIn(context, ref, reason: 'Sign in to report')) {
                return;
              }
              final id = seller.asData?.value.id;
              if (id != null && context.mounted) {
                showReportSheet(context, ref, targetType: 'seller', targetId: id);
              }
            },
          ),
        ],
      ),
      body: seller.when(
        loading: () => const ListSkeleton(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(sellerPublicProvider(slug))),
        data: (s) => PagedListingGrid(
          state: pets,
          onRefresh: () async {
            ref.invalidate(sellerPublicProvider(slug));
            await n.refresh();
          },
          onLoadMore: n.loadMore,
          emptyTitle: 'No active listings',
          emptyMessage: 'This seller has no pets listed right now.',
          header: Padding(
            padding: const EdgeInsets.all(PSpace.gutter),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(PSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PAvatar(url: s.logoUrl, name: s.displayName, size: 56),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.displayName, style: context.tt.titleMedium),
                              if (s.location.isNotEmpty)
                                Text(s.location, style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  if (s.verified)
                                    const VerifiedBadge()
                                  else
                                    const StatusBadge('Not verified', tone: Tone.neutral),
                                  StatusBadge(
                                    s.sellerType == 'business' ? 'Business' : 'Individual',
                                    tone: Tone.neutral,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (s.bio.isNotEmpty) ...[const SizedBox(height: 12), Text(s.bio, style: context.tt.bodyMedium)],
                    const SizedBox(height: 10),
                    Text(
                      'Member since ${s.memberSince?.year ?? '-'} · ${s.activeListings} active listings',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Report a listing / seller / enquiry.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required String targetId,
}) {
  const reasons = {
    'spam': 'Spam',
    'scam': 'Scam or fraud',
    'prohibited': 'Prohibited animal or listing',
    'misleading': 'Misleading information',
    'animal_welfare': 'Animal welfare concern',
    'abuse': 'Abusive behaviour',
    'other': 'Something else',
  };
  String reason = 'misleading';
  final details = TextEditingController();
  return showPetoraSheet<void>(
    context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        bool busy = false;
        return StatefulBuilder(
          builder: (ctx, setB) {
            return SheetScaffold(
              title: 'Report',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tell us what is wrong. Our team reviews every report.',
                    style: ctx.tt.bodyMedium?.copyWith(color: ctx.pc.textMuted),
                  ),
                  const SizedBox(height: 12),
                  RadioGroup<String>(
                    groupValue: reason,
                    onChanged: (v) => setS(() => reason = v ?? reason),
                    child: Column(
                      children: [
                        for (final e in reasons.entries)
                          RadioListTile<String>(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: Text(e.value),
                            value: e.key,
                          ),
                      ],
                    ),
                  ),
                  TextField(
                    controller: details,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(hintText: 'Details (optional)'),
                  ),
                  const SizedBox(height: 8),
                  PButton(
                    'Submit report',
                    loading: busy,
                    onPressed: () async {
                      setB(() => busy = true);
                      try {
                        await ref
                            .read(buyerRepoProvider)
                            .report(
                              targetType: targetType,
                              targetId: targetId,
                              reason: reason,
                              details: details.text.trim(),
                            );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          showSnack(context, 'Thanks - we will review this report.');
                        }
                      } catch (e) {
                        setB(() => busy = false);
                        if (ctx.mounted) handleActionError(ctx, e);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    ),
  );
}
