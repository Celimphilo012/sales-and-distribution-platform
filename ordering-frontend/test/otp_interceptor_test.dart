import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ordering_frontend/core/network/otp_interceptor.dart';

/// Fake server: `/orders/o1/approve` answers 428 until it gets the right
/// X-OTP-* headers; `/auth/otp` hands out challenge "c1".
class _FakeServer implements HttpClientAdapter {
  final codeRequests = <Map<String, dynamic>>[];
  String? seenCode;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    ResponseBody json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

    if (options.path == '/auth/otp') {
      codeRequests.add(Map<String, dynamic>.from(options.data as Map));
      return json(201, {'challengeId': 'c1', 'channel': 'EMAIL', 'destination': 'a•••@example.com'});
    }
    final code = options.headers['X-OTP-Code'];
    if (options.headers['X-OTP-Challenge'] == 'c1' && code == '123456') {
      seenCode = code as String;
      return json(201, {'id': 'o1', 'status': 'APPROVED'});
    }
    if (code != null) return json(403, {'otpInvalid': true, 'message': 'Incorrect code — check it and try again'});
    return json(428, {
      'otpRequired': true,
      'action': 'order.approve',
      'targetId': 'o1',
      'availableChannels': ['EMAIL', 'SMS'],
      'defaultChannel': 'EMAIL',
      'message': 'Confirm with a one-time code to approve an order',
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeServer server;
  late Dio dio;

  Dio build(OtpPrompt prompt) {
    server = _FakeServer();
    dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = server;
    dio.interceptors.add(OtpInterceptor(mainDio: dio, prompt: prompt));
    return dio;
  }

  test('a 428 prompts for a code, requests it for that action + order, and retries with it', () async {
    final errors = <String?>[];
    build((requirement, requestCode, attempt) async {
      expect(requirement.action, 'order.approve');
      expect(requirement.targetId, 'o1');
      expect(requirement.availableChannels, ['EMAIL', 'SMS']);
      final challenge = await requestCode('SMS');
      errors.add(await attempt(challenge.challengeId, '000000')); // wrong: shown inline, prompt stays
      errors.add(await attempt(challenge.challengeId, '123456'));
      return true;
    });

    final response = await dio.post<Map<String, dynamic>>('/orders/o1/approve', data: {});
    expect(response.statusCode, 201);
    expect(response.data!['status'], 'APPROVED');
    expect(server.codeRequests.single, {'action': 'order.approve', 'targetId': 'o1', 'channel': 'SMS'});
    expect(errors, ['Incorrect code — check it and try again', null]);
    expect(server.seenCode, '123456');
  });

  test('closing the prompt leaves the original 428 (nothing was done)', () async {
    build((requirement, requestCode, attempt) async => false);
    await expectLater(
      dio.post<dynamic>('/orders/o1/approve', data: {}),
      throwsA(isA<DioException>().having((e) => e.response?.statusCode, 'status', 428)),
    );
    expect(server.codeRequests, isEmpty);
  });
}
