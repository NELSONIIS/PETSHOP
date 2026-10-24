import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petora/core/api_client.dart';
import 'package:petora/core/config.dart';
import 'package:petora/core/errors.dart';
import 'package:petora/core/format.dart';
import 'package:petora/core/token_store.dart';
import 'package:petora/models/listing.dart';
import 'package:petora/router.dart';
import 'package:petora/models/common.dart';
import 'package:petora/state/auth.dart';
import 'package:petora/ui/widgets/fields.dart';

import 'helpers/fake_backend.dart';

void main() {
  group('AppConfig', () {
    test('defaults per environment', () {
      expect(AppConfig.resolve('dev', '', release: false).apiBaseUrl, 'http://10.0.2.2:8080/api/v1');
      expect(AppConfig.resolve('dev', '', release: false, isWeb: true).apiBaseUrl, 'http://localhost:8080/api/v1');
      expect(AppConfig.resolve('staging', '', release: true).apiBaseUrl, 'https://staging.petora.in/api/v1');
      expect(AppConfig.resolve('prod', '', release: true).apiBaseUrl, 'https://petora.in/api/v1');
    });
    test('release builds reject cleartext and loopback URLs', () {
      expect(() => AppConfig.resolve('prod', 'http://petora.in/api/v1', release: true), throwsStateError);
      expect(() => AppConfig.resolve('dev', '', release: true), throwsStateError);
      expect(() => AppConfig.resolve('prod', 'https://localhost/api/v1', release: true), throwsStateError);
      expect(() => AppConfig.resolve('qa', '', release: false), throwsStateError);
    });
    test('trailing slash is trimmed and override wins in debug', () {
      expect(
        AppConfig.resolve('dev', 'http://192.168.1.5:8080/api/v1/', release: false).apiBaseUrl,
        'http://192.168.1.5:8080/api/v1',
      );
    });
  });

  group('formatting', () {
    test('money is formatted from integer minor units with Indian grouping', () {
      expect(formatMoney(1500000), '₹15,000');
      expect(formatMoney(12345678), '₹1,23,456.78');
      expect(formatMoney(49900), '₹499');
      expect(formatMoney(0, free: true), 'Free');
      expect(formatMoney(-5000), '-₹50');
    });
    test('rupee input parses to paise without floating point', () {
      expect(parseMoneyToMinor('15,000'), 1500000);
      expect(parseMoneyToMinor('499.5'), 49950);
      expect(parseMoneyToMinor('0.1'), 10);
      expect(parseMoneyToMinor('abc'), isNull);
      expect(parseMoneyToMinor('1.234'), isNull);
    });
    test('age labels', () {
      expect(formatAge(null), 'Age n/a');
      expect(formatAge(0), '< 1 mo');
      expect(formatAge(5), '5 mo');
      expect(formatAge(14), '14 mo');
      expect(formatAge(26), '2 yr 2 mo');
      expect(formatAge(36), '3 yr');
    });
  });

  group('validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('nope'), isNotNull);
      expect(Validators.email('a@b.co'), isNull);
    });
    test('password mirrors server rule (10+ chars, letter and digit)', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('onlyletterslong'), isNotNull);
      expect(Validators.password('1234567890123'), isNotNull);
      expect(Validators.password('Petora-2026-ok'), isNull);
    });
    test('phone and code', () {
      expect(Validators.phone('12345'), isNotNull);
      expect(Validators.phone('+919876543210'), isNull);
      expect(Validators.phone('', optional: true), isNull);
      expect(Validators.code6('12345'), isNotNull);
      expect(Validators.code6('123456'), isNull);
    });
  });

  group('PetFilter', () {
    test('toQuery omits empty values and counts active filters', () {
      const f = PetFilter(q: ' lab ', category: 'dogs', minPrice: 100, verifiedSeller: true);
      final q = f.toQuery();
      expect(q['q'], 'lab');
      expect(q['category'], 'dogs');
      expect(q['verified_seller'], true);
      expect(q['featured'], isNull);
      expect(f.activeCount, 3);
    });
    test('copyWith can clear nullable fields and equality is value based', () {
      const f = PetFilter(category: 'dogs', breed: 'labrador');
      final g = f.copyWith(category: null, breed: null);
      expect(g.category, isNull);
      expect(g.breed, isNull);
      expect(const PetFilter(category: 'dogs') == const PetFilter(category: 'dogs'), isTrue);
    });
  });

  group('error mapping', () {
    test('API error envelope becomes typed AppException with details and extra', () async {
      final b = FakeBackend()
        ..on(
          'POST',
          '/x',
          err(
            422,
            'validation_failed',
            'Some fields are invalid',
            details: [
              {'field': 'email', 'message': 'must be a valid email address'},
            ],
          ),
        )
        ..on(
          'POST',
          '/y',
          err(
            402,
            'membership_required',
            'Membership needed',
            extra: {
              'suggested_plans': [planJson()],
            },
          ),
        )
        ..on('GET', '/z', err(503, 'maintenance', 'Back soon'));
      final api = fakeClient(b);
      await expectLater(
        api.post('/x'),
        throwsA(
          isA<AppException>()
              .having((e) => e.kind, 'kind', ErrorKind.validation)
              .having((e) => e.fieldErrors['email'], 'field', contains('valid')),
        ),
      );
      try {
        await api.post('/y');
        fail('should throw');
      } on AppException catch (e) {
        expect(e.kind, ErrorKind.membershipRequired);
        expect(e.suggestedPlans, hasLength(1));
        expect(e.requestId, 'req-test');
      }
      await expectLater(
        api.get('/z'),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', ErrorKind.maintenance)),
      );
    });

    test('connection problems map to network/timeout', () async {
      final b = FakeBackend()
        ..on('GET', '/boom', (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError));
      final api = fakeClient(b);
      await expectLater(api.get('/boom'), throwsA(isA<AppException>().having((e) => e.isNetwork, 'network', isTrue)));
      expect(AppException(ErrorKind.network, '').userMessage, contains('internet'));
    });
  });

  group('session handling (single-flight refresh)', () {
    ApiClient make(FakeBackend api, FakeBackend refresh, MemoryTokenStore store, {void Function()? onExpired}) =>
        fakeClient(api, tokens: store, refreshBackend: refresh, onExpired: onExpired);

    test('concurrent 401s trigger exactly one refresh, then each request is retried once', () async {
      var refreshHits = 0;
      final refresh = FakeBackend()
        ..latency = const Duration(milliseconds: 30)
        ..on('POST', '/auth/refresh', (o) {
          refreshHits++;
          return ok({
            'user': userJson(),
            'access_token': 'new-access',
            'refresh_token': 'new-refresh',
            'expires_at': '2030-01-01T00:00:00Z',
          });
        });
      final api = FakeBackend()
        ..on(
          'GET',
          '/me',
          (o) =>
              o.headers['Authorization'] == 'Bearer new-access' ? ok(userJson()) : err(401, 'unauthorized', 'expired'),
        );
      final store = MemoryTokenStore(const StoredTokens(access: 'old-access', refresh: 'old-refresh'));
      final client = make(api, refresh, store);

      final results = await Future.wait([client.get('/me'), client.get('/me'), client.get('/me'), client.get('/me')]);
      expect(results.every((r) => r.map['email'] == 'asha@example.test'), isTrue);
      expect(refreshHits, 1, reason: 'single-flight');
      expect(client.refreshCalls, 1);
      // The rotated refresh token is persisted for the next refresh.
      final saved = await store.read();
      expect(saved!.access, 'new-access');
      expect(saved.refresh, 'new-refresh');
      // 4 originals (401) + 4 retries
      expect(api.count('GET', '/me'), 8);
    });

    test('refresh sends the stored refresh token in the body', () async {
      Object? sent;
      final refresh = FakeBackend()
        ..on('POST', '/auth/refresh', (o) {
          sent = o.data;
          return ok({'user': userJson(), 'access_token': 'a2', 'refresh_token': 'r2'});
        });
      final api = FakeBackend()
        ..on(
          'GET',
          '/me',
          (o) => o.headers['Authorization'] == 'Bearer a2' ? ok(userJson()) : err(401, 'unauthorized', 'x'),
        );
      final client = make(api, refresh, MemoryTokenStore(const StoredTokens(access: 'a1', refresh: 'r1')));
      await client.get('/me');
      expect(sent, {'refresh_token': 'r1'});
    });

    test('rejected refresh clears the session and signals expiry', () async {
      var expired = 0;
      final refresh = FakeBackend()..on('POST', '/auth/refresh', err(401, 'unauthorized', 'Session expired'));
      final api = FakeBackend()..on('GET', '/me', err(401, 'unauthorized', 'expired'));
      final store = MemoryTokenStore(const StoredTokens(access: 'a', refresh: 'r'));
      final client = make(api, refresh, store, onExpired: () => expired++);
      await expectLater(
        client.get('/me'),
        throwsA(isA<AppException>().having((e) => e.kind, 'kind', ErrorKind.unauthorized)),
      );
      expect(await store.read(), isNull);
      expect(expired, 1);
      expect(await client.hasSession, isFalse);
    });

    test('a network failure during refresh keeps the session (no surprise logout)', () async {
      var expired = 0;
      final refresh = FakeBackend()
        ..on(
          'POST',
          '/auth/refresh',
          (o) => throw DioException(requestOptions: o, type: DioExceptionType.connectionError),
        );
      final api = FakeBackend()..on('GET', '/me', err(401, 'unauthorized', 'expired'));
      final store = MemoryTokenStore(const StoredTokens(access: 'a', refresh: 'r'));
      final client = make(api, refresh, store, onExpired: () => expired++);
      await expectLater(client.get('/me'), throwsA(isA<AppException>()));
      expect(await store.read(), isNotNull);
      expect(expired, 0);
    });

    test('login/refresh endpoints never trigger the refresh loop', () async {
      var refreshHits = 0;
      final refresh = FakeBackend()
        ..on('POST', '/auth/refresh', (o) {
          refreshHits++;
          return ok({});
        });
      final api = FakeBackend()..on('POST', '/auth/login', err(401, 'unauthorized', 'Incorrect email or password'));
      final client = make(api, refresh, MemoryTokenStore(const StoredTokens(access: 'a', refresh: 'r')));
      await expectLater(client.post('/auth/login', body: {}), throwsA(isA<AppException>()));
      expect(refreshHits, 0);
    });

    test('every request carries X-Client: mobile and the bearer token', () async {
      final api = FakeBackend()..on('GET', '/me', ok(userJson()));
      final client = make(api, FakeBackend(), MemoryTokenStore(const StoredTokens(access: 'tok', refresh: 'r')));
      await client.get('/me');
      expect(api.log.single.headers['X-Client'], 'mobile');
      expect(api.log.single.headers['Authorization'], 'Bearer tok');
    });
  });

  group('router redirects', () {
    const buyer = User(id: '1', email: 'a@b.c', name: 'A', accountType: 'buyer');
    const seller = User(id: '2', email: 'a@b.c', name: 'S', accountType: 'seller');
    const staff = User(id: '3', email: 'a@b.c', name: 'T', accountType: 'staff');
    String? r(AuthState a, String loc, {bool seen = true}) => redirectFor(auth: a, location: loc, onboardingSeen: seen);

    test('everything waits on the splash until the session is known', () {
      expect(r(const AuthState.unknown(), '/search'), '/splash');
      expect(r(const AuthState.unknown(), '/splash'), isNull);
    });
    test('splash routes to the right home', () {
      expect(r(const AuthState(AuthStatus.guest), '/splash', seen: false), '/onboarding');
      expect(r(const AuthState(AuthStatus.guest), '/splash'), '/');
      expect(r(const AuthState(AuthStatus.authed, user: buyer), '/splash'), '/');
      expect(r(const AuthState(AuthStatus.authed, user: seller), '/splash'), '/sell');
      expect(r(const AuthState(AuthStatus.authed, user: staff), '/splash'), '/staff');
    });
    test('guests may browse but not reach account areas', () {
      const g = AuthState(AuthStatus.guest);
      expect(r(g, '/'), isNull);
      expect(r(g, '/pet/abc'), isNull);
      expect(r(g, '/plans'), isNull);
      expect(r(g, '/checkout/p-1'), startsWith('/login?from='));
      expect(r(g, '/notifications'), startsWith('/login'));
      expect(r(g, '/sell'), '/login');
      expect(r(g, '/sell/listing/new'), '/login');
    });
    test('roles are kept in their own area', () {
      const b = AuthState(AuthStatus.authed, user: buyer);
      const s = AuthState(AuthStatus.authed, user: seller);
      const t = AuthState(AuthStatus.authed, user: staff);
      expect(r(b, '/sell'), '/');
      expect(r(b, '/sell/listing/new'), '/');
      expect(r(s, '/'), '/sell');
      expect(r(s, '/favourites'), '/sell');
      expect(r(s, '/pet/abc'), isNull);
      expect(r(s, '/plans'), isNull);
      expect(r(b, '/login'), '/');
      expect(r(s, '/register'), '/sell');
      expect(r(t, '/search'), '/staff');
      expect(r(t, '/staff'), isNull);
    });
  });

  test('Paged meta', () {
    final m = Meta.fromJson({'page': 2, 'per_page': 20, 'total': 41, 'total_pages': 3});
    expect(m.hasMore, isTrue);
    expect(Meta.fromJson({'page': 3, 'total_pages': 3}).hasMore, isFalse);
  });
}
