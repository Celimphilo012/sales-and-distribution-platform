import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/features/products/domain/product.dart';

void main() {
  group('ProductCategoryRef.displayLabel', () {
    test('a top-level category shows just its own name', () {
      const ref = ProductCategoryRef(id: 'c1', name: 'Household', workstreamId: 'w1');
      expect(ref.displayLabel, 'Household');
    });

    test('a sub-category shows "Parent (Sub-category)"', () {
      const ref = ProductCategoryRef(
        id: 'c2',
        name: 'Face Cream',
        workstreamId: 'w1',
        parent: ProductCategoryParentRef(id: 'c1', name: 'Skincare'),
      );
      expect(ref.displayLabel, 'Skincare (Face Cream)');
    });

    test('parses the parent out of a real backend-shaped JSON payload', () {
      final ref = ProductCategoryRef.fromJson({
        'id': 'c2',
        'name': 'Face Cream',
        'workstreamId': 'w1',
        'workstream': {'id': 'w1', 'name': 'Retail', 'code': 'RETAIL'},
        'parent': {'id': 'c1', 'name': 'Skincare'},
      });
      expect(ref.displayLabel, 'Skincare (Face Cream)');
      expect(ref.parent?.id, 'c1');
    });

    test('a category with no parent in JSON parses to null, not a crash', () {
      final ref = ProductCategoryRef.fromJson({'id': 'c1', 'name': 'Household', 'workstreamId': 'w1'});
      expect(ref.parent, isNull);
      expect(ref.displayLabel, 'Household');
    });
  });
}
