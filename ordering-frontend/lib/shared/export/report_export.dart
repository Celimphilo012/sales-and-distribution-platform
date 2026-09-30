import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/painting.dart' show Color;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/theme/brand_palette.dart';
import '../../core/theme/nocturne.dart';
import '../browser_download.dart';
import '../nx/nx_format.dart';

/// How a report column is formatted (and aligned: everything but text is right-aligned).
enum ColType { text, num, money, pct }

class ReportColumn {
  const ReportColumn(this.header, [this.type = ColType.text, this.width = 14]);

  final String header;
  final ColType type;

  /// Excel column width (characters).
  final double width;
}

/// A report ready to export: columns, raw rows (numbers stay numbers), and
/// optionally a totals row summing the numeric columns from [totalsFrom].
class ReportData {
  const ReportData({required this.title, required this.description, required this.columns, required this.rows, this.totalsFrom, this.note});

  final String title;
  final String description;
  final List<ReportColumn> columns;
  final List<List<Object?>> rows;
  final int? totalsFrom;
  final String? note;

  List<Object?>? get totals {
    if (totalsFrom == null || rows.isEmpty) return null;
    return [
      for (var i = 0; i < columns.length; i++)
        if (i == 0)
          'Total'
        else if (i >= totalsFrom! && (columns[i].type == ColType.num || columns[i].type == ColType.money))
          rows.fold<double>(0, (s, r) => s + ((r[i] as num?)?.toDouble() ?? 0))
        else
          '',
    ];
  }
}

/// Who/what goes in the header of every export — the company's letterhead.
class ExportBranding {
  const ExportBranding({
    required this.company,
    required this.subtitle,
    this.logo,
    this.color,
    this.tagline,
    this.contact = const [],
    this.registration,
    this.footer,
  });

  final String company;

  /// "Mbabane Central (WH-MB-01) · Generated 30 Sep 2026 14:05 by Kinani"
  final String subtitle;

  /// PNG or JPEG bytes; null (or anything else) draws the default mark.
  final Uint8List? logo;

  /// The brand colour; null keeps the built-in violet.
  final Color? color;

  final String? tagline;

  /// Letterhead contact lines (address, phone, email, website), top right.
  final List<String> contact;

  /// Registration / VAT line and small print, at the foot of every page.
  final String? registration;
  final String? footer;

  /// The export colours, from the brand colour (see [BrandPalette]): a deep
  /// shade for header bands, the accent for rules, pale tints for fills.
  ExportColors get colors {
    if (color == null) return ExportColors.standard;
    final ramp = BrandPalette.of(color!, Nocturne.light).ramp;
    PdfColor p(Color c) => PdfColor.fromInt(c.toARGB32());
    return ExportColors(deep: p(ramp[1]), accent: p(ramp[4]), soft: p(ramp[7]), pale: p(ramp[8]), mark: p(ramp[6]));
  }
}

/// The colours an export is drawn in.
class ExportColors {
  const ExportColors({required this.deep, required this.accent, required this.soft, required this.pale, required this.mark});

  /// Header bands (white text on it).
  final PdfColor deep;

  /// Rules, the letterhead stripe, the tagline.
  final PdfColor accent;

  /// Totals row / section fills.
  final PdfColor soft;

  /// Zebra stripes.
  final PdfColor pale;

  /// The default mark's letter.
  final PdfColor mark;

  static const standard = ExportColors(
    deep: PdfColor.fromInt(0xFF2B2741),
    accent: PdfColor.fromInt(0xFF6D60C6),
    soft: PdfColor.fromInt(0xFFECEEF7),
    pale: PdfColor.fromInt(0xFFF8F9FD),
    mark: PdfColor.fromInt(0xFFB5ABFC),
  );

  /// "#RRGGBB" for Excel.
  static String hexOf(PdfColor c) => '#${(c.toInt() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String formatCell(Object? v, ColType type) {
  if (v == null || v == '') return '';
  if (v is num) {
    return switch (type) {
      ColType.num => fmtNum(v),
      ColType.money => fmtMoney(v),
      ColType.pct => '${(v * 100).round()}%',
      ColType.text => '$v',
    };
  }
  return '$v';
}

String exportStamp() => fmtDateTime(DateTime.now());

String _slug(String s) => s.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-').replaceAll(RegExp(r'(^-|-$)'), '');

String exportFileName(String title) {
  final d = DateTime.now();
  final day = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  return '${_slug(title)}-$day';
}

