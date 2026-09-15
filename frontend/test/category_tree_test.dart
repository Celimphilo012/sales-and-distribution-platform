import 'package:flutter_test/flutter_test.dart';

import 'package:distribution_platform/features/categories/domain/category.dart';
import 'package:distribution_platform/features/categories/domain/category_tree.dart';

void main() {
  const beverages = Category(id: 'bev', name: 'Beverages', isActive: true);
  const soda = Category(id: 'soda', name: 'Soda', parentId: 'bev', isActive: true);
  const cola = Category(id: 'cola', name: 'Cola', parentId: 'soda', isActive: true);
  const snacks = Category(id: 'snacks', name: 'Snacks', isActive: false);

  final flat = [snacks, beverages, soda, cola];

  test('buildCategoryTree nests by parentId and sorts siblings by name', () {
    final tree = buildCategoryTree(flat);

    expect(tree.map((n) => n.category.id), ['bev', 'snacks']);
    expect(tree.first.children.single.category.id, 'soda');
    expect(tree.first.children.single.children.single.category.id, 'cola');
    expect(tree.first.depth, 0);
    expect(tree.first.children.single.depth, 1);
    expect(tree.first.children.single.children.single.depth, 2);
  });

  test('flattenCategoryTree is depth-first', () {
    final tree = buildCategoryTree(flat);
    final result = flattenCategoryTree(tree);

    expect(result.map((n) => n.category.id), ['bev', 'soda', 'cola', 'snacks']);
  });

  test('descendantIds includes the category itself and every nested child', () {
    final tree = buildCategoryTree(flat);

    expect(descendantIds(tree, 'bev'), {'bev', 'soda', 'cola'});
    expect(descendantIds(tree, 'soda'), {'soda', 'cola'});
    expect(descendantIds(tree, 'cola'), {'cola'});
    expect(descendantIds(tree, 'snacks'), {'snacks'});
  });

  test('descendantIds is empty for an unknown id', () {
    final tree = buildCategoryTree(flat);
    expect(descendantIds(tree, 'nope'), isEmpty);
  });
}
