import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the access/refresh token pair in the platform's secure storage
/// (Keychain/Keystore on mobile, encrypted browser storage on web) — never
/// [shared_preferences], since these are credentials.
class AuthTokenStore {
  AuthTokenStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'auth.accessToken';
  static const _refreshTokenKey = 'auth.refreshToken';

  Future<String?> readAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> readRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> saveAccessToken(String accessToken) => _storage.write(key: _accessTokenKey, value: accessToken);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }
}
