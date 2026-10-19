import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/common.dart';
import 'providers.dart';

enum AuthStatus { unknown, guest, authed }

class AuthState {
  const AuthState(this.status, {this.user, this.bootError, this.sessionExpired = false});
  const AuthState.unknown() : this(AuthStatus.unknown);
  final AuthStatus status;
  final User? user;
  final AppException? bootError;
  final bool sessionExpired;
  bool get isAuthed => status == AuthStatus.authed && user != null;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState.unknown();

  /// Restores the session on app start. Network failures keep the tokens and surface a retry state;
  /// an explicit 401 (after the client's refresh attempt) falls back to guest browsing.
  Future<void> bootstrap() async {
    final api = ref.read(apiClientProvider);
    if (!await api.hasSession) {
      state = const AuthState(AuthStatus.guest);
      return;
    }
    try {
      final u = await ref.read(authRepoProvider).me();
      state = AuthState(AuthStatus.authed, user: u);
    } on AppException catch (e) {
      if (e.isNetwork || e.kind == ErrorKind.server || e.kind == ErrorKind.maintenance) {
        state = AuthState(AuthStatus.unknown, bootError: e);
      } else {
        await api.clearSession();
        state = const AuthState(AuthStatus.guest);
      }
    }
  }

  Future<User> login(String email, String password) async {
    final r = await ref.read(authRepoProvider).login(email, password);
    state = AuthState(AuthStatus.authed, user: r.user);
    return r.user;
  }

  Future<User> register({
    required String name,
    required String email,
    String phone = '',
    required String password,
    required String role,
  }) async {
    final r = await ref
        .read(authRepoProvider)
        .register(name: name, email: email, phone: phone, password: password, role: role);
    state = AuthState(AuthStatus.authed, user: r.user);
    return r.user;
  }

  Future<void> logout() async {
    try {
      await ref.read(authRepoProvider).logout();
    } catch (_) {
      await ref.read(apiClientProvider).clearSession();
    }
    state = const AuthState(AuthStatus.guest);
  }

  Future<void> refreshUser() async {
    try {
      final u = await ref.read(authRepoProvider).me();
      state = AuthState(AuthStatus.authed, user: u);
    } on AppException catch (_) {
      /* keep current state */
    }
  }

  void setUser(User u) => state = AuthState(AuthStatus.authed, user: u);

  /// Called by the API client when the refresh token was rejected.
  void sessionExpired() {
    if (state.status == AuthStatus.authed) {
      state = const AuthState(AuthStatus.guest, sessionExpired: true);
    }
  }

  void ackSessionExpired() {
    if (state.sessionExpired) state = const AuthState(AuthStatus.guest);
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Current user id (null for guests); user-scoped providers watch this so they reset on login/logout.
final userIdProvider = Provider<String?>((ref) => ref.watch(authProvider.select((s) => s.user?.id)));
