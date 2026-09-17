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
