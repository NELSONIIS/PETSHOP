import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/listing.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/inputs.dart';
import 'filters_sheet.dart';
import 'listing_views.dart';

/// Search tab. The filter lives in a global provider and results in a provider keyed by it, so
/// opening a listing and returning keeps query, filters and scroll position.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _q = TextEditingController(text: ref.read(searchFilterProvider).q);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _set(PetFilter f) => ref.read(searchFilterProvider.notifier).set(f);

  Future<void> _openFilters() async {
    final cur = ref.read(searchFilterProvider);
    final res = await showPetoraSheet<PetFilter>(context, full: true, builder: (_) => FiltersSheet(initial: cur));
    if (res != null) _set(res);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(searchFilterProvider);
    final state = ref.watch(petsProvider(filter));
    final cats = ref.watch(categoriesProvider).asData?.value ?? const [];
    final notifier = ref.read(petsProvider(filter).notifier);

    final active = <Widget>[
      if (filter.category != null)
        _tag(
          cats.where((c) => c.slug == filter.category).firstOrNull?.name ?? filter.category!,
          () => _set(filter.copyWith(category: null, breed: null)),
        ),
      if (filter.breed != null) _tag('Breed: ${filter.breed}', () => _set(filter.copyWith(breed: null))),
      if (filter.minPrice != null || filter.maxPrice != null)
        _tag('Price', () => _set(filter.copyWith(minPrice: null, maxPrice: null))),
      if (filter.minAge != null || filter.maxAge != null)
        _tag('Age', () => _set(filter.copyWith(minAge: null, maxAge: null))),
      if (filter.gender != null) _tag(filter.gender!, () => _set(filter.copyWith(gender: null))),
      if (filter.city.isNotEmpty) _tag(filter.city, () => _set(filter.copyWith(city: ''))),
      if (filter.radiusKm != null)
        _tag('${filter.radiusKm} km', () => _set(filter.copyWith(radiusKm: null, lat: null, lng: null))),
      if (filter.verifiedSeller) _tag('Verified sellers', () => _set(filter.copyWith(verifiedSeller: false))),
      if (filter.listingType != null)
        _tag(
          filter.listingType == 'adoption' ? 'Adoption' : 'For sale',
          () => _set(filter.copyWith(listingType: null)),
        ),
      if (filter.vaccination != null)
        _tag('Vaccination: ${filter.vaccination}', () => _set(filter.copyWith(vaccination: null))),
      if (filter.availability != null) _tag(filter.availability!, () => _set(filter.copyWith(availability: null))),
      if (filter.listedWithinDays != null)
        _tag('Last ${filter.listedWithinDays}d', () => _set(filter.copyWith(listedWithinDays: null))),
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, PSpace.gutter, 0),
              child: PSearchBar(
                controller: _q,
                onSubmitted: (v) => _set(filter.copyWith(q: v)),
                trailing: IconButton(
                  tooltip: 'Filters',
                  onPressed: _openFilters,
                  icon: Badge(
                    isLabelVisible: filter.activeCount > 0,
                    label: Text('${filter.activeCount}'),
                    child: const Icon(Icons.tune),
                  ),
                ),
              ),
            ),
            ChipRow(
              children: [
                for (final c in cats)
                  PFilterChip(
                    label: c.name,
                    selected: filter.category == c.slug,
                    onTap: () =>
                        _set(filter.copyWith(category: filter.category == c.slug ? null : c.slug, breed: null)),
                  ),
              ],
            ),
            if (active.isNotEmpty)
              ChipRow(
                children: [
                  ...active,
                  TextButton(
                    onPressed: () {
                      _q.clear();
                      ref.read(searchFilterProvider.notifier).reset();
                    },
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PSpace.gutter),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      state.loading && state.items.isEmpty
                          ? 'Searching...'
                          : '${state.total} ${state.total == 1 ? 'pet' : 'pets'}',
                      style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final loc = ref.read(locationProvider);
                      final k = await pickOne(
                        context,
                        title: 'Sort by',
                        options: {
                          for (final e in sortOptions.entries)
                            if (e.key != 'nearest' || loc.hasCoords) e.key: e.value,
                        },
                        selected: filter.sort,
                      );
                      if (k != null) {
                        _set(
                          filter.copyWith(
                            sort: k,
                            lat: k == 'nearest' ? loc.lat : filter.lat,
                            lng: k == 'nearest' ? loc.lng : filter.lng,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.swap_vert, size: 18),
                    label: Text(sortOptions[filter.sort] ?? 'Sort'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PagedListingGrid(
                state: state,
                onRefresh: notifier.refresh,
                onLoadMore: notifier.loadMore,
                emptyTitle: 'No pets match your search',
                emptyMessage: 'Try removing a filter or searching a nearby city.',
                emptyIcon: Icons.search_off,
                emptyActionLabel: filter.activeCount > 0 || filter.q.isNotEmpty ? 'Clear filters' : null,
                emptyAction: () {
                  _q.clear();
                  ref.read(searchFilterProvider.notifier).reset();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String label, VoidCallback onRemove) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: InputChip(
      label: Text(label),
      onDeleted: onRemove,
      deleteButtonTooltipMessage: 'Remove filter $label',
      visualDensity: VisualDensity.compact,
    ),
  );
}
