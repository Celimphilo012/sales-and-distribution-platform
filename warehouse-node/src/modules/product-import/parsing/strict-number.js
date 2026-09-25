"use strict";
exports.parseStrictNumber = parseStrictNumber;
exports.isBlankCell = isBlankCell;
// Strict numeric parsing for import cells — rule: "reject text-formatted,
// currency-prefixed, or comma-decimal values with a clear message per row".
// Deliberately NOT `Number(x)`: that coerces `''` -> 0, accepts hex
// (`'0x1A'` -> 26) and `'Infinity'`, and silently trims in ways that would
// let a currency-prefixed or comma-decimal value slip through as garbage
// instead of failing loudly. A single regex makes "valid number" mean
// exactly one thing: an optional leading minus, digits, an optional single
// decimal point with digits — nothing else.
const STRICT_NUMBER = /^-?\d+(\.\d+)?$/;
/**
 * Parses a spreadsheet cell into a number under the strict rule above.
 * Accepts a genuine numeric cell value as-is (exceljs gives xlsx numeric
 * cells back as JS `number`). Returns `null` for anything that isn't
 * strictly numeric — the caller decides whether that's "missing" (blank) or
 * "invalid" (non-numeric text) and phrases the row's rejection accordingly.
 */
function parseStrictNumber(raw) {
    if (typeof raw === 'number')
        return Number.isFinite(raw) ? raw : null;
    if (raw === null || raw === undefined)
        return null;
    const text = String(raw).trim();
    if (!STRICT_NUMBER.test(text))
        return null;
    return Number(text);
}
/** True when the cell is empty/blank — distinct from "present but invalid". */
function isBlankCell(raw) {
    if (raw === null || raw === undefined)
        return true;
    return String(raw).trim() === '';
}
