import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fails fast in release builds if API_BASE_URL is not https.
  final config = AppConfig.fromEnvironment();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(statusBarColor: Colors.transparent, systemNavigationBarColor: Colors.transparent),
  );
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      // Riverpod 3 retries failed providers by default; PETORA shows explicit retry states instead.
      retry: (_, _) => null,
      overrides: [sharedPrefsProvider.overrideWithValue(prefs), appConfigProvider.overrideWithValue(config)],
      child: const PetoraApp(),
    ),
  );
}
