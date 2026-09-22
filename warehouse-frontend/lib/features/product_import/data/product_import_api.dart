import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_client.dart';
import '../domain/import_models.dart';

/// All product-import API calls — template download, preview (upload +
/// validate, no writes), confirm (commits the session's writes). Mirrors
/// `ProductsApi`'s repository pattern: screens never touch [ApiClient] or
/// raw multipart plumbing directly.
class ProductImportApi {
  ProductImportApi(this._apiClient);

  final ApiClient _apiClient;

  /// `GET /products/import/template` — the backend streams a generated
  /// `.xlsx` as raw bytes (`res.send(buffer)`), not JSON.
  Future<Uint8List> downloadTemplate() async {
    final response = await _apiClient.guard(
      (dio) => dio.get<List<int>>(
        '/products/import/template',
        options: Options(responseType: ResponseType.bytes),
      ),
    );
    return Uint8List.fromList(response.data!);
  }

  /// `POST /products/import/preview` — multipart upload of the picked
  /// spreadsheet. Validates and stages the rows server-side (session-keyed,
  /// 15-min TTL) without writing anything yet.
  Future<ImportPreviewResult> preview(Uint8List fileBytes, String fileName) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/products/import/preview',
        data: FormData.fromMap({'file': MultipartFile.fromBytes(fileBytes, filename: fileName)}),
      ),
    );
    return ImportPreviewResult.fromJson(response.data!);
  }

  /// `POST /products/import/confirm` — commits the staged session (creates +
  /// updates), re-validating each row hasn't gone stale since preview.
  Future<ImportConfirmResult> confirm(String importSessionId) async {
    final response = await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/products/import/confirm',
        data: {'importSessionId': importSessionId},
      ),
    );
    return ImportConfirmResult.fromJson(response.data!);
  }
}
