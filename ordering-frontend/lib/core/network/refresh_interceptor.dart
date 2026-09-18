import 'package:dio/dio.dart';

import 'auth_token_store.dart';

/// On a 401, silently refreshes the access token and retries the original
/// request once. The backend rotates refresh tokens on every use (Phase 1A),
/// so the new refresh token returned by `/auth/refresh` MUST be persisted
/// each time — the old one is revoked server-side the moment it's used.
///
/// [refreshDio] is a bare [Dio] instance with no interceptors, dedicated to
/// calling `/auth/refresh` — this is what prevents an infinite loop: the
/// refresh call itself can never trigger this interceptor. The
/// `extra['retried']` flag is a second guard, capping the retried original
/// request to a single attempt.
class RefreshInterceptor extends Interceptor {
  RefreshInterceptor({
    required AuthTokenStore tokenStore,
    required Dio mainDio,
    required Dio refreshDio,
    required Future<void> Function() onRefreshFailed,
  }) : _tokenStore = tokenStore,
       _mainDio = mainDio,
       _refreshDio = refreshDio,
       _onRefreshFailed = onRefreshFailed;

  final AuthTokenStore _tokenStore;
  final Dio _mainDio;
  final Dio _refreshDio;
  final Future<void> Function() _onRefreshFailed;

  Future<bool>? _refreshInFlight;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    if (err.response?.statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    final refreshFuture = _refreshInFlight ??= _refresh();
    final refreshed = await refreshFuture;
    _refreshInFlight = null;

    if (!refreshed) {
      await _tokenStore.clear();
      await _onRefreshFailed();
      handler.next(err);
      return;
    }

    try {
      final newAccessToken = await _tokenStore.readAccessToken();
      final retryOptions = err.requestOptions;
      retryOptions.headers['Authorization'] = 'Bearer $newAccessToken';
      retryOptions.extra['retried'] = true;
      final response = await _mainDio.fetch(retryOptions);
      handler.resolve(response);
    } on DioException catch (retryError) {
      handler.next(retryError);
    }
  }

  Future<bool> _refresh() async {
    final refreshToken = await _tokenStore.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final response = await _refreshDio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = response.data!;
      await _tokenStore.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );
      return true;
    } on DioException {
      return false;
    }
  }
}
