import 'app_user.dart';

/// Auth status. F1 only ever reaches [unauthenticated] or [authenticated]
/// via the placeholder login screen — nothing calls the backend yet.
enum AuthStatus { unauthenticated, authenticated }

class AuthState {
  const AuthState({required this.status, this.user});

  const AuthState.unauthenticated() : status = AuthStatus.unauthenticated, user = null;

  const AuthState.authenticated(AppUser this.user) : status = AuthStatus.authenticated;

  final AuthStatus status;
  final AppUser? user;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
