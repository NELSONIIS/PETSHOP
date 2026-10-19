import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/billing.dart';
import '../../models/listing.dart';
import '../../state/auth.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/badges.dart';
import '../../ui/widgets/brand.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/net_image.dart';
import '../../ui/widgets/states.dart';
import '../search/listing_views.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(categoriesProvider);
    ref.invalidate(homeFeaturedProvider);
    ref.invalidate(homeRecentProvider);
    ref.invalidate(homeNearbyProvider);
    ref.invalidate(verifiedSellersProvider);
    ref.invalidate(recentlyViewedProvider);
    await ref.read(homeRecentProvider.future).catchError((_) => <Listing>[]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final loc = ref.watch(locationProvider);
    final unread = ref.watch(unreadCountProvider).asData?.value ?? 0;
    final cats = ref.watch(categoriesProvider);
    final featured = ref.watch(homeFeaturedProvider);
    final recent = ref.watch(homeRecentProvider);
    final nearby = ref.watch(homeNearbyProvider);
    final sellers = ref.watch(verifiedSellersProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, 4, 0),
                  child: Row(
                    children: [
                      const PetoraLogo(size: 32),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => context.push('/setup/location'),
                            icon: const Icon(Icons.place_outlined, size: PIcon.md),
                            label: Text(
                              loc.city.isEmpty ? 'Set location' : loc.city,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Notifications',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: unread > 0,
                          label: Text('$unread'),
                          child: const Icon(Icons.notifications_none),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(PSpace.gutter, 8, PSpace.gutter, 4),
                  child: PSearchBar(onTap: () => context.go('/search')),
                ),
              ),
              SliverToBoxAdapter(
                child: cats.when(
                  loading: () => const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 84, radius: 14)),
                  error: (e, _) => const SizedBox.shrink(),
                  data: (list) => SizedBox(
                    height: 96 + 20 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: list.length,
                      itemBuilder: (_, i) =>
                          CategoryTile(category: list[i], onTap: () => context.push('/category/${list[i].slug}')),
                    ),
                  ),
                ),
              ),
              if (!(auth.user?.isSeller ?? false)) SliverToBoxAdapter(child: _MembershipCard(authed: auth.isAuthed)),
              ..._section(context, 'Featured pets', featured, onMore: () => context.push('/pets/featured')),
              ..._section(context, 'Recently added', recent, onMore: () => context.push('/pets/recent')),
              SliverToBoxAdapter(
                child: loc.isSet
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(PSpace.gutter, 16, PSpace.gutter, 0),
                        child: InfoBanner(
                          'Set your location to see pets near you.',
                          icon: Icons.near_me_outlined,
                          action: TextButton(
                            onPressed: () => context.push('/setup/location'),
                            child: const Text('Set'),
                          ),
                        ),
                      ),
              ),
              if (loc.isSet)
                ..._section(
                  context,
                  'Near ${loc.city.isEmpty ? 'you' : loc.city}',
                  nearby,
                  onMore: () => context.push('/pets/nearby'),
                ),
              SliverToBoxAdapter(
                child: SectionHeader(
                  'Verified sellers',
                  actionLabel: 'See all',
                  onAction: () => context.push('/sellers'),
                ),
              ),
              SliverToBoxAdapter(
                child: sellers.when(
                  loading: () => const Padding(padding: EdgeInsets.all(16), child: Skeleton(height: 86, radius: 14)),
                  error: (e, _) =>
                      ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(verifiedSellersProvider)),
                  data: (list) => list.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
                          child: Text(
                            'Verified sellers will appear here.',
                            style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                          ),
                        )
                      : SizedBox(
                          height: 96,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
                            itemCount: list.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 10),
                            itemBuilder: (_, i) => _SellerChip(seller: list[i]),
                          ),
                        ),
                ),
              ),
              if (auth.isAuthed) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    'Recently viewed',
                    actionLabel: 'See all',
                    onAction: () => context.push('/pets/recently-viewed'),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ref
                      .watch(recentlyViewedProvider)
                      .when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                        data: (l) => l.isEmpty ? const SizedBox.shrink() : ListingStrip(items: l.take(8).toList()),
                      ),
                ),
              ],
              if (!auth.isAuthed)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(PSpace.gutter),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(PSpace.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Selling or rehoming pets?', style: context.tt.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              'Reach local buyers with a verified seller profile.',
                              style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
                            ),
                            const SizedBox(height: 12),
                            PButton(
                              'Register as a seller',
                              kind: PButtonKind.outline,
                              onPressed: () => context.push('/register?role=seller'),
                              expand: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _section(
    BuildContext context,
    String title,
    AsyncValue<List<Listing>> v, {
    required VoidCallback onMore,
  }) => [
    SliverToBoxAdapter(
      child: SectionHeader(title, actionLabel: 'See all', onAction: onMore),
    ),
    SliverToBoxAdapter(
      child: v.when(
        loading: () => SizedBox(
          height: 240,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              SizedBox(width: 176, child: ListingCardSkeleton()),
              SizedBox(width: 12),
              SizedBox(width: 176, child: ListingCardSkeleton()),
              SizedBox(width: 12),
              SizedBox(width: 176, child: ListingCardSkeleton()),
            ],
          ),
        ),
        error: (e, _) => Consumer(
          builder: (c, ref, _) => ErrorState(error: e, compact: true, onRetry: () => _refresh(ref)),
        ),
        data: (l) => l.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
                child: Text('Nothing here yet.', style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted)),
              )
            : ListingStrip(items: l),
      ),
    ),
  ];
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.authed});
  final bool authed;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(PSpace.gutter, 8, PSpace.gutter, 0),
    child: Material(
      color: context.cs.primary,
      borderRadius: PRadius.cardR,
      child: InkWell(
        borderRadius: PRadius.cardR,
        onTap: () => context.push('/plans'),
        child: Padding(
          padding: const EdgeInsets.all(PSpace.lg),
          child: Row(
            children: [
              const Icon(Icons.lock_open_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unlock seller contacts', style: context.tt.titleSmall?.copyWith(color: Colors.white)),
                    Text('See membership plans', style: context.tt.bodySmall?.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SellerChip extends StatelessWidget {
  const _SellerChip({required this.seller});
  final SellerBadge seller;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/s/${seller.slug}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  PAvatar(url: seller.logoUrl, name: seller.displayName, size: 32),
                  const SizedBox(width: 8),
                  if (seller.verified) const VerifiedBadge(compact: true),
                ],
              ),
              const SizedBox(height: 6),
              Text(seller.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
              Text(
                seller.city,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Used by Plan summaries elsewhere.
String planSummary(Plan p) => '${p.name} · ${p.periodLabel}';

/// Category icon placeholder re-export so other files avoid importing net_image just for this.
IconData iconForCategory(String slug) => categoryIcon(slug);
