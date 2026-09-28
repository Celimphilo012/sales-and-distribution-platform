import 'package:dio/dio.dart';

/// What the backend says when an action needs a one-time code
/// (HTTP 428 `{ otpRequired, action, targetId, availableChannels, defaultChannel, message }`).
class OtpRequirement {
  const OtpRequirement({
    required this.action,
    required this.message,
    required this.availableChannels,
    required this.defaultChannel,
    this.targetId,
  });

  final String action;
  final String? targetId;
  final String message;

  /// Some of `EMAIL`, `SMS`, `TOTP` (authenticator app).
  final List<String> availableChannels;
  final String defaultChannel;

  factory OtpRequirement.fromJson(Map<String, dynamic> json) {
    final channels = (json['availableChannels'] as List<dynamic>? ?? const ['EMAIL']).cast<String>();
    return OtpRequirement(
      action: json['action'] as String,
      targetId: json['targetId'] as String?,
      message: json['message'] as String? ?? 'Confirm this action with a one-time code.',
      availableChannels: channels,
      defaultChannel: json['defaultChannel'] as String? ?? channels.first,
    );
  }
}

/// A code that was sent (or, for the authenticator app, opened): `POST /auth/otp`'s answer.
class OtpChallenge {
  const OtpChallenge({required this.challengeId, required this.channel, required this.destination});

  final String challengeId;
  final String channel;

  /// Masked, e.g. `j•••e@example.com`, `+268•••••456`, or "your authenticator app".
  final String destination;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) => OtpChallenge(
    challengeId: json['challengeId'] as String,
    channel: json['channel'] as String,
    destination: json['destination'] as String? ?? '',
  );
}

/// Asks the backend for a code on [channel]. Throws [DioException] on failure.
typedef OtpCodeRequester = Future<OtpChallenge> Function(String channel);

/// Re-sends the original request with the code. Returns `null` when that
/// settled the request (it succeeded, or failed for a reason other than the
/// code — either way the prompt should close), or an error message to show
/// inline when the code itself was wrong/expired and the user can retry.
typedef OtpAttempt = Future<String?> Function(String challengeId, String code);

/// Shows the code prompt. Completes once the prompt is closed; `false` means
/// the user cancelled.
typedef OtpPrompt = Future<bool> Function(OtpRequirement requirement, OtpCodeRequester requestCode, OtpAttempt attempt);

/// Turns a 428 "confirm with a one-time code" into a prompt and a retry, so
/// no screen needs to know which actions are protected: the approve /
/// submit / deactivate button just awaits its request as before, and this
/// interceptor inserts the confirmation step in between.
///
/// Retries go through [mainDio] (so the auth + refresh interceptors still
/// apply) carrying `X-OTP-Challenge` / `X-OTP-Code`. Multipart bodies can't
/// be re-sent, so those pass through untouched (no protected route takes one).
class OtpInterceptor extends Interceptor {
  OtpInterceptor({required Dio mainDio, required OtpPrompt prompt}) : _mainDio = mainDio, _prompt = prompt;

  final Dio _mainDio;
  final OtpPrompt _prompt;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final data = err.response?.data;
    final options = err.requestOptions;
    final needsCode =
        err.response?.statusCode == 428 && data is Map && data['otpRequired'] == true && options.data is! FormData;
    if (!needsCode || options.extra['otpRetry'] == true) {
      handler.next(err);
      return;
    }

    final requirement = OtpRequirement.fromJson(Map<String, dynamic>.from(data));
    Response<dynamic>? settled;
    DioException? failed;

    Future<OtpChallenge> requestCode(String channel) async {
      final response = await _mainDio.post<Map<String, dynamic>>(
        '/auth/otp',
        data: {'action': requirement.action, 'targetId': requirement.targetId, 'channel': channel},
      );
      return OtpChallenge.fromJson(response.data!);
    }

    Future<String?> attempt(String challengeId, String code) async {
      final retry = options.copyWith(
        headers: {...options.headers, 'X-OTP-Challenge': challengeId, 'X-OTP-Code': code},
        extra: {...options.extra, 'otpRetry': true},
      );
      try {
        settled = await _mainDio.fetch<dynamic>(retry);
        return null;
      } on DioException catch (retryError) {
        final body = retryError.response?.data;
        if (retryError.response?.statusCode == 403 && body is Map && body['otpInvalid'] == true) {
          return body['message'] as String? ?? 'That code is not valid.';
        }
        failed = retryError;
        return null;
      }
    }

    await _prompt(requirement, requestCode, attempt);

    if (settled != null) {
      handler.resolve(settled!);
    } else if (failed != null) {
      handler.next(failed!);
    } else {
      handler.next(err); // cancelled — surfaces as ConfirmationRequiredError
    }
  }
}
