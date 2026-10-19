import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'state/theme_mode.dart';
import 'ui/theme.dart';

class PetoraApp extends ConsumerWidget {
  const PetoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'PETORA',
      debugShowCheckedModeBanner: false,
      theme: PetoraTheme.light(),
      darkTheme: PetoraTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
