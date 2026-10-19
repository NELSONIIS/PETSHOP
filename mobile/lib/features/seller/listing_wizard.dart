import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Ref;
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/media_picker.dart';
import '../../data/repositories.dart';
import '../../models/common.dart';
import '../../models/listing.dart';
import '../../state/data.dart';
import '../../state/providers.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/cards.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/inputs.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';
import '../../ui/widgets/upload.dart';
import '../common.dart';

class _Photo {
  _Photo({required this.key, this.file, this.img, this.status = UploadStatus.queued});
  final String key;
  final UploadFile? file;
  Img? img;
  UploadStatus status;
  double progress = 0;
  String? error;
  CancelToken? cancel;
}

const stepTitles = [
  'Basics',
  'Species & breed',
  'Age & gender',
  'Price',
  'Characteristics',
  'Health & vaccination',
  'Photos',
  'Location',
  'Availability',
  'Preview & submit',
];

/// Add / edit pet wizard. Steps persist to the server as a draft as you go, so leaving never loses work.
class ListingWizardScreen extends ConsumerStatefulWidget {
  const ListingWizardScreen({super.key, this.listingId});
  final String? listingId;
  @override
  ConsumerState<ListingWizardScreen> createState() => _ListingWizardScreenState();
}

class _ListingWizardScreenState extends ConsumerState<ListingWizardScreen> {
  ListingDraft _d = ListingDraft();
  String? _id;
  String _availability = 'available';
  String _loadedAvailability = 'available';
  int _step = 0;
  bool _loading = false, _saving = false, _dirty = false;
  String? _stepError; // inline validation message (a snackbar would cover the bottom action bar)
  Object? _loadError;
  final _photos = <_Photo>[];
  final _forms = List.generate(10, (_) => GlobalKey<FormState>());

  // controllers
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _years = TextEditingController();
  final _months = TextEditingController();
  final _colour = TextEditingController();
  final _price = TextEditingController();
  final _vaccNotes = TextEditingController();
  final _healthNotes = TextEditingController();
  final _city = TextEditingController();
  String? _state;
  final _attr = {for (final k in attributeKeys.keys) k: TextEditingController()};

  static const attributeKeys = {
    'temperament': 'Temperament (e.g. friendly, calm)',
    'size': 'Size (small / medium / large)',
    'coat': 'Coat',
    'diet': 'Diet',
    'trained': 'Training (e.g. house-trained)',
    'good_with_kids': 'Good with kids? (yes / no / unknown)',
  };