/// The built-in PDF fonts only cover Latin-1: swap the typographic marks the
/// app uses for plain equivalents.
String _pdfSafe(String s) => s
    .replaceAll('›', '>')
    .replaceAll('→', '->')
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('−', '-')
    .replaceAll('…', '...')
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('’', "'")
    .replaceAll('·', '|')
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

// ─── PDF ────────────────────────────────────────────────────────────────────

const _ink = PdfColor.fromInt(0xFF1F2127);
const _muted = PdfColor.fromInt(0xFF6B6F80);
const _faint = PdfColor.fromInt(0xFF9397AB);
const _rule = PdfColor.fromInt(0xFFD6D9E7);
const _grid = PdfColor.fromInt(0xFFE2E5F0);
const _headFg = PdfColor.fromInt(0xFFFFFFFF);

pw.ImageProvider? _logoImage(Uint8List? bytes) {
  if (bytes == null || bytes.length < 4) return null;
  final png = bytes[0] == 0x89 && bytes[1] == 0x50;
  final jpg = bytes[0] == 0xFF && bytes[1] == 0xD8;
  return png || jpg ? pw.MemoryImage(bytes) : null;
}

pw.Widget _defaultMark(ExportColors c, String company) => pw.Container(
  width: 36,
  height: 36,
  decoration: pw.BoxDecoration(color: c.deep, borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8))),
  alignment: pw.Alignment.center,
  child: pw.Text(
    company.trim().isEmpty ? 'W' : _pdfSafe(company.trim()[0].toUpperCase()),
    style: pw.TextStyle(color: c.mark, fontSize: 18, fontWeight: pw.FontWeight.bold),
  ),
);

/// The letterhead: logo, company name + tagline + what this document is, the
/// contact block on the right, and a rule in the brand colour.
pw.Widget _pdfHeader(ExportBranding b) {
  final logo = _logoImage(b.logo);
  final c = b.colors;
  final tagline = b.tagline ?? '';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logo != null) pw.SizedBox(width: 36, height: 36, child: pw.Image(logo, fit: pw.BoxFit.contain)) else _defaultMark(c, b.company),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(_pdfSafe(b.company), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
                if (tagline.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(_pdfSafe(tagline), style: pw.TextStyle(fontSize: 8.5, color: c.accent)),
                ],
                pw.SizedBox(height: 2),
                pw.Text(_pdfSafe(b.subtitle), style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              ],
            ),
          ),
          if (b.contact.isNotEmpty) ...[
            pw.SizedBox(width: 12),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [for (final line in b.contact) pw.Text(_pdfSafe(line), style: const pw.TextStyle(fontSize: 8, color: _muted))],
            ),
          ],
        ],
      ),
      pw.SizedBox(height: 8),
      pw.Container(height: 1.6, color: c.accent),
      pw.SizedBox(height: 10),
    ],
  );
}

/// Registration / small print (when set), then "company | title" and the page number.
pw.Widget _pdfFooter(pw.Context ctx, ExportBranding b, String title) {
  final small = [b.registration, b.footer].whereType<String>().where((x) => x.isNotEmpty).join('   |   ');
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (small.isNotEmpty) ...[
        pw.Divider(color: _rule, thickness: 0.5, height: 1),
        pw.SizedBox(height: 4),
        pw.Text(_pdfSafe(small), style: const pw.TextStyle(fontSize: 7.5, color: _faint)),
        pw.SizedBox(height: 3),
      ],
      pw.Row(
        children: [
          pw.Expanded(child: pw.Text(_pdfSafe('${b.company} | $title'), style: const pw.TextStyle(fontSize: 8, color: _faint))),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _faint)),
        ],
      ),
    ],
  );
}

pw.Widget _titleBlock(String title, String desc) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(_pdfSafe(title), style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: _ink)),
    pw.SizedBox(height: 3),
    pw.Text(_pdfSafe(desc), style: const pw.TextStyle(fontSize: 9, color: _muted)),
    pw.SizedBox(height: 10),
  ],
);

