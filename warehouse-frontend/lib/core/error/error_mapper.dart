import 'package:dio/dio.dart';

import 'app_error.dart';

/// Maps a [DioException] to a typed [AppError].
///
/// The backend's global `AllExceptionsFilter` returns bodies shaped like:
/// `{ statusCode, error, message, path, timestamp }`, where `message` is
/// either a string or (for class-validator failures) a list of strings.
/// This mapper is defensive about that shape rather than assuming it.
class ErrorMapper {
  const ErrorMapper._();

  static AppError fromDioException(DioException exception) {
    switch (exception.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const TimeoutError();
      case DioExceptionType.connectionError:
        return const NetworkError();
      case DioExceptionType.cancel:
        return const UnknownError('The request was cancelled.');
      case DioExceptionType.badCertificate:
        return const NetworkError('The server certificate could not be verified.');
      case DioExceptionType.badResponse:
        return _fromStatusCode(exception);
      case DioExceptionType.unknown:
        return const NetworkError();
      default:
        return const UnknownError();
    }
  }

  static AppError _fromStatusCode(DioException exception) {
    final statusCode = exception.response?.statusCode;
    final message = _extractMessage(exception.response?.data) ?? exception.message;

    switch (statusCode) {
      case 400:
      case 422:
        return ValidationError(
          message ?? 'The submitted data is invalid.',
          fieldErrors: _extractFieldErrors(exception.response?.data),
        );
      case 401:
        return UnauthorizedError(message ?? const UnauthorizedError().message);
      case 403:
        return ForbiddenError(message ?? const ForbiddenError().message);
      case 404:
        return NotFoundError(message ?? const NotFoundError().message);
      case 409:
        return ConflictError(message ?? const ConflictError().message);
      default:
        if (statusCode != null && statusCode >= 500) {
          return ServerError(message ?? const ServerError().message);
        }
        return UnknownError(message ?? const UnknownError().message);
    }
  }

  static String? _extractMessage(dynamic data) {
    if (data is Map) {
      final raw = data['message'];
      if (raw is String) return raw;
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => e.toString()).join('\n');
      }
    }
    return null;
  }

  static Map<String, List<String>> _extractFieldErrors(dynamic data) {
    if (data is Map && data['fieldErrors'] is Map) {
      final raw = data['fieldErrors'] as Map;
      return raw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is List ? value.map((e) => e.toString()).toList() : [value.toString()],
        ),
      );
    }
    return const {};
  }
}
