import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/nocturne.dart';
import '../../shared/export/label_export.dart';
import '../../shared/nx/nx_form.dart';
import '../../shared/nx/nx_overlays.dart';
import '../../shared/nx/nx_primitives.dart';
import '../../shared/scan/scan_code.dart';
import '../locations/data/leaf_locations_provider.dart';
import '../locations/domain/location.dart';
import '../products/domain/product.dart';
import '../reports/data/export_branding.dart';

QrLabel productLabel(Product p) => QrLabel(
  payload: ScanCode.forProduct(p.id),
  code: p.sku,
  title: p.name,
  sub: [p.category?.name, p.uom].whereType<String>().join(' · '),
);

QrLabel locationLabel(Location l, {String? path, String? warehouse}) => QrLabel(
  payload: ScanCode.forLocation(l.id),
  code: l.code,
  title: path ?? l.name,
  sub: warehouse,
);

QrLabel leafLabel(LeafLocation l) => locationLabel(l.location, path: l.pathLabel.isEmpty ? l.location.name : l.pathLabel, warehouse: l.warehouse.name);

/// Downloads [labels] as an A4 sticker sheet, toasting the outcome.
Future<void> printQrLabels(WidgetRef ref, List<QrLabel> labels, {int copies = 1, String name = 'qr labels'}) async {
  if (labels.isEmpty) {
    NxToast.error('Nothing to print', 'There are no labels in this selection.');
    return;
  }
  try {
    final file = await downloadLabels(labels, await loadExportBranding(ref), copies: copies, name: name);
    NxToast.ok('Labels ready', '${labels.length * copies} label(s) · $file');
  } catch (e) {
    NxToast.error('Labels not created', '$e');
  }
}

/// Shows one record's QR code (what a scanner reads) with a "print labels"
/// action for as many copies as needed.
Future<void> showQrLabelDialog(BuildContext context, QrLabel label) =>
    showNxDialog<void>(context, width: 400, builder: (_) => _QrLabelDialog(label: label));

class _QrLabelDialog extends ConsumerStatefulWidget {
  const _QrLabelDialog({required this.label});

  final QrLabel label;

  @override
  ConsumerState<_QrLabelDialog> createState() => _QrLabelDialogState();
}

class _QrLabelDialogState extends ConsumerState<_QrLabelDialog> {
  final _copies = TextEditingController(text: '1');
  bool _busy = false;

  @override
  void dispose() {
    _copies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final l = widget.label;
    return NxDialogFrame(
      title: 'QR label',
      sub: 'Scanning this opens the record anywhere in the console. It keeps working if the code is renamed.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(NxRadius.md)),
              child: QrImageView(data: l.payload, size: 190, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Text(l.code, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: n.text, fontFamily: NxText.mono)),
          Text(l.title, textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: n.n300)),
          if (l.sub != null && l.sub!.isNotEmpty) Text(l.sub!, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: n.n500)),
          const SizedBox(height: 14),
          NxField(
            label: 'Copies',
            hint: 'Printed on A4 sheets of 24 stickers (3 × 8).',
            child: NxInput(controller: _copies, inputFormatters: [FilteringTextInputFormatter.digitsOnly], placeholder: '1'),
          ),
        ],
      ),
      actions: [
        NxButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: 'Print labels',
          icon: PhosphorIconsRegular.printer,
          onPressed: _busy
              ? null
              : () async {
                  final copies = (int.tryParse(_copies.text.trim()) ?? 1).clamp(1, 240);
                  setState(() => _busy = true);
                  await printQrLabels(ref, [l], copies: copies, name: '${l.code} label');
                  if (mounted) setState(() => _busy = false);
                },
        ),
      ],
    );
  }
}
