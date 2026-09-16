import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/features/products/domain/products_filter.dart';

void main() {
  test('default filter sends no query params (backend defaults to ACTIVE only)', () {
    const filter = ProductsFilter();
    expect(filter.toQueryParameters(), isEmpty);
    expect(filter.statusFilter, ProductStatusFilter.active);
  });

  test('setting statusFilter to inactive sends an explicit status param', () {
    final filter = const ProductsFilter().copyWith(statusFilter: ProductStatusFilter.inactive);
    expect(filter.toQueryParameters(), {'status': 'INACTIVE'});
  });

  test('setting statusFilter to all sends includeInactive, no status', () {
    final filter = const ProductsFilter().copyWith(statusFilter: ProductStatusFilter.all);
    expect(filter.toQueryParameters(), {'includeInactive': true});
    expect(filter.status, isNull);
  });

  test('search is trimmed and omitted when blank', () {
    final filter = const ProductsFilter().copyWith(search: '  cola  ');
    expect(filter.toQueryParameters(), {'search': 'cola'});

    final blank = const ProductsFilter().copyWith(search: '   ');
    expect(blank.toQueryParameters(), isEmpty);
  });

  test('categoryId round-trips through copyWith including clearing to null', () {
    final withCategory = const ProductsFilter().copyWith(categoryId: 'cat-1');
    expect(withCategory.toQueryParameters(), {'categoryId': 'cat-1'});

    final cleared = withCategory.copyWith(categoryId: null);
    expect(cleared.toQueryParameters(), isEmpty);
  });

  test('combining search, category and status filters all params together', () {
    final filter = const ProductsFilter().copyWith(
      search: 'cola',
      categoryId: 'cat-1',
      statusFilter: ProductStatusFilter.active,
    );
    expect(filter.toQueryParameters(), {'search': 'cola', 'categoryId': 'cat-1', 'status': 'ACTIVE'});
  });
}
