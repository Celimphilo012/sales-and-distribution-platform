import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/features/product_import/domain/import_models.dart';

/// Real `POST /products/import/preview` response, captured live against a
/// running warehouse backend (2 create rows, 3 rejected rows — missing
/// price, unknown workstream, comma-decimal price). Not a guess at the
/// shape: this is the actual JSON the backend sent.
const _realCreateAndRejectResponse = '''
{
  "importSessionId": "4466e3a6-5d99-4fcd-955c-ac5c9669c393",
  "fileName": "import1.csv",
  "toCreate": [
    {
      "rowNumber": 2,
      "sku": "IMPORT-UI-TEST-1",
      "name": "Import UI Test Widget",
      "description": "A frontend verification row",
      "workstreamId": "c3844c82-6751-437e-92f4-56ef2bd37abc",
      "workstreamCode": "OR-45",
      "workstreamName": "Orijins",
      "categoryId": "7cc80649-4946-40e0-9911-f36a0184f08e",
      "categoryName": "Accessories",
      "sellingPrice": 12.5,
      "costPrice": 7,
      "uom": "EACH",
      "minStockLevel": 5,
      "attributes": []
    },
    {
      "rowNumber": 3,
      "sku": "IMPORT-UI-TEST-2",
      "name": "Import UI Test Soap",
      "description": "A frontend verification row",
      "workstreamId": "eae0e5aa-94b0-4f4f-bcac-97817ee17b40",
      "workstreamCode": "PR-22",
      "workstreamName": "Puer",
      "categoryId": "da5e8adc-9dc8-4e40-96c1-d39851f94862",
      "categoryName": "Personal Care",
      "sellingPrice": 8,
      "uom": "EACH",
      "minStockLevel": 2,
      "attributes": []
    }
  ],
  "toUpdate": [],
  "rejected": [
    { "rowNumber": 4, "sku": "IMPORT-UI-TEST-3", "reason": "Row 4: missing required field(s): selling_price" },
    { "rowNumber": 5, "sku": "IMPORT-UI-TEST-4", "reason": "Row 5: workstream_code \\"ZZZZ\\" does not exist or is not active" },
    { "rowNumber": 6, "sku": "IMPORT-UI-TEST-5", "reason": "Row 6: selling_price (\\"12,50\\") is not a valid number" }
  ],
  "summary": { "createCount": 2, "updateCount": 0, "rejectCount": 3, "totalRows": 5 }
}
''';

/// Real `POST /products/import/preview` response for an UPDATE row (same
/// SKU as above, price changed) — also captured live, including the
/// `changes[]` diff the backend computed.
const _realUpdateResponse = '''
{
  "importSessionId": "62856c30-c877-40b6-8c8d-92b97dee2d66",
  "fileName": "import2.csv",
  "toCreate": [],
  "toUpdate": [
    {
      "rowNumber": 2,
      "sku": "IMPORT-UI-TEST-1",
      "name": "Import UI Test Widget",
      "description": "A frontend verification row",
      "workstreamId": "c3844c82-6751-437e-92f4-56ef2bd37abc",
      "workstreamCode": "OR-45",
      "workstreamName": "Orijins",
      "categoryId": "7cc80649-4946-40e0-9911-f36a0184f08e",
      "categoryName": "Accessories",
      "sellingPrice": 15.75,
      "costPrice": 7,
      "uom": "EACH",
      "minStockLevel": 5,
      "attributes": [],
      "existingProductId": "8fcb3d96-ccef-4391-961b-2ae1e9a7fc80",
      "changes": [{ "field": "sellingPrice", "oldValue": 12.5, "newValue": 15.75 }]
    }
  ],
  "rejected": [],
  "summary": { "createCount": 0, "updateCount": 1, "rejectCount": 0, "totalRows": 1 }
}
''';

/// Real `POST /products/import/confirm` response for the create batch above.
const _realConfirmResponse = '{"created": 2, "updated": 0, "failed": []}';

void main() {
  group('ImportPreviewResult.fromJson against real backend payloads', () {
    test('parses a create+reject response exactly', () {
      final result = ImportPreviewResult.fromJson(jsonDecode(_realCreateAndRejectResponse) as Map<String, dynamic>);

      expect(result.toCreate, hasLength(2));
      expect(result.toUpdate, isEmpty);
      expect(result.rejected, hasLength(3));
      expect(result.summary.createCount, 2);
      expect(result.summary.rejectCount, 3);
      expect(result.summary.totalRows, 5);

      final widget = result.toCreate[0];
      expect(widget.sku, 'IMPORT-UI-TEST-1');
      expect(widget.workstreamName, 'Orijins');
      expect(widget.categoryName, 'Accessories');
      expect(widget.sellingPrice, 12.5);
      expect(widget.costPrice, 7);
      expect(widget.minStockLevel, 5);

      final soap = result.toCreate[1];
      expect(soap.sku, 'IMPORT-UI-TEST-2');
      expect(soap.costPrice, isNull); // omitted in the source row — stays optional, not coerced to 0

      expect(result.rejected[0].reason, contains('missing required field'));
      expect(result.rejected[1].reason, contains('ZZZZ'));
      expect(result.rejected[2].reason, contains('not a valid number'));
    });

    test('parses an update response with its changes[] diff exactly', () {
      final result = ImportPreviewResult.fromJson(jsonDecode(_realUpdateResponse) as Map<String, dynamic>);

      expect(result.toCreate, isEmpty);
      expect(result.toUpdate, hasLength(1));

      final update = result.toUpdate.single;
      expect(update.existingProductId, '8fcb3d96-ccef-4391-961b-2ae1e9a7fc80');
      expect(update.row.sku, 'IMPORT-UI-TEST-1');
      expect(update.row.sellingPrice, 15.75);
      expect(update.changes, hasLength(1));
      expect(update.changes.single.field, 'sellingPrice');
      expect(update.changes.single.oldValue, 12.5);
      expect(update.changes.single.newValue, 15.75);
    });
  });

  test('ImportConfirmResult.fromJson parses a real confirm response', () {
    final result = ImportConfirmResult.fromJson(jsonDecode(_realConfirmResponse) as Map<String, dynamic>);
    expect(result.created, 2);
    expect(result.updated, 0);
    expect(result.failed, isEmpty);
  });
}
