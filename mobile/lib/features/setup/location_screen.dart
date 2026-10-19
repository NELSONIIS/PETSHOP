import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../state/data.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/buttons.dart';
import '../../ui/widgets/dialogs.dart';
import '../../ui/widgets/fields.dart';
import '../../ui/widgets/scaffolds.dart';
import '../../ui/widgets/states.dart';

/// Location selection / profile setup. [next] is set during first-run setup; otherwise the screen pops.
class LocationScreen extends ConsumerStatefulWidget {
  const LocationScreen({super.key, this.next});
  final String? next;
  @override
  ConsumerState<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends ConsumerState<LocationScreen> {
  final _form = GlobalKey<FormState>();
  late final UserLocation _initial = ref.read(locationProvider);
  late final _city = TextEditingController(text: _initial.city);
  late String? _state = indianStates.contains(_initial.state) ? _initial.state : null;
  late double _radius = _initial.radiusKm.toDouble().clamp(10, 500);
  double? _lat, _lng;
  bool _locating = false, _saving = false;
  String? _geoMsg;

  @override
  void initState() {
    super.initState();
    _lat = _initial.lat;
    _lng = _initial.lng;
  }

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _geoMsg = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw 'Location services are turned off on this device.';
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw 'Location permission was not granted. You can still enter your city manually.';
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 15));
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _geoMsg = 'Location captured. Enter your city name so sellers can see where you are searching.';
      });
    } catch (e) {
      setState(() => _geoMsg = e is String ? e : 'Could not get your location. Enter your city manually.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    await ref
        .read(locationProvider.notifier)
        .set(
          UserLocation(city: _city.text.trim(), state: _state ?? '', lat: _lat, lng: _lng, radiusKm: _radius.round()),
        );
    if (!mounted) return;
    ref.invalidate(homeNearbyProvider);
    if (widget.next != null) {
      context.go(widget.next!);
    } else {
      showSnack(context, 'Location saved');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormPage(
      title: 'Your location',
      actions: widget.next == null
          ? null
          : [TextButton(onPressed: () => context.go(widget.next!), child: const Text('Skip'))],
      bottom: PButton('Save location', onPressed: _save, loading: _saving),
      children: [
        Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Show pets near you', style: context.tt.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Your location is only used to sort and filter listings. Sellers never see it.',
                style: context.tt.bodyMedium?.copyWith(color: context.pc.textMuted),
              ),
              gap16,
              PButton(
                'Use my current location',
                icon: Icons.my_location,
                kind: PButtonKind.outline,
                loading: _locating,
                onPressed: _useMyLocation,
              ),
              if (_geoMsg != null) ...[
                gap8,
                InfoBanner(_geoMsg!, tone: _lat != null ? BannerTone.success : BannerTone.warning),
              ],
              gap16,
              PTextField(
                label: 'City',
                controller: _city,
                validator: (v) => Validators.minLen(v, 2, 'City'),
                textInputAction: TextInputAction.next,
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
              Text(
                'Search radius: ${_radius.round()} km',
                style: context.tt.labelMedium?.copyWith(color: context.pc.textMuted),
              ),
              Slider(
                value: _radius,
                min: 10,
                max: 500,
                divisions: 49,
                label: '${_radius.round()} km',
                onChanged: (v) => setState(() => _radius = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
