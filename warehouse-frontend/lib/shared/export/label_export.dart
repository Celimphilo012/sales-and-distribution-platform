import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../browser_download.dart';
import 'report_export.dart';

/// One sticker: the QR [payload] (see `ScanCode`), the big human-readable
/// [code] printed under it (SKU / location code), a [title] and a [sub] line.
class QrLabel {
  const QrLabel({required this.payload, required this.code, required this.title, this.sub});

  final String payload;
  final String code;
  final String title;
  final String? sub;
}

const _cols = 3;
const _rows = 8;
const _perPage = _cols * _rows;

const _ink = PdfColor.fromInt(0xFF1F2127);
const _muted = PdfColor.fromInt(0xFF6B6F80);
const _cut = PdfColor.fromInt(0xFFD6D9E7);

String _safe(String s) => s
    .replaceAll('›', '>')
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('·', '|')
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

pw.Widget _label(QrLabel l, String company) => pw.Container(
  padding: const pw.EdgeInsets.all(6),
  decoration: pw.BoxDecoration(border: pw.Border.all(color: _cut, width: 0.4)),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(width: 78, height: 78, child: pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: l.payload, drawText: false)),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(_safe(l.code), maxLines: 1, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.SizedBox(height: 2),
            pw.Text(_safe(l.title), maxLines: 3, style: const pw.TextStyle(fontSize: 7.5, color: _ink)),
            if (l.sub != null && l.sub!.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text(_safe(l.sub!), maxLines: 2, style: const pw.TextStyle(fontSize: 6.5, color: _muted)),
            ],
            pw.SizedBox(height: 3),
            pw.Text(_safe(company), maxLines: 1, style: const pw.TextStyle(fontSize: 6, color: _muted)),
          ],
        ),
      ),
    ],
  ),
);

/// A4 sheets of 3 × 8 QR stickers (about 63 × 35 mm each — the common
/// 24-per-sheet label stock), each label repeated [copies] times.
Future<Uint8List> labelsPdf(List<QrLabel> labels, ExportBranding b, {int copies = 1}) async {
  final all = [for (final l in labels) for (var i = 0; i < copies; i++) l];
  final doc = pw.Document(title: 'QR labels', author: b.company);
  for (var start = 0; start < all.length; start += _perPage) {
    final page = all.sublist(start, (start + _perPage).clamp(0, all.length));
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 22, vertical: 30),
        build: (ctx) => pw.Column(
          children: [
            for (var r = 0; r < _rows; r++)
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (var c = 0; c < _cols; c++)
                      pw.Expanded(child: r * _cols + c < page.length ? _label(page[r * _cols + c], b.company) : pw.SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

/// Builds and downloads the label sheet; returns the file name.
Future<String> downloadLabels(List<QrLabel> labels, ExportBranding b, {int copies = 1, String name = 'qr labels'}) async {
  final file = '${exportFileName(name)}.pdf';
  triggerBrowserDownload(await labelsPdf(labels, b, copies: copies), file, mimeType: 'application/pdf');
  return file;
}