  @override
  void initState() {
    super.initState();
    _id = widget.listingId;
    if (_id != null) {
      _loading = true;
      Future.microtask(_loadExisting);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _desc,
      _years,
      _months,
      _colour,
      _price,
      _vaccNotes,
      _healthNotes,
      _city,
      ..._attr.values,
    ]) {
      c.dispose();
    }
    for (final p in _photos) {
      p.cancel?.cancel();
    }
    super.dispose();
  }

  Future<void> _loadExisting() async {
    try {
      final l = await ref.read(sellerRepoProvider).listing(_id!);
      _d = ListingDraft.fromListing(l);
      _availability = _loadedAvailability = l.availability;
      _title.text = _d.title;
      _desc.text = _d.description;
      if (_d.ageMonths != null) {
        _years.text = _d.ageMonths! >= 12 ? '${_d.ageMonths! ~/ 12}' : '';
        _months.text = '${_d.ageMonths! % 12}';
      }
      _colour.text = _d.colour;
      _price.text = _d.priceMinor == 0
          ? ''
          : (_d.priceMinor % 100 == 0 ? '${_d.priceMinor ~/ 100}' : (_d.priceMinor / 100).toStringAsFixed(2));
      _vaccNotes.text = _d.vaccinationNotes;
      _healthNotes.text = _d.healthNotes;
      _city.text = _d.city;
      _state = indianStates.contains(_d.state) ? _d.state : null;
      _d.attributes.forEach((k, v) => _attr[k]?.text = v);
      for (final i in l.images) {
        _photos.add(_Photo(key: i.id, img: i, status: UploadStatus.done));
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = e;
        });
      }
    }
  }

  // ---- step data collection ----

  void _collect() {
    _d.title = _title.text.trim();
    _d.description = _desc.text.trim();
    _d.colour = _colour.text.trim();
    final y = int.tryParse(_years.text.trim());
    final m = int.tryParse(_months.text.trim());
    _d.ageMonths = (y == null && m == null) ? null : (y ?? 0) * 12 + (m ?? 0);
    if (_d.listingType == 'sale') {
      _d.priceMinor = parseMoneyToMinor(_price.text) ?? 0;
    }
    _d.vaccinationNotes = _vaccNotes.text.trim();
    _d.healthNotes = _healthNotes.text.trim();
    _d.city = _city.text.trim();
    _d.state = _state ?? '';
    _d.attributes = {
      for (final e in _attr.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
  }

  Future<bool> _persist() async {
    _collect();
    try {
      final repo = ref.read(sellerRepoProvider);
      if (_id == null) {
        final l = await repo.createListing(_d);
        _id = l.id;
      } else {
        await repo.updateListing(_id!, _d);
      }
      ref.invalidate(sellerListingsProvider);
      ref.invalidate(sellerDashboardProvider);
      _dirty = false;
      return true;
    } on AppException catch (e) {
      if (!mounted) return false;
      if (e.kind == ErrorKind.subscriptionRequired ||
          e.kind == ErrorKind.membershipRequired ||
          e.kind == ErrorKind.limitReached) {
        _planPrompt(e);
      } else if (e.fieldErrors.isNotEmpty) {
        showSnack(context, e.fieldErrors.entries.map((x) => '${titleCase(x.key)} ${x.value}').join('\n'), error: true);
      } else {
        handleActionError(context, e);
      }
      return false;
    }
  }

  void _planPrompt(AppException e) => showPetoraSheet<void>(
    context,
    builder: (ctx) => SheetScaffold(
      title: e.kind == ErrorKind.limitReached ? 'Listing limit reached' : 'An active plan is required',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.message.isNotEmpty ? e.message : 'Subscribe or upgrade your seller plan to add more listings.',
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

  bool _validateStep() {
    switch (_step) {
      case 1:
        if (_d.categoryId == null) {
          setState(() => _stepError = 'Choose a category');
          return false;
        }
      case 3:
        if (_d.listingType == 'sale' && (parseMoneyToMinor(_price.text) ?? 0) <= 0) {
          _forms[3].currentState?.validate();
          return false;
        }
      case 6:
        if (_photos.any((p) => p.status == UploadStatus.uploading || p.status == UploadStatus.queued)) {
          setState(() => _stepError = 'Wait for uploads to finish');
          return false;
        }
        if (!_photos.any((p) => p.status == UploadStatus.done)) {
          setState(() => _stepError = 'Add at least one photo');
          return false;
        }
        return true;
      default:
    }
    return _forms[_step].currentState?.validate() ?? true;
  }

  Future<void> _next() async {
    if (_saving) return;
    setState(() => _stepError = null);
    if (!_validateStep()) return;
    setState(() => _saving = true);
    var ok = true;
    if (_step == 1 || (_id != null && const {2, 3, 4, 5, 7}.contains(_step))) {
      ok = await _persist();
    } else if (_step == 0 || _step == 6) {
      _collect();
    }
    if (ok && _step == 8 && _id != null && _availability != _loadedAvailability) {
      try {
        await ref.read(sellerRepoProvider).setAvailability(_id!, _availability);
        _loadedAvailability = _availability;
      } on AppException catch (e) {
        ok = false;
        if (mounted) showError(context, e);
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok && _step < stepTitles.length - 1) {
      setState(() {
        _step++;
        _stepError = null;
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      if (!await _persist()) return;
      await ref.read(sellerRepoProvider).submitListing(_id!);
      ref.invalidate(sellerListingsProvider);
      ref.invalidate(sellerDashboardProvider);
      if (mounted) context.go('/sell/listing/$_id/submitted');
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.kind == ErrorKind.subscriptionRequired || e.kind == ErrorKind.membershipRequired) {
        _planPrompt(e);
      } else if (e.fieldErrors.isNotEmpty) {
        showSnack(context, e.fieldErrors.values.join('\n'), error: true);
      } else {
        handleActionError(context, e);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---- photos ----

  Future<void> _addPhotos({bool camera = false}) async {
    final cfg = ref.read(publicConfigProvider).asData?.value ?? const PublicConfig();
    final room = cfg.maxImages - _photos.where((p) => p.status != UploadStatus.failed).length;
    if (room <= 0) {
      showSnack(context, 'You can add up to ${cfg.maxImages} photos.', error: true);
      return;
    }
    final files = await ref.read(mediaPickerProvider).pickImages(camera: camera, limit: room);
    for (final f in files.take(room)) {
      final lower = f.mime.toLowerCase();
      if (!const ['image/jpeg', 'image/png', 'image/webp'].contains(lower)) {
        if (mounted) {
          showSnack(context, '${f.name}: only JPEG, PNG or WebP photos are supported.', error: true);
        }
        continue;
      }
      if (f.size > cfg.maxImageMb * 1024 * 1024) {
        if (mounted) {
          showSnack(context, '${f.name} is larger than ${cfg.maxImageMb} MB.', error: true);
        }
        continue;
      }
      _photos.add(_Photo(key: const Uuid().v4(), file: f));
    }
    if (mounted) setState(() {});
    _pump();
  }

  void _pump() {
    final active = _photos.where((p) => p.status == UploadStatus.uploading).length;
    var slots = 2 - active;
    for (final p in _photos) {
      if (slots <= 0) break;
      if (p.status == UploadStatus.queued) {
        slots--;
        _upload(p);
      }
    }
  }

  Future<void> _upload(_Photo p) async {
    // A listing id is required for uploads; photos step is only reachable after the draft exists.
    if (_id == null) return;
    setState(() {
      p.status = UploadStatus.uploading;
      p.progress = 0;
      p.error = null;
      p.cancel = CancelToken();
    });
    try {
      final img = await ref
          .read(sellerRepoProvider)
          .uploadImage(
            _id!,
            p.file!,
            onProgress: (s, t) {
              if (t > 0 && mounted) setState(() => p.progress = s / t);
            },
            cancel: p.cancel,
          );
      if (!mounted) return;
      setState(() {
        p.img = img;
        p.status = UploadStatus.done;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      if (e.code == 'cancelled') {
        setState(() => _photos.remove(p));
      } else {
        setState(() {
          p.status = UploadStatus.failed;
          p.error = e.fieldErrors.values.isNotEmpty ? e.fieldErrors.values.first : e.userMessage;
        });
      }
    }
    _pump();
  }

  Future<void> _deletePhoto(_Photo p) async {
    if (p.img != null && _id != null) {
      try {
        await ref.read(sellerRepoProvider).deleteImage(_id!, p.img!.id);
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    if (mounted) setState(() => _photos.remove(p));
  }

  Future<void> _setCover(_Photo p) async {
    try {
      await ref.read(sellerRepoProvider).setCover(_id!, p.img!.id);
      setState(() {
        for (final x in _photos) {
          if (x.img != null) {
            final i = x.img!;
            x.img = Img(
              id: i.id,
              thumb: i.thumb,
              medium: i.medium,
              large: i.large,
              width: i.width,
              height: i.height,
              position: i.position,
              isCover: x == p,
              altText: i.altText,
            );
          }
        }
      });
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _reorder(int oldI, int newI) async {
    final done = _photos.where((p) => p.status == UploadStatus.done).toList();
    final before = List.of(_photos);
    final moved = done.removeAt(oldI);
    done.insert(newI, moved);
    final rest = _photos.where((p) => p.status != UploadStatus.done);
    setState(
      () => _photos
        ..clear()
        ..addAll(done)
        ..addAll(rest),
    );
    try {
      await ref.read(sellerRepoProvider).reorderImages(_id!, [for (final p in done) p.img!.id]);
    } catch (e) {
      if (mounted) {
        setState(
          () => _photos
            ..clear()
            ..addAll(before),
        );
        showError(context, e);
      }
    }
  }

  Future<void> _useLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are off.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Permission not granted - enter the city manually.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 15));
      setState(() {
        _d.lat = pos.latitude;
        _d.lng = pos.longitude;
      });
      if (mounted) {
        showSnack(context, 'Coordinates captured for distance search. Enter the city name too.');
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, e is String ? e : 'Could not get your location.', error: true);
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (_step == 0 && !_dirty && _id == null) return true;
    return confirmDialog(
      context,
      title: 'Leave listing editor?',
      message: _id == null
          ? 'Your draft has not been saved yet.'
          : 'Progress up to your last completed step is saved as a draft.',
      confirmLabel: 'Leave',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: petoraAppBar(context, 'Edit listing'), body: const ListSkeleton());
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: petoraAppBar(context, 'Edit listing'),
        body: ErrorState(
          error: _loadError!,
          onRetry: () {
            setState(() {
              _loadError = null;
              _loading = true;
            });
            _loadExisting();
          },
        ),
      );
    }
    final last = _step == stepTitles.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_step > 0 && !_saving) {
          setState(() {
            _step--;
            _stepError = null;
          });
          return;
        }
        final leave = await _confirmLeave();
        if (!context.mounted) return;
        if (leave) context.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.listingId == null ? 'Add a pet' : 'Edit listing'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () async {
              final leave = await _confirmLeave();
              if (!context.mounted) return;
              if (leave) context.pop();
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(PSpace.gutter, 4, PSpace.gutter, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: (_step + 1) / stepTitles.length,
                      minHeight: 4,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 6),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        'Step ${_step + 1} of ${stepTitles.length} · ${stepTitles[_step]}',
                        style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(PSpace.gutter, 4, PSpace.gutter, PSpace.xl),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    if (_stepError != null) ...[
                      InfoBanner(_stepError!, tone: BannerTone.danger, icon: Icons.error_outline),
                      const SizedBox(height: 12),
                    ],
                    _stepBody(),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(PSpace.gutter, 10, PSpace.gutter, 10),
                decoration: BoxDecoration(
                  color: context.pc.surface,
                  border: Border(top: BorderSide(color: context.pc.border)),
                ),
                child: Row(
                  children: [
                    if (_step > 0) ...[
                      Expanded(
                        child: PButton(
                          'Back',
                          kind: PButtonKind.outline,
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _step--;
                                  _stepError = null;
                                }),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: last
                          ? PButton('Submit for moderation', icon: Icons.send, onPressed: _submit, loading: _saving)
                          : PButton(
                              _step == 1 && _id == null ? 'Save draft & continue' : 'Continue',
                              onPressed: _next,
                              loading: _saving,
                            ),
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

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _basics();
      case 1:
        return _species();
      case 2:
        return _ageGender();
      case 3:
        return _priceStep();
      case 4:
        return _characteristics();
      case 5:
        return _health();
      case 6:
        return _photosStep();
      case 7:
        return _location();
      case 8:
        return _availabilityStep();
      default:
        return _preview();
    }
  }

  Widget _head(String t, [String? sub]) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t, style: context.tt.headlineMedium),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(sub, style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted)),
          ),
      ],
    ),
  );

  Widget _basics() => Form(
    key: _forms[0],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('Tell us about the pet', 'A clear, honest title and description get more trustworthy enquiries.'),
        Text('Listing type', style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
        const SizedBox(height: 6),
        SegmentRow<String>(
          value: _d.listingType,
          options: const {'sale': 'For sale', 'adoption': 'Adoption / rehoming'},
          onChanged: (v) => setState(() {
            _d.listingType = v;
            _dirty = true;
          }),
        ),
        gap16,
        PTextField(
          label: 'Title',
          controller: _title,
          hint: 'e.g. Labrador puppy, 3 months, vaccinated',
          maxLength: 140,
          validator: (v) => (v ?? '').trim().length < 5 ? 'Title must be at least 5 characters' : null,
          onChanged: (_) => _dirty = true,
        ),
        gap16,
        PTextField(
          label: 'Description',
          controller: _desc,
          maxLines: 6,
          minLines: 4,
          maxLength: 5000,
          hint: 'Temperament, routine, why you are selling or rehoming...',
          onChanged: (_) => _dirty = true,
        ),
      ],
    ),
  );

  Widget _species() {
    final cats = ref.watch(categoriesProvider);
    return Form(
      key: _forms[1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head('Species & breed'),
          cats.when(
            loading: () => const ListSkeleton(count: 2),
            error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(categoriesProvider)),
            data: (list) {
              final cur = list.where((c) => c.id == _d.categoryId).firstOrNull;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final c in list)
                        PFilterChip(
                          label: c.name,
                          selected: c.id == _d.categoryId,
                          icon: null,
                          onTap: () => setState(() {
                            _d.categoryId = c.id;
                            _stepError = null;
                            _d.breedId = null;
                            _dirty = true;
                          }),
                        ),
                    ],
                  ),
                  if (cur != null && cur.requiresVerifiedSeller) ...[
                    gap12,
                    const InfoBanner(
                      'This category requires an approved Verified seller account to publish.',
                      tone: BannerTone.warning,
                    ),
                  ],
                  if (cur != null && cur.breeds.isNotEmpty) ...[
                    gap16,
                    PDropdown<String?>(
                      label: 'Breed',
                      value: _d.breedId,
                      hint: 'Select breed (optional)',
                      items: {null: 'Mixed / not listed', for (final b in cur.breeds) b.id: b.name},
                      onChanged: (v) => setState(() {
                        _d.breedId = v;
                        _dirty = true;
                      }),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _ageGender() => Form(
    key: _forms[2],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('Age & gender'),
        Row(
          children: [
            Expanded(
              child: PTextField(
                label: 'Years',
                controller: _years,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 2,
                validator: (v) => (int.tryParse(v ?? '') ?? 0) > 50 ? 'Too high' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PTextField(
                label: 'Months',
                controller: _months,
                keyboard: TextInputType.number,
                formatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 2,
                validator: (v) => (int.tryParse(v ?? '') ?? 0) > 11 ? '0-11' : null,
              ),
            ),
          ],
        ),
        gap16,
        Text('Gender', style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
        const SizedBox(height: 6),
        SegmentRow<String>(
          value: _d.gender,
          options: const {'male': 'Male', 'female': 'Female', 'unknown': 'Not sure'},
          onChanged: (v) => setState(() => _d.gender = v),
        ),
        gap16,
        PTextField(label: 'Colour / markings (optional)', controller: _colour),
      ],
    ),
  );

  Widget _priceStep() => Form(
    key: _forms[3],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head(
          'Price',
          _d.listingType == 'adoption'
              ? 'Adoption listings are free. Do not ask for payment before meeting.'
              : 'Enter your asking price in rupees.',
        ),
        if (_d.listingType == 'adoption')
          const InfoBanner(
            'Adoption listings cannot have a price. Rehoming fees are not allowed.',
            icon: Icons.volunteer_activism_outlined,
          )
        else
          PTextField(
            label: 'Price (₹)',
            controller: _price,
            keyboard: const TextInputType.numberWithOptions(decimal: true),
            formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            prefix: const Padding(
              padding: EdgeInsets.only(left: 14, right: 4),
              child: Align(widthFactor: 1, child: Text('₹')),
            ),
            validator: (v) {
              final m = parseMoneyToMinor(v ?? '');
              if (m == null) return 'Enter a valid amount';
              if (m <= 0) return 'Price must be greater than zero';
              return null;
            },
            onChanged: (_) => _dirty = true,
          ),
      ],
    ),
  );

  Widget _characteristics() => Form(
    key: _forms[4],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('Characteristics', 'Optional details that help buyers decide.'),
        for (final e in attributeKeys.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: PTextField(label: e.value, controller: _attr[e.key], maxLength: 100),
          ),
      ],
    ),
  );

  Widget _health() {
    Widget tri(String label, bool? v, ValueChanged<bool?> set) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
        const SizedBox(height: 6),
        SegmentRow<int>(
          value: v == null ? 0 : (v ? 1 : 2),
          options: const {0: 'Not stated', 1: 'Yes', 2: 'No'},
          onChanged: (x) => setState(() => set(x == 0 ? null : x == 1)),
        ),
      ],
    );
    return Form(
      key: _forms[5],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _head(
            'Health & vaccination',
            'Only state what is true and what you can show records for. PETORA does not verify health claims.',
          ),
          Text('Vaccination status', style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted)),
          const SizedBox(height: 6),
          SegmentRow<String>(
            value: _d.vaccinationStatus,
            options: const {'unspecified': 'Not stated', 'none': 'None', 'partial': 'Partial', 'complete': 'Complete'},
            onChanged: (v) => setState(() => _d.vaccinationStatus = v),
          ),
          gap16,
          PTextField(
            label: 'Vaccination details (vaccines, dates)',
            controller: _vaccNotes,
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
          ),
          gap16,
          tri('Dewormed', _d.dewormed, (v) => _d.dewormed = v),
          gap16,
          tri('Microchipped', _d.microchipped, (v) => _d.microchipped = v),
          gap16,
          PTextField(
            label: 'Other health notes (optional)',
            controller: _healthNotes,
            maxLines: 3,
            minLines: 2,
            maxLength: 500,
          ),
        ],
      ),
    );
  }

  Widget _photosStep() {
    final cfg = ref.watch(publicConfigProvider).asData?.value ?? const PublicConfig();
    final pending = _photos.where((p) => p.status != UploadStatus.done).toList();
    final done = _photos.where((p) => p.status == UploadStatus.done).toList();
    if (_id == null) {
      return const EmptyState(
        icon: Icons.photo_library_outlined,
        title: 'Save your draft first',
        message: 'Go back and continue past Species & breed to create the draft.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head(
          'Photos',
          'Add up to ${cfg.maxImages} clear photos (JPEG, PNG or WebP, ${cfg.maxImageMb} MB max). The first/cover photo is shown in search results. Only photos of the actual pet - no stock images.',
        ),
        Row(
          children: [
            Expanded(
              child: PButton(
                'Choose photos',
                icon: Icons.photo_library_outlined,
                kind: PButtonKind.outline,
                onPressed: () => _addPhotos(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PButton(
                'Camera',
                icon: Icons.photo_camera_outlined,
                kind: PButtonKind.outline,
                onPressed: () => _addPhotos(camera: true),
              ),
            ),
          ],
        ),
        gap12,
        if (pending.isNotEmpty) ...[
          Text('Uploading', style: context.tt.titleSmall),
          gap8,
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pending.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final p = pending[i];
                return SizedBox(
                  width: 110,
                  child: UploadTile(
                    status: p.status,
                    progress: p.progress,
                    error: p.error,
                    onRetry: () {
                      setState(() => p.status = UploadStatus.queued);
                      _pump();
                    },
                    onCancel: () => p.cancel?.cancel(),
                    onDelete: () => setState(() => _photos.remove(p)),
                    index: i,
                  ),
                );
              },
            ),
          ),
          gap12,
        ],
        Text('Your photos (${done.length})', style: context.tt.titleSmall),
        const SizedBox(height: 2),
        Text(
          'Drag to reorder. Tap the star to choose the cover.',
          style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
        ),
        gap8,
        if (done.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No photos yet')),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: done.length,
            onReorderItem: _reorder,
            itemBuilder: (_, i) {
              final p = done[i];
              return Card(
                key: ValueKey(p.key),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 72,
                        height: 72,
                        child: UploadTile(image: p.img, isCover: p.img?.isCover ?? false, index: i),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.img?.isCover == true ? 'Cover photo' : 'Photo ${i + 1}',
                          style: context.tt.titleSmall,
                        ),
                      ),
                      if (p.img?.isCover != true)
                        IconButton(
                          tooltip: 'Make cover photo',
                          icon: const Icon(Icons.star_outline),
                          onPressed: () => _setCover(p),
                        ),
                      IconButton(
                        tooltip: 'Remove photo',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _deletePhoto(p),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.drag_handle)),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _location() => Form(
    key: _forms[7],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('Where is the pet?', 'Buyers see the city and state only - never your street address.'),
        PTextField(
          label: 'City',
          controller: _city,
          validator: (v) => Validators.minLen(v, 2, 'City'),
          onChanged: (_) => _dirty = true,
        ),
        gap16,
        PDropdown<String>(
          label: 'State',
          value: _state,
          items: {for (final s in indianStates) s: s},
          onChanged: (v) => setState(() => _state = v),
          validator: (v) => v == null ? 'Select a state' : null,
        ),
        gap16,
        PButton(
          _d.lat == null ? 'Use my location for distance search' : 'Location captured ✓',
          icon: Icons.my_location,
          kind: PButtonKind.outline,
          onPressed: _useLocation,
        ),
      ],
    ),
  );

  Widget _availabilityStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _head('Availability', 'You can change this any time after the listing is live.'),
      RadioGroup<String>(
        groupValue: _availability,
        onChanged: (v) => setState(() => _availability = v ?? _availability),
        child: Column(
          children: const [
            RadioListTile<String>(title: Text('Available'), subtitle: Text('Ready to meet buyers'), value: 'available'),
            RadioListTile<String>(
              title: Text('Reserved'),
              subtitle: Text('Held for a buyer for now'),
              value: 'reserved',
            ),
          ],
        ),
      ),
    ],
  );

  Widget _preview() {
    _collect();
    final cats = ref.watch(categoriesProvider).asData?.value ?? const [];
    final cat = cats.where((c) => c.id == _d.categoryId).firstOrNull;
    final cover =
        _photos.where((p) => p.img?.isCover ?? false).firstOrNull ?? _photos.where((p) => p.img != null).firstOrNull;
    final missing = <String>[
      if (_d.title.length < 5) 'A title',
      if (_d.categoryId == null) 'A category',
      if (_d.listingType == 'sale' && _d.priceMinor <= 0) 'A price',
      if (_d.city.isEmpty || _d.state.isEmpty) 'City and state',
      if (cover == null) 'At least one photo',
    ];
    final preview = Listing(
      id: _id ?? 'preview',
      title: _d.title.isEmpty ? 'Untitled' : _d.title,
      listingType: _d.listingType,
      priceMinor: _d.priceMinor,
      ageMonths: _d.ageMonths,
      gender: _d.gender,
      city: _d.city,
      state: _d.state,
      category: cat == null ? null : Ref(id: cat.id, slug: cat.slug, name: cat.name),
      cover: cover?.img == null ? null : cover!.img,
      vaccinationStatus: _d.vaccinationStatus,
      availability: _availability,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _head('Preview', 'This is how your listing will appear in search results.'),
        Center(
          child: SizedBox(
            width: 220,
            child: ListingCard(listing: preview, onTap: () {}),
          ),
        ),
        gap16,
        if (missing.isNotEmpty)
          InfoBanner('Still needed: ${missing.join(', ')}', tone: BannerTone.warning, icon: Icons.checklist)
        else
          const InfoBanner(
            'Everything required is filled in.',
            tone: BannerTone.success,
            icon: Icons.check_circle_outline,
          ),
        gap12,
        InfoRow('Type', _d.listingType == 'sale' ? 'For sale' : 'Adoption'),
        InfoRow('Category', cat?.name ?? '-'),
        InfoRow('Age', formatAge(_d.ageMonths)),
        InfoRow('Gender', genderLabel(_d.gender)),
        InfoRow('Vaccination', vaccinationLabel(_d.vaccinationStatus)),
        InfoRow('Photos', '${_photos.where((p) => p.img != null).length}'),
        InfoRow('Availability', titleCase(_availability)),
        gap12,
        Text(
          'When you submit, our moderators review the listing before it goes live. You need an active seller plan to publish.',
          style: context.tt.bodySmall?.copyWith(color: context.pc.textMuted),
        ),
      ],
    );
  }
}

class ListingSubmittedScreen extends StatelessWidget {
  const ListingSubmittedScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(PSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(color: context.pc.successBg, shape: BoxShape.circle),
              child: Icon(Icons.check_rounded, size: 52, color: context.pc.success),
            ),
            gap24,
            Text('Submitted for review', style: context.tt.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Our moderators will review your listing - usually within one working day. You will get a notification when it is live or if changes are needed.',
              textAlign: TextAlign.center,
              style: context.tt.bodyLarge?.copyWith(color: context.pc.textMuted),
            ),
            gap24,
            PButton('View listing', onPressed: () => context.go('/sell/listing/$id')),
            gap8,
            PButton('Back to my listings', kind: PButtonKind.outline, onPressed: () => context.go('/sell/listings')),
          ],
        ),
      ),
    ),
  );
}