Future<Uint8List> reportPdf(ReportData rep, ExportBranding b) async {
  final c = b.colors;
  final doc = pw.Document(title: rep.title, author: b.company);
  final landscape = rep.columns.length > 6;
  final totals = rep.totals;
  final align = {
    for (var i = 0; i < rep.columns.length; i++)
      i: rep.columns[i].type == ColType.text ? pw.Alignment.centerLeft : pw.Alignment.centerRight,
  };
  final data = [
    for (final r in rep.rows) [for (var i = 0; i < rep.columns.length; i++) _pdfSafe(formatCell(r[i], rep.columns[i].type))],
  ];
  doc.addPage(
    pw.MultiPage(
      pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
      header: (_) => _pdfHeader(b),
      footer: (ctx) => _pdfFooter(ctx, b, rep.title),
      build: (ctx) => [
        _titleBlock(rep.title, '${rep.description}${rep.note == null ? '' : '  ${rep.note}'}'),
        if (rep.rows.isEmpty)
          pw.Text('No rows.', style: const pw.TextStyle(fontSize: 10, color: _muted))
        else
          pw.TableHelper.fromTextArray(
            headers: [for (final c in rep.columns) _pdfSafe(c.header)],
            data: [
              ...data,
              if (totals != null)
                [for (var i = 0; i < rep.columns.length; i++) _pdfSafe(totals[i] is num ? formatCell(totals[i], rep.columns[i].type) : '${totals[i]}')],
            ],
            headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _headFg),
            headerDecoration: pw.BoxDecoration(color: c.deep),
            cellStyle: const pw.TextStyle(fontSize: 8.5, color: _ink),
            cellAlignments: align,
            headerAlignments: align,
            cellPadding: const pw.EdgeInsets.all(5),
            oddRowDecoration: pw.BoxDecoration(color: c.pale),
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _grid, width: 0.5), bottom: pw.BorderSide(color: _grid, width: 0.5)),
            cellDecoration: totals == null
                ? null
                : (index, value, rowNum) => rowNum == data.length + 1 ? pw.BoxDecoration(color: c.soft) : const pw.BoxDecoration(),
          ),
      ],
    ),
  );
  return doc.save();
}

/// One order's pick lines for [pickListPdf].
class PickOrder {
  const PickOrder({required this.title, required this.subtitle, required this.lines});

  final String title;
  final String subtitle;

  /// (qty with unit, product, sku, pick from)
  final List<(String, String, String, String)> lines;
}

Future<Uint8List> pickListPdf(List<PickOrder> orders, ExportBranding b) async {
  final c = b.colors;
  final doc = pw.Document(title: 'Pick list', author: b.company);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 30, 40, 30),
      header: (_) => _pdfHeader(b),
      footer: (ctx) => _pdfFooter(ctx, b, 'Pick list'),
      build: (ctx) => [
        _titleBlock('Pick list', '${orders.length} open order(s) | only the lines you pack'),
        for (final o in orders) ...[
          pw.Container(
            color: c.deep,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: pw.Text(_pdfSafe('${o.title}   |   ${o.subtitle}'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _headFg)),
          ),
          pw.TableHelper.fromTextArray(
            headers: ['', 'Qty', 'Product', 'SKU', 'Pick from'],
            data: [for (final l in o.lines) ['[  ]', _pdfSafe(l.$1), _pdfSafe(l.$2), _pdfSafe(l.$3), _pdfSafe(l.$4)]],
            headerStyle: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: _ink),
            headerDecoration: pw.BoxDecoration(color: c.soft),
            cellStyle: const pw.TextStyle(fontSize: 9, color: _ink),
            cellPadding: const pw.EdgeInsets.all(5),
            columnWidths: {0: const pw.FixedColumnWidth(26), 1: const pw.FixedColumnWidth(70)},
            border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _grid, width: 0.5), bottom: pw.BorderSide(color: _grid, width: 0.5)),
          ),
          pw.SizedBox(height: 16),
        ],
      ],
    ),
  );
  return doc.save();
}

// ─── Excel ──────────────────────────────────────────────────────────────────

