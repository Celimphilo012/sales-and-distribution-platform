/// Static, compile-time app configuration.
///
/// F1 ships with a hard-coded default so the app runs out of the box against
/// a local backend. F2 (live auth wiring) can promote this to a
/// `--dart-define`-driven value without changing any call sites.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
