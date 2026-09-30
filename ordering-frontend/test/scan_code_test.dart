import 'package:flutter_test/flutter_test.dart';
import 'package:ordering_frontend/shared/scan/scan_code.dart';

typedef _Product = ({String id, String sku});

void main() {
  const catalogue = <_Product>[(id: 'wh-1', sku: 'PC-001'), (id: 'wh-2', sku: 'HH-002')];
  _Product? scan(String raw) => ScanCode.parse(raw).match(ScanKind.product, catalogue, id: (p) => p.id, code: (p) => p.sku);

  test('a warehouse product label adds that product (by its permanent id)', () {
    expect(scan('WH:P:wh-2')?.sku, 'HH-002');
  });

  test('a SKU barcode or a typed SKU works too, ignoring case', () {
    expect(scan('pc-001')?.id, 'wh-1');
  });

  test('location labels and unknown codes add nothing', () {
    expect(scan('WH:L:wh-1'), isNull);
    expect(scan('ZZ-404'), isNull);
    expect(scan('   '), isNull);
  });
}
