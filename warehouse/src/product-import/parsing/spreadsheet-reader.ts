import { BadRequestException } from '@nestjs/common';
import { Readable } from 'stream';
import ExcelJS from 'exceljs';

/** One data row, header name -> raw cell value, plus its 1-based spreadsheet row number (matching what a user sees in Excel) for row-specific error messages. */
export interface RawImportRow {
  rowNumber: number;
  cells: Record<string, unknown>;
}

const SUPPORTED_EXTENSIONS = ['.xlsx', '.csv'];

/**
 * Reads an uploaded .xlsx or .csv buffer into header-keyed rows.
 *
 * The FIRST worksheet is the data sheet (the template's own "Instructions"
 * sheet, if present, is always sheet 2+, so it's never read as data here —
 * see `template/build-import-template.ts`). Row 1 is the header row; column
 * headers are matched by their trimmed text, so column ORDER doesn't matter
 * — a user may reorder/delete columns and re-upload. Fully blank rows
 * (every cell empty) are skipped, not reported as rejected — Excel commonly
 * leaves trailing blank rows after the last real one.
 */
export async function readSpreadsheetRows(buffer: Buffer, originalFileName: string): Promise<RawImportRow[]> {
  const extension = extensionOf(originalFileName);
  if (!SUPPORTED_EXTENSIONS.includes(extension)) {
    throw new BadRequestException(`Unsupported file type "${extension || '(none)'}" — upload a .xlsx or .csv file`);
  }

  const workbook = new ExcelJS.Workbook();
  try {
    if (extension === '.csv') {
      const stream = new Readable();
      stream.push(buffer);
      stream.push(null);
      await workbook.csv.read(stream);
    } else {
      await workbook.xlsx.load(buffer as unknown as ExcelJS.Buffer);
    }
  } catch (error) {
    throw new BadRequestException(`Could not read the file as ${extension === '.csv' ? 'CSV' : 'Excel'}: ${(error as Error).message}`);
  }

  const sheet = workbook.worksheets[0];
  if (!sheet) throw new BadRequestException('The file has no worksheet to read');

  const headerRow = sheet.getRow(1);
  const headers = new Map<number, string>(); // column index -> trimmed header text
  headerRow.eachCell({ includeEmpty: false }, (cell, colNumber) => {
    const text = cellText(cell.value).trim();
    if (text) headers.set(colNumber, text);
  });
  if (headers.size === 0) {
    throw new BadRequestException('The file has no header row — the first row must name each column');
  }

  const rows: RawImportRow[] = [];
  const lastRow = sheet.actualRowCount || sheet.rowCount;
  for (let rowNumber = 2; rowNumber <= lastRow; rowNumber++) {
    const row = sheet.getRow(rowNumber);
    const cells: Record<string, unknown> = {};
    let hasAnyValue = false;

    for (const [colNumber, header] of headers) {
      const value = row.getCell(colNumber).value;
      const text = cellText(value);
      if (text.trim() !== '') hasAnyValue = true;
      cells[header] = normalizeCellValue(value);
    }

    if (hasAnyValue) rows.push({ rowNumber, cells });
  }

  return rows;
}

function extensionOf(fileName: string): string {
  const match = /\.[^.]+$/.exec(fileName.toLowerCase());
  return match ? match[0] : '';
}

/** exceljs may give back a rich-text object or a formula-result object instead of a plain scalar — reduce either to plain text for header matching / blank checks. */
function cellText(value: ExcelJS.CellValue): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'object') {
    if ('text' in value && typeof value.text === 'string') return value.text;
    if ('result' in value) return cellText(value.result as ExcelJS.CellValue);
    if ('richText' in value && Array.isArray(value.richText)) {
      return value.richText.map((run) => run.text).join('');
    }
    if (value instanceof Date) return value.toISOString();
    return '';
  }
  return String(value);
}

/** Numbers stay numbers (so strict-number parsing sees a real JS number for a genuinely-numeric xlsx cell); everything else is reduced to plain text. */
function normalizeCellValue(value: ExcelJS.CellValue): unknown {
  if (typeof value === 'number') return value;
  const text = cellText(value);
  return text;
}
