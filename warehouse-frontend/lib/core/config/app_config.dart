/// Static, compile-time app configuration.
///
/// This app is a standalone client of the WAREHOUSE system only
/// (ARCHITECTURE.md §A2) — it never talks to the back-office/ordering
/// backend on port 3000. The default points at the warehouse's local dev
/// server; override with `--dart-define=API_BASE_URL=...` for other
/// environments without changing any call sites.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3100',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
