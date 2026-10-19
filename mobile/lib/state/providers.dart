import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/config.dart';
import '../core/token_store.dart';
import '../data/repositories.dart';
import 'auth.dart';

/// Overridden in main() / tests.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig.fromEnvironment());
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(config: ref.watch(appConfigProvider), tokens: ref.watch(tokenStoreProvider));
  client.onSessionExpired = () => ref.read(authProvider.notifier).sessionExpired();
  return client;
});

final authRepoProvider = Provider((ref) => AuthRepository(ref.watch(apiClientProvider)));
final catalogRepoProvider = Provider((ref) => CatalogRepository(ref.watch(apiClientProvider)));
final buyerRepoProvider = Provider((ref) => BuyerRepository(ref.watch(apiClientProvider)));
final sellerRepoProvider = Provider((ref) => SellerRepository(ref.watch(apiClientProvider)));
final billingRepoProvider = Provider((ref) => BillingRepository(ref.watch(apiClientProvider)));
final accountRepoProvider = Provider((ref) => AccountRepository(ref.watch(apiClientProvider)));
