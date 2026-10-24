import 'package:flutter/foundation.dart';

enum AppEnv { dev, staging, prod }

/// Environment-specific settings, supplied with `--dart-define`:
///   --dart-define=APP_ENV=prod|staging|dev
///   --dart-define=API_BASE_URL=https://petora.in/api/v1   (optional override)
class AppConfig {
  const AppConfig({required this.env, required this.apiBaseUrl});

  final AppEnv env;
  final String apiBaseUrl;

  bool get isProd => env == AppEnv.prod;

  /// Public website origin used for share links.
  String get webBaseUrl =>
      apiBaseUrl.startsWith('https://') ? apiBaseUrl.replaceFirst(RegExp(r'/api/v1$'), '') : 'https://petora.in';

  static const _defaults = {
    AppEnv.dev: 'http://10.0.2.2:8080/api/v1', // Android emulator -> host loopback
    AppEnv.staging: 'https://staging.petora.in/api/v1',
    AppEnv.prod: 'https://petora.in/api/v1',
  };

  static String defaultDevUrl({bool isWeb = kIsWeb, TargetPlatform? platform}) {
    if (isWeb) return 'http://localhost:8080/api/v1';
    final p = platform ?? defaultTargetPlatform;
    if (p == TargetPlatform.android) return 'http://10.0.2.2:8080/api/v1';
    return 'http://localhost:8080/api/v1';
  }

  /// Builds the config from compile-time defines. In release builds the base URL
  /// must be HTTPS - a cleartext or localhost URL throws at start-up.
  factory AppConfig.fromEnvironment({bool? release}) {
    const envName = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    const override = String.fromEnvironment('API_BASE_URL');
    return AppConfig.resolve(envName, override, release: release ?? kReleaseMode);
  }

  factory AppConfig.resolve(
    String envName,
    String override, {
    required bool release,
    bool isWeb = kIsWeb,
    TargetPlatform? platform,
  }) {
    final env = AppEnv.values.firstWhere(
      (e) => e.name == envName,
      orElse: () => throw StateError('APP_ENV must be dev, staging or prod (got "$envName")'),
    );
    final defaultUrl = env == AppEnv.dev ? defaultDevUrl(isWeb: isWeb, platform: platform) : _defaults[env]!;
    final base = (override.isNotEmpty ? override : defaultUrl).replaceAll(RegExp(r'/+$'), '');
    if (release) {
      final uri = Uri.parse(base);
      if (uri.scheme != 'https' || uri.host == 'localhost' || uri.host == '10.0.2.2' || uri.host == '127.0.0.1') {
        throw StateError('Release builds require an https API_BASE_URL (got $base)');
      }
    }
    return AppConfig(env: env, apiBaseUrl: base);
  }
}
