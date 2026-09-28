import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../persistence/secure_storage_provider.dart';
import '../../shared/widgets/otp_confirm_dialog.dart';
import 'api_client.dart';
import 'auth_token_store.dart';

final authTokenStoreProvider = Provider<AuthTokenStore>((ref) {
  return AuthTokenStore(ref.watch(secureStorageProvider));
});

/// The shared [ApiClient] every feature call goes through. Wired so that a
/// refresh failure (expired refresh token, revoked session) routes back
/// into [AuthNotifier] to clear state — go_router's redirect then takes the
/// user to `/login` on its own.
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenStore = ref.watch(authTokenStoreProvider);
  return ApiClient(
    tokenStore,
    onRefreshFailed: () => ref.read(authProvider.notifier).handleSessionExpired(),
    otpPrompt: showOtpPrompt,
  );
});
