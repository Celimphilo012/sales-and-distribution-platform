import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';

/// Email (SMTP) + SMS (httpSMS) delivery as `GET /settings/delivery` returns
/// it. The SMTP password and httpSMS API key are never sent back — only
/// [hasPassword] / [hasApiKey].
class DeliverySettings {
  const DeliverySettings({
    required this.emailEnabled,
    required this.host,
    required this.port,
    required this.secure,
    required this.user,
    required this.from,
    required this.hasPassword,
    required this.smsEnabled,
    required this.smsFrom,
    required this.hasApiKey,
    this.updatedAt,
    this.updatedByName,
  });

  /// true = SMTP really sends; false = messages only go to the server log.
  final bool emailEnabled;
  final String host;
  final int port;
  final bool secure;
  final String user;
  final String from;
  final bool hasPassword;

  /// true = httpSMS really sends; false = texts only go to the server log.
  final bool smsEnabled;
  final String smsFrom;
  final bool hasApiKey;
  final DateTime? updatedAt;
  final String? updatedByName;

  factory DeliverySettings.fromJson(Map<String, dynamic> json) {
    final email = json['email'] as Map<String, dynamic>;
    final sms = json['sms'] as Map<String, dynamic>;
    return DeliverySettings(
      emailEnabled: email['transport'] == 'smtp',
      host: email['host'] as String? ?? '',
      port: (email['port'] as num?)?.toInt() ?? 587,
      secure: email['secure'] as bool? ?? false,
      user: email['user'] as String? ?? '',
      from: email['from'] as String? ?? '',
      hasPassword: email['hasPassword'] as bool? ?? false,
      smsEnabled: sms['transport'] == 'httpsms',
      smsFrom: sms['from'] as String? ?? '',
      hasApiKey: sms['hasApiKey'] as bool? ?? false,
      updatedAt: json['updatedAt'] == null ? null : DateTime.parse(json['updatedAt'] as String),
      updatedByName: json['updatedByName'] as String?,
    );
  }
}

/// Result of a test send: `ok`, or the provider's error text.
class DeliveryTestResult {
  const DeliveryTestResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

class DeliverySettingsApi {
  DeliverySettingsApi(this._apiClient);

  final ApiClient _apiClient;

  Future<DeliverySettings> get() async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/settings/delivery'));
    return DeliverySettings.fromJson(response.data!);
  }

  /// A blank [password] / [apiKey] keeps the stored secret.
  Future<DeliverySettings> save({
    required bool emailEnabled,
    required String host,
    required int port,
    required bool secure,
    required String user,
    required String password,
    required String from,
    required bool smsEnabled,
    required String apiKey,
    required String smsFrom,
  }) async {
    final response = await _apiClient.guard(
      (dio) => dio.put<Map<String, dynamic>>(
        '/settings/delivery',
        data: {
          'email': {
            'transport': emailEnabled ? 'smtp' : 'log',
            'host': host,
            'port': port,
            'secure': secure,
            'user': user,
            'pass': password,
            'from': from,
          },
          'sms': {'transport': smsEnabled ? 'httpsms' : 'log', 'apiKey': apiKey, 'from': smsFrom},
        },
      ),
    );
    return DeliverySettings.fromJson(response.data!);
  }

  /// [channel]: `EMAIL` or `SMS`; [to]: an email address or +country phone number.
  Future<DeliveryTestResult> sendTest({required String channel, required String to}) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>('/settings/delivery/test', data: {'channel': channel, 'to': to}),
    );
    final data = response.data!;
    return DeliveryTestResult(ok: data['ok'] == true, error: data['error'] as String?);
  }
}

final deliverySettingsApiProvider = Provider<DeliverySettingsApi>(
  (ref) => DeliverySettingsApi(ref.watch(apiClientProvider)),
);

final deliverySettingsProvider = FutureProvider.autoDispose<DeliverySettings>((ref) {
  return ref.watch(deliverySettingsApiProvider).get();
});
