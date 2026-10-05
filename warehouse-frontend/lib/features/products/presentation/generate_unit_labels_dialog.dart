import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/export/label_export.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/scan/scan_code.dart';
import '../../scan/qr_label_dialog.dart';
import '../data/products_providers.dart';
import '../domain/product.dart';

/// Pre-prints N unique stickers for a SERIAL product — one physically distinct
/// `WH:U:<id>` code per sticker, meant to be applied to each incoming unit
/// before (or as) it's received, then scanned in on "Scan to receive".
Future<void> showGenerateUnitLabelsDialog(BuildContext context, Product product) =>
    showNxDialog<void>(context, width: 380, builder: (_) => _GenerateUnitLabelsDialog(product: product));

class _GenerateUnitLabelsDialog extends ConsumerStatefulWidget {
  const _GenerateUnitLabelsDialog({required this.product});

  final Product product;

  @override
  ConsumerState<_GenerateUnitLabelsDialog> createState() => _GenerateUnitLabelsDialogState();
}

class _GenerateUnitLabelsDialogState extends ConsumerState<_GenerateUnitLabelsDialog> {
  final _count = TextEditingController(text: '1');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < 1 || count > 500) {
      setState(() => _error = 'Enter a whole number between 1 and 500');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(productsApiProvider);
      final unitIds = await api.generateUnits(widget.product.id, count);
      final labels = [
        for (final id in unitIds)
          QrLabel(payload: ScanCode.forUnit(id), code: id.substring(0, 8).toUpperCase(), title: widget.product.name, sub: widget.product.sku),
      ];
      if (!mounted) return;
      Navigator.of(context).pop();
      await printQrLabels(ref, labels, name: '${widget.product.sku} unit labels');
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: 'Generate unit labels',
      sub: 'Each sticker carries its own unique code — apply one per physical unit before receiving, '
          'then scan them in. ${widget.product.sku} · ${widget.product.name}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxField(
            label: 'How many units',
            error: _error,
            child: NxInput(
              controller: _count,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              placeholder: 'e.g. 30',
              error: _error != null,
            ),
          ),
          const SizedBox(height: 6),
          Text('Printed on A4 sheets of 24 stickers (3 × 8), one distinct code per sticker.', style: TextStyle(fontSize: 11, color: n.n500)),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _busy ? 'Generating…' : 'Generate & print',
          icon: PhosphorIconsRegular.printer,
          onPressed: _busy ? null : _generate,
        ),
      ],
    );
  }
}
