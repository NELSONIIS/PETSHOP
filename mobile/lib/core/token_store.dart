import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredTokens {
  const StoredTokens({required this.access, required this.refresh, this.expiresAt});
  final String access;
  final String refresh;
  final DateTime? expiresAt;
}

abstract class TokenStore {
  Future<StoredTokens?> read();
  Future<void> write(StoredTokens tokens);
  Future<void> clear();
}

/// Tokens live in the Android Keystore-backed encrypted storage, never in SharedPreferences.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _s = storage ?? const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
  final FlutterSecureStorage _s;

  @override
  Future<StoredTokens?> read() async {
    final a = await _s.read(key: 'at');
    final r = await _s.read(key: 'rt');
    if (a == null || r == null) return null;
    final e = await _s.read(key: 'exp');
    return StoredTokens(access: a, refresh: r, expiresAt: e == null ? null : DateTime.tryParse(e));
  }

  @override
  Future<void> write(StoredTokens t) async {
    await _s.write(key: 'at', value: t.access);
    await _s.write(key: 'rt', value: t.refresh);
    if (t.expiresAt != null) {
      await _s.write(key: 'exp', value: t.expiresAt!.toIso8601String());
    }
  }

  @override
  Future<void> clear() async {
    await _s.delete(key: 'at');
    await _s.delete(key: 'rt');
    await _s.delete(key: 'exp');
  }
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._t]);
  StoredTokens? _t;
  @override
  Future<StoredTokens?> read() async => _t;
  @override
  Future<void> write(StoredTokens tokens) async => _t = tokens;
  @override
  Future<void> clear() async => _t = null;
}
