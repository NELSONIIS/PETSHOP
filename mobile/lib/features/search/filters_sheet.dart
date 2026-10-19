import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../models/listing.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/scaffolds.dart';

const sortOptions = {
  'newest': 'Newest',
  'price_asc': 'Price: low to high',
  'price_desc': 'Price: high to low',
  'nearest': 'Nearest',
  'relevance': 'Relevance',
};

/// Advanced filter sheet. Returns the new [PetFilter] on Apply (or null when dismissed).
class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial});
  final PetFilter initial;
  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late PetFilter _f = widget.initial;
  late final _minPrice = TextEditingController(text: _f.minPrice == null ? '' : '${_f.minPrice! ~/ 100}');
  late final _maxPrice = TextEditingController(text: _f.maxPrice == null ? '' : '${_f.maxPrice! ~/ 100}');
  late final _city = TextEditingController(text: _f.city);

  static const _ages = {
    'any': 'Any age',
    '0-3': 'Up to 3 months',
    '3-12': '3-12 months',
    '12-36': '1-3 years',
    '36+': '3+ years',
  };
  static const _listed = {0: 'Any time', 1: 'Last 24 hours', 7: 'Last 7 days', 30: 'Last 30 days'};

  @override
  void dispose() {
    _minPrice.dispose();
    _maxPrice.dispose();
    _city.dispose();
    super.dispose();
  }

  String get _ageKey {
    final a = _f.minAge, b = _f.maxAge;
    if (a == null && b == null) return 'any';
    if (a == null && b == 3) return '0-3';
    if (a == 3 && b == 12) return '3-12';
    if (a == 12 && b == 36) return '12-36';
    if (a == 36 && b == null) return '36+';
    return 'any';
  }

  void _setAge(String k) {
    setState(() {
      switch (k) {
        case '0-3':
          _f = _f.copyWith(minAge: null, maxAge: 3);
        case '3-12':
          _f = _f.copyWith(minAge: 3, maxAge: 12);
        case '12-36':
          _f = _f.copyWith(minAge: 12, maxAge: 36);
        case '36+':
          _f = _f.copyWith(minAge: 36, maxAge: null);
        default:
          _f = _f.copyWith(minAge: null, maxAge: null);
      }
    });
  }

  void _apply() {
    final min = parseMoneyToMinor(_minPrice.text);
    final max = parseMoneyToMinor(_maxPrice.text);
    Navigator.pop(context, _f.copyWith(minPrice: min, maxPrice: max, city: _city.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).asData?.value ?? const [];
    final cat = cats.where((c) => c.slug == _f.category).firstOrNull;
    final loc = ref.watch(locationProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(PSpace.gutter, 0, 8, 4),
            child: Row(
              children: [
                Expanded(child: Text('Filters', style: context.tt.titleLarge)),
                TextButton(
                  onPressed: () => setState(() {
                    _f = const PetFilter().copyWith(q: widget.initial.q);
                    _minPrice.clear();
                    _maxPrice.clear();
                    _city.clear();
                  }),
                  child: const Text('Reset'),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(PSpace.gutter, 0, PSpace.gutter, PSpace.lg),
              children: [
                _label('Category'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    PFilterChip(
                      label: 'All',
                      selected: _f.category == null,
                      onTap: () => setState(() => _f = _f.copyWith(category: null, breed: null)),
                    ),
                    for (final c in cats)
                      PFilterChip(
                        label: c.name,
                        selected: _f.category == c.slug,
                        onTap: () => setState(() => _f = _f.copyWith(category: c.slug, breed: null)),
                      ),
                  ],
                ),
                if (cat != null && cat.breeds.isNotEmpty) ...[
                  _label('Breed'),
                  PDropdown<String?>(
                    label: '',
                    value: _f.breed,
                    hint: 'Any breed',
                    items: {null: 'Any breed', for (final b in cat.breeds) b.slug: b.name},
                    onChanged: (v) => setState(() => _f = _f.copyWith(breed: v)),
                  ),
                ],
                _label('Listing type'),
                SegmentRow<String?>(
                  value: _f.listingType,
                  options: const {null: 'Any', 'sale': 'For sale', 'adoption': 'Adoption'},
                  onChanged: (v) => setState(() => _f = _f.copyWith(listingType: v)),
                ),
                if (_f.listingType != 'adoption') ...[
                  _label('Price (₹)'),
                  Row(
                    children: [
                      Expanded(
                        child: PTextField(
                          label: 'Min',
                          controller: _minPrice,
                          keyboard: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PTextField(
                          label: 'Max',
                          controller: _maxPrice,
                          keyboard: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                ],
                _label('Age'),
                SegmentRow<String>(value: _ageKey, options: _ages, onChanged: _setAge),
                _label('Gender'),
                SegmentRow<String?>(
                  value: _f.gender,
                  options: const {null: 'Any', 'male': 'Male', 'female': 'Female'},
                  onChanged: (v) => setState(() => _f = _f.copyWith(gender: v)),
                ),
                _label('Location'),
                PTextField(label: 'City', controller: _city, hint: 'e.g. Pune'),
                if (loc.hasCoords) ...[
                  gap12,
                  Text(
                    _f.radiusKm == null ? 'Within radius: off' : 'Within ${_f.radiusKm} km of your location',
                    style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted),
                  ),
                  Slider(
                    value: (_f.radiusKm ?? 0).toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 50,
                    label: _f.radiusKm == null ? 'Off' : '${_f.radiusKm} km',
                    onChanged: (v) => setState(
                      () => _f = v < 5
                          ? _f.copyWith(radiusKm: null, lat: null, lng: null)
                          : _f.copyWith(radiusKm: v.round(), lat: loc.lat, lng: loc.lng, sort: 'nearest'),
                    ),
                  ),
                ],
                _label('Seller'),
                SegmentRow<String?>(
                  value: _f.sellerType,
                  options: const {null: 'Any', 'individual': 'Individual', 'business': 'Business'},
                  onChanged: (v) => setState(() => _f = _f.copyWith(sellerType: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Verified sellers only'),
                  value: _f.verifiedSeller,
                  onChanged: (v) => setState(() => _f = _f.copyWith(verifiedSeller: v)),
                ),
                _label('Vaccination (as disclosed by seller)'),
                SegmentRow<String?>(
                  value: _f.vaccination,
                  options: const {null: 'Any', 'complete': 'Complete', 'partial': 'Partial', 'none': 'None'},
                  onChanged: (v) => setState(() => _f = _f.copyWith(vaccination: v)),
                ),
                _label('Availability'),
                SegmentRow<String?>(
                  value: _f.availability,
                  options: const {null: 'Any', 'available': 'Available', 'reserved': 'Reserved'},
                  onChanged: (v) => setState(() => _f = _f.copyWith(availability: v)),
                ),
                _label('Listed'),
                SegmentRow<int>(
                  value: _f.listedWithinDays ?? 0,
                  options: _listed,
                  onChanged: (v) => setState(() => _f = _f.copyWith(listedWithinDays: v == 0 ? null : v)),
                ),
                _label('Sort by'),
                SegmentRow<String>(
                  value: _f.sort,
                  options: {
                    for (final e in sortOptions.entries)
                      if (e.key != 'nearest' || loc.hasCoords) e.key: e.value,
                  },
                  onChanged: (v) => setState(() => _f = _f.copyWith(sort: v)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, PSpace.gutter, 10),
            decoration: BoxDecoration(
              color: context.pc.surface,
              border: Border(top: BorderSide(color: context.pc.border)),
            ),
            child: SafeArea(top: false, child: PButton('Show results', onPressed: _apply)),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(t, style: context.tt.titleSmall),
  );
}
