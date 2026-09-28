import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/providers.dart';
import 'app_user.dart';
import 'auth_state.dart';

/// Real auth state, backed by the NestJS API.
///
/// `build()` restores a session from the persisted refresh/access token on
/// app startup (so a page reload does not log the user out); [login] posts
/// real credentials to `/auth/login`; [logout] posts to `/auth/logout` and
/// clears storage; [handleSessionExpired] is called by [RefreshInterceptor]
/// when a silent refresh fails, so an expired session drops the user back
/// to `/login` without a manual API call from here.
///
/// The exposed state is `AsyncValue<AuthState>` so the login screen can
/// show a loading spinner during the call and a mapped [AppError] message
/// on failure, and the router can show a splash screen while the initial
/// session restore is in flight.
class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final tokenStore = ref.watch(authTokenStoreProvider);
    final accessToken = await tokenStore.readAccessToken();
    final refreshToken = await tokenStore.readRefreshToken();
    if (accessToken == null || refreshToken == null) {
      return const AuthState.unauthenticated();
    }

    try {
      final user = await _fetchCurrentUser();
      return AuthState.authenticated(user);
    } catch (_) {
      await tokenStore.clear();
      return const AuthState.unauthenticated();
    }
  }

  Future<void> login({required String email, required String password}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final apiClient = ref.read(apiClientProvider);
      final tokenStore = ref.read(authTokenStoreProvider);

      final response = await apiClient.guard(
        (dio) => dio.post<Map<String, dynamic>>('/auth/login', data: {'email': email, 'password': password}),
      );
      final data = response.data!;
      // Sign-in verification is on: no tokens yet, the login screen asks for the code.
      if (data['mfaRequired'] == true) return AuthState.mfaPending(MfaChallenge.fromJson(data));

      await tokenStore.saveTokens(
        accessToken: data['accessToken'] as String,
        refreshToken: data['refreshToken'] as String,
      );

      final user = await _fetchCurrentUser();
      return AuthState.authenticated(user);
    });
  }

  /// Finishes an MFA sign-in with the code. Throws [AppError] (e.g. a wrong
  /// code) WITHOUT touching state, so the code screen stays up for a retry
  /// instead of bouncing through the splash screen.
  Future<void> verifyMfa(String code) async {
    final challenge = state.value?.mfa;
    if (challenge == null) return;
    final apiClient = ref.read(apiClientProvider);
    final tokenStore = ref.read(authTokenStoreProvider);

    final response = await apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/auth/mfa/verify',
        data: {'challengeId': challenge.challengeId, 'code': code},
      ),
    );
    final data = response.data!;
    await tokenStore.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    state = AsyncValue.data(AuthState.authenticated(await _fetchCurrentUser()));
  }

  /// Sends a fresh sign-in code, optionally on the other channel (EMAIL <-> SMS).
  Future<void> resendMfa({String? channel}) async {
    final challenge = state.value?.mfa;
    if (challenge == null) return;
    final response = await ref.read(apiClientProvider).guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/auth/mfa/resend',
        data: {'challengeId': challenge.challengeId, 'channel': ?channel},
      ),
    );
    state = AsyncValue.data(AuthState.mfaPending(MfaChallenge.fromJson(response.data!)));
  }

  /// Back to the email/password form.
  void cancelMfa() => state = const AsyncValue.data(AuthState.unauthenticated());

  /// Re-reads `/auth/me` after the user changed their own profile or MFA settings.
  Future<void> refreshUser() async {
    if (!(state.value?.isAuthenticated ?? false)) return;
    state = AsyncValue.data(AuthState.authenticated(await _fetchCurrentUser()));
  }

  Future<void> logout() async {
    final tokenStore = ref.read(authTokenStoreProvider);
    final refreshToken = await tokenStore.readRefreshToken();
    if (refreshToken != null) {
      try {
        await ref.read(apiClientProvider).guard(
          (dio) => dio.post('/auth/logout', data: {'refreshToken': refreshToken}),
        );
      } catch (_) {
        // Logout is best-effort server-side; local state always clears.
      }
    }
    await tokenStore.clear();
    state = const AsyncValue.data(AuthState.unauthenticated());
  }

  /// Called by [RefreshInterceptor] when a silent token refresh fails (the
  /// refresh token is expired, revoked, or missing). Tokens are already
  /// cleared by the interceptor; this just drops local state so go_router's
  /// redirect sends the user back to `/login`.
  Future<void> handleSessionExpired() async {
    state = const AsyncValue.data(AuthState.unauthenticated());
  }

  /// `GET /auth/me` — the caller's own identity + flat, deduped effective
  /// permissions, resolved server-side the same way `PermissionGuard`
  /// resolves them. Needs no `roles.manage`/`users.manage`, so this works
  /// identically for every authenticated user, not just admins.
  Future<AppUser> _fetchCurrentUser() async {
    final apiClient = ref.read(apiClientProvider);

    final response = await apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/auth/me'));
    final me = response.data!;
    final permissions = (me['permissions'] as List).cast<String>();
    final roles = (me['roles'] as List<dynamic>? ?? const [])
        .map((r) => AppUserRoleRef.fromJson(r as Map<String, dynamic>))
        .toList();

    return AppUser(
      id: me['id'] as String,
      name: me['fullName'] as String,
      email: me['email'] as String,
      permissions: permissions.toSet(),
      roles: roles,
      status: me['status'] as String?,
      phone: me['phone'] as String?,
      notifyChannel: me['notifyChannel'] as String? ?? 'EMAIL',
      mfaMethod: me['mfaMethod'] as String? ?? 'NONE',
    );
  }
}

final authProvider = AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
