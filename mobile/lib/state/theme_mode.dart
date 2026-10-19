import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Light is the default; the user may choose dark or follow the system.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final v = ref.watch(sharedPrefsProvider).getString('theme_mode');
    return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.light);
  }

  Future<void> set(ThemeMode m) async {
    state = m;
    await ref.read(sharedPrefsProvider).setString('theme_mode', m.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
