/// SUGGESTED `location_type` labels (§G / the real `CreateLocationDto`'s own
/// doc comment: "Free-form label ... Not a structural constraint — any
/// string is accepted"). This list drives the picker's dropdown options for
/// convenience only — the picker also accepts a free-typed custom value, so
/// nothing in this app ever rejects a `locationType` the backend would
/// accept, and no fixed hierarchy of these is ever assumed.
const List<String> kSuggestedLocationTypes = [
  'WAREHOUSE',
  'ZONE',
  'AISLE',
  'RACK',
  'SHELF',
  'LEVEL',
  'BIN',
  'PALLET',
  'CAGE',
  'ROOM',
  'FLOOR',
  'OTHER',
];

/// A purely UI-side "largest container" -> "smallest slot" ordering, used
/// ONLY to narrow which of [kSuggestedLocationTypes] the Type dropdown
/// offers FIRST when adding a CHILD under a location of a known type — so
/// e.g. a Rack isn't suggested "Warehouse" or "Room" as a child type. This
/// is a suggestion-ordering hint only: it never blocks a value ("Custom…"
/// and the full list stay reachable) and the backend enforces no hierarchy
/// at all (§G / rule 5 — `location_type` is a free label, never a
/// structural constraint) — unlimited depth, any type anywhere.
const List<String> _locationTypeTierOrder = [
  'WAREHOUSE',
  'FLOOR',
  'ROOM',
  'ZONE',
  'AISLE',
  'RACK',
  'SHELF',
  'CAGE',
  'LEVEL',
  'BIN',
  'PALLET',
  'OTHER',
];

/// Suggested types for a child of a location typed [parentType]: every
/// tiered type STRICTLY deeper than the parent's (e.g. a Rack's child is
/// suggested Shelf/Cage/Level/Bin/Pallet/Other, never Warehouse/Room/Zone/
/// Aisle/Rack itself). Falls back to the full [kSuggestedLocationTypes]
/// list when [parentType] is `null`, a custom/free-typed value, or the
/// deepest known tier (`OTHER`) — there's nothing to narrow against.
List<String> suggestedChildLocationTypes(String? parentType) {
  final index = parentType == null ? -1 : _locationTypeTierOrder.indexOf(parentType);
  if (index == -1) return kSuggestedLocationTypes;
  final narrowed = _locationTypeTierOrder.sublist(index + 1);
  return narrowed.isEmpty ? kSuggestedLocationTypes : narrowed;
}
