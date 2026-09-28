import 'app_user.dart';

/// Auth status. [mfaPending] = the password was right but the account has
/// sign-in verification on, so a code is still needed before any tokens exist.
enum AuthStatus { unauthenticated, mfaPending, authenticated }

/// The second sign-in step, as `POST /auth/login` (or `/auth/mfa/resend`) returned it.
class MfaChallenge {
  const MfaChallenge({
    required this.challengeId,
    required this.channel,
    required this.destination,
    required this.availableChannels,
  });

  final String challengeId;

  /// `EMAIL`, `SMS` or `TOTP` (authenticator app).
  final String channel;

  /// Masked address/number the code went to, or "your authenticator app".
  final String destination;

  /// Channels the user may switch the code to (EMAIL/SMS users can swap between the two).
  final List<String> availableChannels;

  factory MfaChallenge.fromJson(Map<String, dynamic> json) => MfaChallenge(
    challengeId: json['challengeId'] as String,
    channel: json['channel'] as String,
    destination: json['destination'] as String? ?? '',
    availableChannels: (json['availableChannels'] as List<dynamic>? ?? const []).cast<String>(),
  );
}

class AuthState {
  const AuthState({required this.status, this.user, this.mfa});

  const AuthState.unauthenticated() : status = AuthStatus.unauthenticated, user = null, mfa = null;

  const AuthState.mfaPending(MfaChallenge this.mfa) : status = AuthStatus.mfaPending, user = null;

  const AuthState.authenticated(AppUser this.user) : status = AuthStatus.authenticated, mfa = null;

  final AuthStatus status;
  final AppUser? user;
  final MfaChallenge? mfa;

  bool get isAuthenticated => status == AuthStatus.authenticated;
}