Uint8List reportXlsx(ReportData rep, ExportBranding b) {
  final book = xl.Excel.createExcel();
  final defaultSheet = book.getDefaultSheet() ?? 'Sheet1';
  final name = rep.title.length > 31 ? rep.title.substring(0, 31) : rep.title;
  book.rename(defaultSheet, name);
  final s = book[name];
  final n = rep.columns.length;
  xl.CellIndex at(int col, int row) => xl.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
  xl.ExcelColor hex(String h) => xl.ExcelColor.fromHexString(h);

  void put(int col, int row, Object? v, {xl.CellStyle? style}) {
    final cell = s.cell(at(col, row));
    cell.value = switch (v) {
      null => null,
      int i => xl.IntCellValue(i),
      num d => xl.DoubleCellValue(d.toDouble()),
      _ => xl.TextCellValue('$v'),
    };
    if (style != null) cell.cellStyle = style;
  }

  final lastCol = n > 1 ? n - 1 : 1;
  put(0, 0, b.company, style: xl.CellStyle(bold: true, fontSize: 14, fontColorHex: hex('#1F2127')));
  s.merge(at(0, 0), at(lastCol, 0));
  final colors = b.colors;
  put(0, 1, [?b.tagline, b.subtitle].join(' · '), style: xl.CellStyle(fontSize: 9, fontColorHex: hex('#6B6F80')));
  s.merge(at(0, 1), at(lastCol, 1));
  if (b.contact.isNotEmpty) {
    put(0, 2, b.contact.join(' · '), style: xl.CellStyle(fontSize: 9, fontColorHex: hex('#6B6F80')));
    s.merge(at(0, 2), at(lastCol, 2));
  }
  put(0, 3, rep.title, style: xl.CellStyle(bold: true, fontSize: 15, fontColorHex: hex('#1F2127')));
  s.merge(at(0, 3), at(lastCol, 3));
  put(0, 4, '${rep.description}${rep.note == null ? '' : '  ${rep.note}'}', style: xl.CellStyle(fontSize: 9, fontColorHex: hex('#6B6F80')));
  s.merge(at(0, 4), at(lastCol, 4));

  xl.NumFormat? fmtOf(ColType t) => switch (t) {
    ColType.num => xl.NumFormat.standard_3,
    ColType.money => xl.NumFormat.standard_4,
    ColType.pct => xl.NumFormat.standard_9,
    ColType.text => null,
  };
  xl.HorizontalAlign alignOf(ColType t) => t == ColType.text ? xl.HorizontalAlign.Left : xl.HorizontalAlign.Right;

  const headRow = 5;
  for (var i = 0; i < n; i++) {
    final c = rep.columns[i];
    put(i, headRow, c.header, style: xl.CellStyle(bold: true, fontColorHex: hex('#FFFFFF'), backgroundColorHex: hex(ExportColors.hexOf(colors.deep)), horizontalAlign: alignOf(c.type)));
    s.setColumnWidth(i, c.width);
  }
  for (var r = 0; r < rep.rows.length; r++) {
    for (var i = 0; i < n; i++) {
      final c = rep.columns[i];
      final f = fmtOf(c.type);
      put(
        i,
        headRow + 1 + r,
        rep.rows[r][i],
        style: xl.CellStyle(
          horizontalAlign: alignOf(c.type),
          backgroundColorHex: r.isOdd ? hex(ExportColors.hexOf(colors.pale)) : xl.ExcelColor.none,
          numberFormat: f ?? xl.NumFormat.standard_0,
        ),
      );
    }
  }
  final totals = rep.totals;
  if (totals != null) {
    final row = headRow + 1 + rep.rows.length;
    for (var i = 0; i < n; i++) {
      final f = fmtOf(rep.columns[i].type);
      put(
        i,
        row,
        totals[i] == '' ? null : totals[i],
        style: xl.CellStyle(bold: true, backgroundColorHex: hex(ExportColors.hexOf(colors.soft)), horizontalAlign: alignOf(rep.columns[i].type), numberFormat: f ?? xl.NumFormat.standard_0),
      );
    }
  }
  return Uint8List.fromList(book.encode()!);
}

// ─── Download ───────────────────────────────────────────────────────────────

const _pdfMime = 'application/pdf';
const _xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Builds and downloads [rep] as PDF (`pdf: true`) or Excel; returns the file name.
Future<String> downloadReport(ReportData rep, ExportBranding b, {required bool pdf}) async {
  final name = '${exportFileName(rep.title)}.${pdf ? 'pdf' : 'xlsx'}';
  final bytes = pdf ? await reportPdf(rep, b) : reportXlsx(rep, b);
  triggerBrowserDownload(bytes, name, mimeType: pdf ? _pdfMime : _xlsxMime);
  return name;
}

Future<String> downloadPickList(List<PickOrder> orders, ExportBranding b) async {
  final name = '${exportFileName('pick list')}.pdf';
  triggerBrowserDownload(await pickListPdf(orders, b), name, mimeType: _pdfMime);
  return name;
}
