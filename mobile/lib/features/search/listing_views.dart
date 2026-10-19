import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/listing.dart';
import '../../state/data.dart';
import '../../state/paged.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/states.dart';
import '../common.dart';

String petRoute(Listing l) => '/pet/${l.slug.isNotEmpty ? l.slug : l.id}';

/// ListingCard wired to routing and optimistic favourites.
class ListingTile extends ConsumerWidget {
  const ListingTile({super.key, required this.listing, this.showStatus = false, this.onTap});
  final Listing listing;
  final bool showStatus;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fav = ref.watch(favouriteOverridesProvider.select((m) => m[listing.id] ?? listing.isFavourite));
    return ListingCard(
      listing: listing.copyWith(isFavourite: fav),
      showStatus: showStatus,
      onTap: onTap ?? () => context.push(petRoute(listing)),
      onFavourite: () async {
        if (!await ensureSignedIn(context, ref, reason: 'Sign in to save pets')) {
          return;
        }
        final ok = await ref.read(favouriteOverridesProvider.notifier).toggle(listing);
        if (!ok && context.mounted) {
          showSnack(context, 'Could not update favourites. Please try again.', error: true);
        }
      },
    );
  }
}

/// Paginated grid with pull-to-refresh, skeletons, error/empty states and automatic load-more.
class PagedListingGrid extends StatelessWidget {
  const PagedListingGrid({
    super.key,
    required this.state,
    required this.onRefresh,
    required this.onLoadMore,
    this.header,
    this.emptyTitle = 'No pets found',
    this.emptyMessage = 'Try changing your filters or check back soon.',
    this.emptyIcon = Icons.pets,
    this.emptyAction,
    this.emptyActionLabel,
  });
  final PagedState<Listing> state;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final Widget? header;
  final String emptyTitle, emptyMessage;
  final IconData emptyIcon;
  final VoidCallback? emptyAction;
  final String? emptyActionLabel;

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (state.loading && state.items.isEmpty) {
      body = const GridSkeleton();
    } else if (state.error != null && state.items.isEmpty) {
      body = ErrorState(error: state.error!, onRetry: onRefresh);
    } else if (state.items.isEmpty) {
      body = EmptyState(
        icon: emptyIcon,
        title: emptyTitle,
        message: emptyMessage,
        actionLabel: emptyActionLabel,
        onAction: emptyAction,
      );
    } else {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 500 && state.loadMoreError == null) onLoadMore();
            return false;
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (header != null) SliverToBoxAdapter(child: header),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(PSpace.gutter, 8, PSpace.gutter, 0),
                sliver: SliverGrid.builder(
                  gridDelegate: listingGridDelegate(context),
                  itemCount: state.items.length,
                  itemBuilder: (_, i) => ListingTile(listing: state.items[i], key: ValueKey(state.items[i].id)),
                ),
              ),
              SliverToBoxAdapter(
                child: LoadMoreFooter(
                  loading: state.loadingMore,
                  hasMore: state.hasMore,
                  onLoadMore: onLoadMore,
                  error: state.loadMoreError,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        ?header,
        Expanded(child: body),
      ],
    );
  }
}

/// Horizontal strip of listing cards for the home screen.
class ListingStrip extends StatelessWidget {
  const ListingStrip({super.key, required this.items});
  final List<Listing> items;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: listingCardHeight(176, textScaleOf(context)),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) => SizedBox(width: 176, child: ListingTile(listing: items[i])),
      ),
    );
  }
}
