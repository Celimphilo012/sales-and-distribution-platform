"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
exports.buildImportTemplate = buildImportTemplate;
const exceljs_1 = __importDefault(require("exceljs"));
// The FIXED columns, in order — every one of these headers is what
// `readSpreadsheetRows`/the import service matches on. `category_code` from
// the original spec doesn't exist in the schema (Category has no `code`
// column — only Workstream and AttributeType do); `category_name` is used
// instead, scoped to the row's resolved workstream. See the module's report
// note.
const FIXED_HEADERS = [
    'sku',
    'name',
    'description',
    'workstream_code',
    'category_name',
    'selling_price',
    'cost_price',
    'uom',
    'min_stock_level',
];
const HEADER_FILL = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFE0E0E0' } };
const REQUIRED_HEADER_FILL = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFFFE0B2' } };
const REQUIRED_FIXED = new Set(['sku', 'name', 'workstream_code', 'category_name', 'selling_price']);
/**
 * Builds the downloadable import template: a "Products" data sheet (fixed
 * columns + one column per active attribute type + example rows) and an
 * "Instructions" sheet explaining the rules. `readSpreadsheetRows` always
 * reads worksheet[0] as data, so Instructions being sheet 2 means it's
 * never mistaken for data on re-upload.
 */
async function buildImportTemplate(attributeColumns, examples) {
    const workbook = new exceljs_1.default.Workbook();
    workbook.creator = 'Warehouse System';
    workbook.created = new Date();
    const headers = [...FIXED_HEADERS, ...attributeColumns.map((c) => c.header)];
    const sheet = workbook.addWorksheet('Products', { views: [{ state: 'frozen', ySplit: 1 }] });
    sheet.columns = headers.map((header) => ({
        header,
        key: header,
        width: Math.max(14, Math.min(28, header.length + 4)),
    }));
    const headerRow = sheet.getRow(1);
    headerRow.eachCell((cell) => {
        cell.font = { bold: true };
        const header = String(cell.value);
        cell.fill = REQUIRED_FIXED.has(header) ? REQUIRED_HEADER_FILL : HEADER_FILL;
        cell.border = { bottom: { style: 'thin' } };
    });
    for (const example of examples) {
        const row = {
            sku: example.sku,
            name: example.name,
            description: example.description ?? '',
            workstream_code: example.workstreamCode,
            category_name: example.categoryName,
            selling_price: example.sellingPrice,
            cost_price: example.costPrice ?? '',
            uom: example.uom,
            min_stock_level: example.minStockLevel ?? '',
        };
        for (const col of attributeColumns) {
            row[col.header] = example.attributeValues?.[col.header] ?? '';
        }
        sheet.addRow(row);
    }
    const notes = workbook.addWorksheet('Instructions');
    notes.columns = [{ width: 100 }];
    const lines = [
        'How to fill in this template',
        '',
        'Required columns: sku, name, workstream_code, category_name, selling_price.',
        '  (highlighted in the Products sheet\'s header row)',
        'Optional columns: description, cost_price, uom, min_stock_level, and every attribute column.',
        '',
        'sku — must be unique. If the SKU already exists in the system, that row UPDATES the',
        '  existing product instead of creating a new one.',
        'workstream_code — must match the CODE of an existing, active workstream exactly',
        '  (see Settings > Workstreams in the app for the current list).',
        'category_name — must match the NAME of an existing, active category that belongs to',
        '  that same workstream (category names are not globally unique — the same name in a',
        '  different workstream will not match).',
        'selling_price, cost_price, min_stock_level — plain numbers only. "E12.50", "12,50" and',
        '  "R 12.50" are all rejected — use a plain decimal like 12.50.',
        '',
        'Attribute columns (one per active attribute type, e.g. Colour, Size, "Weight (kg)") are',
        '  all optional. Leave a cell blank to skip that attribute. A NUMBER-type attribute',
        '  column (e.g. Weight) only accepts a plain number, same rule as the price columns.',
        '  On an UPDATE row, attribute columns REPLACE the product\'s full attribute set —',
        '  leaving one blank clears that attribute on the existing product if it had a value.',
        '  Unknown column headers (not one of the columns above) are ignored, not an error.',
        '',
        'The example rows below the header are real, valid data — you can upload this file',
        '  as-is to see how it works, or delete/overwrite the example rows with your own.',
        '',
        'Preview before it counts: uploading this file only shows a preview of what would be',
        '  created/updated/rejected. Nothing is saved until you confirm the import.',
    ];
    lines.forEach((line, index) => {
        const cell = notes.getCell(index + 1, 1);
        cell.value = line;
        if (index === 0)
            cell.font = { bold: true, size: 14 };
    });
    const buffer = await workbook.xlsx.writeBuffer();
    return Buffer.from(buffer);
}
