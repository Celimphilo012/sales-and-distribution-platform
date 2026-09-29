import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// What `POST /auth/mfa/setup` returns. [secret]/[otpauthUrl] are only set
/// for the authenticator app — shown ONCE, to scan or type into the app.
class MfaSetupStart {
  const MfaSetupStart({
    required this.challengeId,
    required this.channel,
    required this.destination,
    this.secret,
    this.otpauthUrl,
  });

  final String challengeId;
  final String channel;
  final String destination;
  final String? secret;
  final String? otpauthUrl;

  factory MfaSetupStart.fromJson(Map<String, dynamic> json) => MfaSetupStart(
    challengeId: json['challengeId'] as String,
    channel: json['channel'] as String,
    destination: json['destination'] as String? ?? '',
    secret: json['secret'] as String?,
    otpauthUrl: json['otpauthUrl'] as String?,
  );
}

/// The signed-in user's OWN account: contact details, notification channel,
/// and sign-in verification (MFA). Every call here is
/// self-service — no admin permission involved.
class AccountApi {
  AccountApi(this._apiClient);

  final ApiClient _apiClient;

  /// `PATCH /users/me`. [phone] `''` clears it; null leaves it unchanged.
  Future<void> updateProfile({String? phone, String? notifyChannel}) async {
    await _apiClient.guard(
      (dio) => dio.patch<Map<String, dynamic>>('/users/me', data: {'phone': ?phone, 'notifyChannel': ?notifyChannel}),
    );
  }

  /// [method]: `EMAIL`, `SMS` or `TOTP`. Email/SMS: a code is sent there now.
  Future<MfaSetupStart> startMfaSetup(String method) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/auth/mfa/setup', data: {'method': method}),
    );
    return MfaSetupStart.fromJson(response.data!);
  }

  /// Proves the code arrives / the app is set up; switches the method on.
  Future<void> confirmMfaSetup({required String challengeId, required String code}) async {
    await _apiClient.guard(
      (dio) =>
          dio.post<Map<String, dynamic>>('/auth/mfa/setup/confirm', data: {'challengeId': challengeId, 'code': code}),
    );
  }

  /// Turning verification off is itself confirmed with a one-time code — the
  /// API client's OTP prompt appears automatically.
  Future<void> disableMfa() async {
    await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/auth/mfa/disable'));
  }
}

final accountApiProvider = Provider<AccountApi>((ref) => AccountApi(ref.watch(apiClientProvider)));
