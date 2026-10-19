import 'dart:async';

import 'package:dio/dio.dart';

import 'config.dart';
import 'errors.dart';
import 'json.dart';
import 'token_store.dart';

/// Decoded `{data, meta}` envelope.
class ApiResponse {
  ApiResponse(this.data, this.meta);
  final dynamic data;
  final Json? meta;

  Json get map => data is Map ? (data as Map).cast<String, dynamic>() : <String, dynamic>{};
  List<Json> get list =>
      data is List ? (data as List).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList() : <Json>[];
}

const _noRefreshPaths = [
  '/auth/login',
  '/auth/register',
  '/auth/refresh',
  '/auth/forgot-password',
  '/auth/reset-password',
];

/// HTTP client for the PETORA API.
///  * adds `X-Client: mobile` and the bearer token,
///  * on 401 performs ONE shared (single-flight) token refresh for all concurrent requests, then retries once,
///  * if refresh fails, clears the stored session and calls [onSessionExpired].
class ApiClient {
  ApiClient({required this.config, required this.tokens, Dio? dio, Dio? refreshDio, this.onSessionExpired})
    : dio = dio ?? Dio(),
      _refreshDio = refreshDio ?? Dio() {
    for (final d in [this.dio, _refreshDio]) {
      d.options
        ..baseUrl = config.apiBaseUrl
        ..connectTimeout = const Duration(seconds: 12)
        ..receiveTimeout = const Duration(seconds: 25)
        ..sendTimeout = const Duration(seconds: 60)
        ..headers = {'X-Client': 'mobile', 'Accept': 'application/json'}
        ..validateStatus = (s) => s != null && s >= 200 && s < 300;
    }
    this.dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest, onError: _onError));
  }

  final AppConfig config;
  final TokenStore tokens;
  final Dio dio;
  final Dio _refreshDio;
  void Function()? onSessionExpired;

  StoredTokens? _cached;
  bool _loaded = false;
  Future<bool>? _refreshing;
  int refreshCalls = 0; // exposed for tests

  Future<void> _ensureLoaded() async {
    if (!_loaded) {
      _cached = await tokens.read();
      _loaded = true;
    }
  }

  Future<void> setTokens(StoredTokens t) async {
    _cached = t;
    _loaded = true;
    await tokens.write(t);
  }

  Future<void> clearSession() async {
    _cached = null;
    _loaded = true;
    await tokens.clear();
  }

  Future<bool> get hasSession async {
    await _ensureLoaded();
    return _cached != null;
  }

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    await _ensureLoaded();
    final t = _cached;
    if (t != null && o.headers['Authorization'] == null) {
      o.headers['Authorization'] = 'Bearer ${t.access}';
    }
    h.next(o);
  }

  Future<void> _onError(DioException e, ErrorInterceptorHandler h) async {
    final o = e.requestOptions;
    final path = o.path;
    final retriable =
        e.response?.statusCode == 401 &&
        o.extra['retried'] != true &&
        !_noRefreshPaths.any(path.endsWith) &&
        _cached != null;
    if (!retriable) return h.next(e);
    final failedToken = (o.headers['Authorization'] as String?)?.substring(7);
    final ok = await _refreshOnce(failedToken);
    if (!ok) return h.next(e);
    try {
      final opts = o.copyWith(
        headers: {...o.headers, 'Authorization': 'Bearer ${_cached!.access}'},
        extra: {...o.extra, 'retried': true},
        data: o.data is FormData ? (o.data as FormData).clone() : o.data,
      );
      h.resolve(await dio.fetch(opts));
    } on DioException catch (e2) {
      h.next(e2);
    }
  }

  /// Single-flight refresh. All callers awaiting during a refresh share the same Future.
  /// If another request already refreshed (token differs from the one that failed), skip the network call.
  Future<bool> _refreshOnce(String? failedToken) {
    if (_cached != null && failedToken != null && _cached!.access != failedToken && _refreshing == null) {
      return Future.value(true);
    }
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final current = _cached;
    if (current == null) return false;
    refreshCalls++;
    try {
      final r = await _refreshDio.post('/auth/refresh', data: {'refresh_token': current.refresh});
      final d = ((r.data as Map)['data'] as Map).cast<String, dynamic>();
      await setTokens(
        StoredTokens(
          access: J.str(d, 'access_token'),
          refresh: J.str(d, 'refresh_token'),
          expiresAt: J.dt(d, 'expires_at'),
        ),
      );
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Network blips must not log the user out; an explicit rejection must.
      if (status == 401 || status == 403 || status == 400) {
        await clearSession();
        onSessionExpired?.call();
      }
      return false;
    }
  }

  // ---- request helpers ----

  Future<ApiResponse> get(String path, {Map<String, dynamic>? query, CancelToken? cancel}) =>
      _send(() => dio.get(path, queryParameters: _clean(query), cancelToken: cancel));

  Future<ApiResponse> post(String path, {Object? body, Map<String, dynamic>? headers, CancelToken? cancel}) => _send(
    () => dio.post(
      path,
      data: body,
      options: Options(headers: headers),
      cancelToken: cancel,
    ),
  );

  Future<ApiResponse> put(String path, {Object? body}) => _send(() => dio.put(path, data: body));
  Future<ApiResponse> patch(String path, {Object? body}) => _send(() => dio.patch(path, data: body));
  Future<ApiResponse> delete(String path, {Object? body}) => _send(() => dio.delete(path, data: body));

  Future<ApiResponse> upload(String path, FormData form, {void Function(int, int)? onProgress, CancelToken? cancel}) =>
      _send(() => dio.post(path, data: form, onSendProgress: onProgress, cancelToken: cancel));

  Map<String, dynamic>? _clean(Map<String, dynamic>? q) {
    if (q == null) return null;
    final out = <String, dynamic>{};
    q.forEach((k, v) {
      if (v == null || (v is String && v.isEmpty)) return;
      out[k] = v;
    });
    return out;
  }

  Future<ApiResponse> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      final body = r.data;
      if (body is Map) {
        return ApiResponse(body['data'], (body['meta'] as Map?)?.cast<String, dynamic>());
      }
      return ApiResponse(null, null);
    } on DioException catch (e) {
      throw mapError(e);
    }
  }

  static AppException mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return AppException(ErrorKind.timeout, 'Request timed out');
      case DioExceptionType.cancel:
        return AppException(ErrorKind.unknown, 'Cancelled', code: 'cancelled');
      case DioExceptionType.connectionError:
        return AppException(ErrorKind.network, 'No connection');
      default:
        break;
    }
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) {
      final err = (data['error'] as Map).cast<String, dynamic>();
      final code = J.strN(err, 'code');
      final details = <String, String>{};
      final raw = err['details'];
      if (raw is List) {
        for (final d in raw.whereType<Map>()) {
          details[J.str(d.cast<String, dynamic>(), 'field')] = J.str(d.cast<String, dynamic>(), 'message');
        }
      }
      return AppException(
        AppException.kindFor(code, status),
        J.str(err, 'message'),
        code: code,
        status: status,
        fieldErrors: details,
        extra: J.mapN(err, 'extra'),
        requestId: J.strN(err, 'request_id'),
      );
    }
    if (status == null) {
      return AppException(ErrorKind.network, e.message ?? 'No connection');
    }
    return AppException(AppException.kindFor(null, status), '', status: status);
  }
}
