import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_frontend/core/network/auth_token_store.dart';
import 'package:warehouse_frontend/core/network/refresh_interceptor.dart';

/// In-memory token store (no platform secure storage in unit tests).
class _MemoryTokenStore extends AuthTokenStore {
  _MemoryTokenStore() : super(const FlutterSecureStorage());

  String? access = 'expired-access';
  String? refresh = 'refresh-1';

  @override
  Future<String?> readAccessToken() async => access;

  @override
  Future<String?> readRefreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String accessToken, required String refreshToken}) async {
    access = accessToken;
    refresh = refreshToken;
  }

  @override
  Future<void> clear() async => access = refresh = null;
}

/// Fake server: the first upload is refused (expired token), /auth/refresh hands out a new
/// token, and the retried upload succeeds — recording the multipart body it received.
class _FakeServer implements HttpClientAdapter {
  int uploads = 0;
  final receivedBodies = <String>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    ResponseBody json(int status, Object body) =>
        ResponseBody.fromString(jsonEncode(body), status, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });

    if (options.path == '/auth/refresh') {
      return json(200, {'accessToken': 'fresh-access', 'refreshToken': 'refresh-2'});
    }
    uploads++;
    if (options.headers['Authorization'] != 'Bearer fresh-access') {
      return json(401, {'message': 'Invalid or expired access token'});
    }
    receivedBodies.add(utf8.decode(bytes, allowMalformed: true));
    return json(201, {'id': 'adj-1'});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('an expired token on a multipart upload refreshes and re-sends the SAME form', () async {
    final server = _FakeServer();
    final store = _MemoryTokenStore();
    final dio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = server;
    final refreshDio = Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = server;
    dio.interceptors.addAll([
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          options.headers['Authorization'] = 'Bearer ${await store.readAccessToken()}';
          handler.next(options);
        },
      ),
      RefreshInterceptor(tokenStore: store, mainDio: dio, refreshDio: refreshDio, onRefreshFailed: () async {}),
    ]);

    final response = await dio.post<Map<String, dynamic>>(
      '/inventory/adjustments',
      data: FormData.fromMap({
        'reason': 'broken seal',
        'photo': MultipartFile.fromBytes([1, 2, 3], filename: 'photo.png'),
      }),
    );

    expect(response.statusCode, 201);
    expect(server.uploads, 2, reason: 'refused once, then retried');
    expect(store.access, 'fresh-access');
    expect(server.receivedBodies.single, contains('broken seal'));
    expect(server.receivedBodies.single, contains('photo.png'));
  });
}
