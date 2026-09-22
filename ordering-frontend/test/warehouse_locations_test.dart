import 'package:flutter_test/flutter_test.dart';

import 'package:ordering_frontend/features/warehouse_locations/domain/warehouse_locations.dart';

WarehouseLocation _loc(String id, String? parent, String name, String code, {String wh = 'w1', bool active = true}) =>
    WarehouseLocation(
      id: id,
      warehouseId: wh,
      parentId: parent,
      name: name,
      code: code,
      locationType: 'X',
      isActive: active,
    );

void main() {
  final tree = WarehouseLocations(
    warehouses: const [
      WarehouseRef(id: 'w1', name: 'Mbabane Central Distribution Warehouse', code: 'MB', isActive: true),
    ],
    locations: [
      _loc('zone', null, 'Zone A — General Products', 'ZA'),
      _loc('rack1', 'zone', 'Rack 1', 'RA01'),
      _loc('r1l1', 'rack1', 'Level 1', 'RA01-L1'),
      _loc('r1l2', 'rack1', 'Level 2', 'RA01-L2'),
      _loc('bin', 'zone', 'Overflow Bin', 'BB01'),
      _loc('retired', 'rack1', 'Level 9', 'RA01-L9', active: false),
      // A location of a warehouse that is not in the active list (deactivated).
      _loc('ghost', null, 'Ghost Shelf', 'GS', wh: 'w-inactive'),
    ],
  );

  test('only leaves of a known active warehouse are offered (no parents, no inactive, no ghost warehouse)', () {
    final ids = tree.leafLocations.map((l) => l.id).toSet();
    expect(ids, {'r1l1', 'r1l2', 'bin'});
    expect(ids, isNot(contains('zone'))); // a parent — stock can't live there
    expect(ids, isNot(contains('rack1')));
    expect(ids, isNot(contains('retired'))); // inactive
    expect(ids, isNot(contains('ghost'))); // belongs to a deactivated warehouse
  });

  test('the full path resolves through any depth', () {
    expect(tree.pathLabel('r1l1'), 'Mbabane Central Distribution Warehouse › Zone A — General Products › Rack 1 › Level 1');
  });

  test('the leaf label leads with the distinguishing name and code', () {
    expect(tree.leafLabel(tree.byId('r1l1')!), 'Level 1 (RA01-L1)');
  });

  test('the parent path excludes the leaf itself', () {
    expect(tree.parentPathLabel('r1l1'), 'Mbabane Central Distribution Warehouse › Zone A — General Products › Rack 1');
    expect(tree.parentPathLabel('zone'), 'Mbabane Central Distribution Warehouse');
  });

  test('an unknown location falls back to its raw id instead of throwing', () {
    expect(tree.pathLabel('nope'), 'nope');
    expect(tree.parentPathLabel('nope'), '');
  });
}
