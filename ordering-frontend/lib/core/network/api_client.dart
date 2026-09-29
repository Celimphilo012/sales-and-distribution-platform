import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../error/app_error.dart';
import '../error/error_mapper.dart';
import 'auth_interceptor.dart';
import 'auth_token_store.dart';
import 'otp_interceptor.dart';
import 'refresh_interceptor.dart';

BaseOptions _baseOptions() => BaseOptions(
  baseUrl: AppConfig.apiBaseUrl,
  connectTimeout: AppConfig.connectTimeout,
  receiveTimeout: AppConfig.receiveTimeout,
  contentType: 'application/json',
);

/// Thin wrapper around a configured [Dio] instance: attaches the bearer
/// token, silently refreshes it on a 401 and retries once, asks for a
/// one-time code when an action needs one (428) and retries with it, and
/// maps every failure into a typed [AppError].
class ApiClient {
  ApiClient(
    AuthTokenStore tokenStore, {
    required Future<void> Function() onRefreshFailed,
    required OtpPrompt otpPrompt,
  })
    : dio = Dio(_baseOptions()),
      _refreshDio = Dio(_baseOptions()) {
    dio.interceptors.addAll([
      AuthInterceptor(tokenStore),
      RefreshInterceptor(
        tokenStore: tokenStore,
        mainDio: dio,
        refreshDio: _refreshDio,
        onRefreshFailed: onRefreshFailed,
      ),
      OtpInterceptor(mainDio: dio, prompt: otpPrompt),
    ]);
  }

  final Dio dio;

  /// Bare — no interceptors — used only to call `/auth/refresh` itself, so
  /// that call can never re-trigger [RefreshInterceptor].
  final Dio _refreshDio;

  /// Runs [request] and maps any [DioException] into a typed [AppError],
  /// so callers can catch [AppError] instead of Dio's exception type.
  Future<T> guard<T>(Future<T> Function(Dio dio) request) async {
    try {
      return await request(dio);
    } on DioException catch (exception) {
      throw ErrorMapper.fromDioException(exception);
    }
  }
}
