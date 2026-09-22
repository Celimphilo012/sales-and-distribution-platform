/// Typed application error hierarchy.
///
/// Every network failure gets mapped (see `error_mapper.dart`) into one of
/// these so presentation code can `switch` on a closed set instead of
/// inspecting raw Dio exceptions.
sealed class AppError {
  const AppError(this.message);

  final String message;
}

/// No network connection, DNS failure, connection refused, etc.
class NetworkError extends AppError {
  const NetworkError([super.message = 'Could not reach the server. Check your connection.']);
}

/// The request took too long (connect or receive timeout).
class TimeoutError extends AppError {
  const TimeoutError([super.message = 'The request timed out. Please try again.']);
}

/// 401 — missing/expired/invalid credentials.
class UnauthorizedError extends AppError {
  const UnauthorizedError([super.message = 'You need to sign in to continue.']);
}

/// 403 — authenticated but not permitted.
class ForbiddenError extends AppError {
  const ForbiddenError([super.message = "You don't have permission to do that."]);
}

/// 404.
class NotFoundError extends AppError {
  const NotFoundError([super.message = 'The requested resource was not found.']);
}

/// 400/422 — validation failure. `fieldErrors` maps field name to messages
/// when the backend supplies class-validator-style detail.
class ValidationError extends AppError {
  const ValidationError(super.message, {this.fieldErrors = const {}});

  final Map<String, List<String>> fieldErrors;
}

/// 409 — conflicting state (e.g. duplicate email, stale approval).
class ConflictError extends AppError {
  const ConflictError([super.message = 'This conflicts with the current state. Please refresh.']);
}

/// 5xx or anything else the backend's `AllExceptionsFilter` shape reports.
class ServerError extends AppError {
  const ServerError([super.message = 'Something went wrong on the server. Please try again.']);
}

/// Anything that doesn't fit the above (unexpected shape, parsing failure).
class UnknownError extends AppError {
  const UnknownError([super.message = 'An unexpected error occurred.']);
}

/// 503 — a dependency (for the ordering app: the WAREHOUSE) could not be
/// reached at all. The backend guarantees nothing was attempted on the far
/// side, so the caller can always retry safely. Deliberately its own type
/// (not folded into [ServerError]) so the UI can show a calm "safe to
/// retry" message instead of a generic failure.
class ServiceUnavailableError extends AppError {
  const ServiceUnavailableError([super.message = 'The warehouse is temporarily unavailable. This action is safe to retry.']);
}
