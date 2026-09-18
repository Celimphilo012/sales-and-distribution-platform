import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted storage for credentials (access/refresh tokens). Never use
/// [sharedPreferencesProvider] for these — that's plain text.
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());
