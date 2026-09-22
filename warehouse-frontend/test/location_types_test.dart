import 'package:flutter_test/flutter_test.dart';

import 'package:warehouse_frontend/features/locations/domain/location_types.dart';

void main() {
  group('suggestedChildLocationTypes', () {
    test('a Rack only suggests types deeper than Rack — never Warehouse/Room/Zone/Aisle/Rack itself', () {
      final suggested = suggestedChildLocationTypes('RACK');
      expect(suggested, ['SHELF', 'CAGE', 'LEVEL', 'BIN', 'PALLET', 'OTHER']);
      expect(suggested, isNot(contains('WAREHOUSE')));
      expect(suggested, isNot(contains('ROOM')));
      expect(suggested, isNot(contains('ZONE')));
      expect(suggested, isNot(contains('RACK')));
    });

    test('a Level only suggests Bin/Pallet/Other', () {
      expect(suggestedChildLocationTypes('LEVEL'), ['BIN', 'PALLET', 'OTHER']);
    });

    test('a root-level Zone still excludes bigger containers (Warehouse/Floor/Room) but keeps Aisle downward', () {
      final suggested = suggestedChildLocationTypes('ZONE');
      expect(suggested, ['AISLE', 'RACK', 'SHELF', 'CAGE', 'LEVEL', 'BIN', 'PALLET', 'OTHER']);
    });

    test('every suggested child type is still a member of the full suggestion list (nothing invented)', () {
      for (final parent in ['WAREHOUSE', 'ZONE', 'AISLE', 'RACK', 'SHELF', 'LEVEL', 'BIN', 'PALLET', 'CAGE', 'ROOM', 'FLOOR']) {
        for (final child in suggestedChildLocationTypes(parent)) {
          expect(kSuggestedLocationTypes, contains(child), reason: 'child "$child" of "$parent" should be a real suggested type');
        }
      }
    });

    test('falls back to the full list for a null parent (root location)', () {
      expect(suggestedChildLocationTypes(null), kSuggestedLocationTypes);
    });

    test('falls back to the full list for a custom/unrecognised parent type', () {
      expect(suggestedChildLocationTypes('WALK-IN FREEZER'), kSuggestedLocationTypes);
    });

    test('falls back to the full list for OTHER (the deepest known tier — nothing to narrow to)', () {
      expect(suggestedChildLocationTypes('OTHER'), kSuggestedLocationTypes);
    });

    test('narrowing never blocks anything the backend would accept — every suggestion is still just a label', () {
      // The whole point of rule 5: no suggestion list here should ever be
      // read as a structural constraint. This test exists to make that
      // intent explicit, not because narrowing could technically reject a
      // value (the dropdown always offers "Custom…" alongside it — see the
      // widget itself).
      expect(suggestedChildLocationTypes('RACK'), isNotEmpty);
    });
  });
}
