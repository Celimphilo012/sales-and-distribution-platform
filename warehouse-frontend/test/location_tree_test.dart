import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/features/locations/domain/location.dart';
import 'package:warehouse_frontend/features/locations/domain/location_tree.dart';

Location _loc(String id, String name, String code, {String? parentId, bool isActive = true}) {
  final now = DateTime(2026, 1, 1);
  return Location(
    id: id,
    warehouseId: 'wh-1',
    parentId: parentId,
    name: name,
    code: code,
    locationType: 'OTHER',
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  // Zone(z) -> Aisle(a) -> Rack(r) -> Level(l) -> Bin(b) — 5 levels, plus a
  // second warehouse root to prove multiple roots are handled.
  final zone = _loc('z', 'Zone A', 'Z-A');
  final aisle = _loc('a', 'Aisle 1', 'Z-A-1', parentId: 'z');
  final rack = _loc('r', 'Rack 1', 'Z-A-1-R1', parentId: 'a');
  final level = _loc('l', 'Level 1', 'Z-A-1-R1-L1', parentId: 'r');
  final bin = _loc('b', 'Bin 1', 'Z-A-1-R1-L1-B1', parentId: 'l');
  final secondRoot = _loc('z2', 'Zone B', 'Z-B');
  final flat = [bin, level, rack, aisle, zone, secondRoot]; // deliberately unordered

  test('buildLocationTree nests by parentId to unlimited depth and sorts roots by name', () {
    final tree = buildLocationTree(flat);

    expect(tree.map((n) => n.location.id), ['z', 'z2']); // sorted by name: Zone A, Zone B
    expect(tree.first.depth, 0);
    expect(tree.first.children.single.location.id, 'a');
    expect(tree.first.children.single.depth, 1);
    expect(tree.first.children.single.children.single.location.id, 'r');
    expect(tree.first.children.single.children.single.children.single.location.id, 'l');
    expect(tree.first.children.single.children.single.children.single.children.single.location.id, 'b');
    expect(tree.first.children.single.children.single.children.single.children.single.depth, 4);
  });

  test('flattenLocationTree is depth-first across multiple roots', () {
    final tree = buildLocationTree(flat);
    final result = flattenLocationTree(tree);
    expect(result.map((n) => n.location.id), ['z', 'a', 'r', 'l', 'b', 'z2']);
  });

  test('locationDescendantIds includes the node itself and every nested descendant', () {
    final tree = buildLocationTree(flat);
    expect(locationDescendantIds(tree, 'a'), {'a', 'r', 'l', 'b'});
    expect(locationDescendantIds(tree, 'b'), {'b'});
    expect(locationDescendantIds(tree, 'z2'), {'z2'});
  });

  test('locationDescendantIds is empty for an unknown id', () {
    final tree = buildLocationTree(flat);
    expect(locationDescendantIds(tree, 'nope'), isEmpty);
  });

  test('filterLocationTree keeps a matched node plus its full original subtree', () {
    final tree = buildLocationTree(flat);
    final filtered = filterLocationTree(tree, 'rack');

    // Rack matched -> Zone A (ancestor path) -> Aisle 1 (ancestor path) -> Rack 1 (match, full subtree kept)
    expect(filtered.map((n) => n.location.id), ['z']);
    expect(filtered.first.children.map((n) => n.location.id), ['a']);
    final matchedRack = filtered.first.children.first.children.first;
    expect(matchedRack.location.id, 'r');
    expect(matchedRack.children.single.location.id, 'l');
    expect(matchedRack.children.single.children.single.location.id, 'b');
  });

  test('filterLocationTree matches by code too, and excludes non-matching branches', () {
    final tree = buildLocationTree(flat);
    final filtered = filterLocationTree(tree, 'Z-B');
    expect(filtered.map((n) => n.location.id), ['z2']);
  });

  test('filterLocationTree with a blank query returns the tree unchanged', () {
    final tree = buildLocationTree(flat);
    expect(filterLocationTree(tree, '   '), same(tree));
  });

  test('filterLocationTree with no match returns an empty forest', () {
    final tree = buildLocationTree(flat);
    expect(filterLocationTree(tree, 'nonexistent'), isEmpty);
  });
}
