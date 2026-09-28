/// Static, compile-time app configuration.
///
/// This app talks only to the ordering system's own API. The default points at
/// `/ordering-backend` (Node.js + Express, port 3300) — not the older NestJS
/// `/backend` on 3000. Override with `--dart-define=API_BASE_URL=...` for
/// other environments without changing any call sites.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3300',
  );

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);
}
