import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/presentation/widgets/balance_preview.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_options.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/receiving_providers.dart';

/// "Receive stock" — the prototype's receive sheet: product, quantity,
/// destination slot, supplier, reference (plus optional notes), with a live
/// balance preview at the destination. Records ONE RECEIVE transaction that
/// raises on-hand there. Product and destination are SEARCHABLE pickers.
Future<void> showReceiveSheet(BuildContext context, {String? productId, String? locationId}) => showNxSheet<void>(
  context,
  kicker: 'Receive stock',
  builder: (_) => _ReceiveSheet(productId: productId, locationId: locationId),
);

class _ReceiveSheet extends ConsumerStatefulWidget {
  const _ReceiveSheet({this.productId, this.locationId});

  final String? productId;
  final String? locationId;

  @override
  ConsumerState<_ReceiveSheet> createState() => _ReceiveSheetState();
}

class _ReceiveSheetState extends ConsumerState<_ReceiveSheet> {
  late String? _productId = widget.productId;
  late String? _locationId = widget.locationId;
  final _qty = TextEditingController();
  final _supplier = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_qty, _supplier, _reference, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit(Product? product) async {
    final qty = double.tryParse(_qty.text.trim());
    final errors = <String, String>{
      if (_productId == null) 'product': 'Choose a product',
      if (qty == null || qty <= 0) 'qty': 'Enter a quantity above 0',
      if (_locationId == null) 'dest': 'Choose where it goes',
      if (_supplier.text.trim().isEmpty) 'supplier': 'Supplier is required',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _error = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(receivingApiProvider).receive(
        supplier: _supplier.text.trim(),
        productId: _productId!,
        quantity: qty!,
        toLocationId: _locationId!,
        reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      invalidateStockViews(ref);
      if (!mounted) return;
      final leaf = ref.read(leafLocationsProvider).value?.where((l) => l.id == _locationId).firstOrNull;
      Navigator.of(context).pop();
      NxToast.ok('Stock received', '+${fmtNum(qty)} ${product?.uom ?? ''} · ${product?.name ?? ''} → ${leaf?.code ?? ''}');
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final products = ref.watch(productsListProvider).value ?? const <Product>[];
    final leaves = ref.watch(leafLocationsProvider);
    final product = products.where((p) => p.id == _productId).firstOrNull;
    final leaf = leaves.value?.where((l) => l.id == _locationId).firstOrNull;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final before = _productId != null && _locationId != null
        ? ref.watch(productLocationBalanceProvider((productId: _productId!, locationId: _locationId!))).value?.onHand ?? 0
        : 0.0;

    return NxSheetBody(
      children: [
        Text(
          'Records a RECEIVE transaction and increases on-hand at the destination.',
          style: TextStyle(fontSize: 12, color: n.n400),
        ),
        const SizedBox(height: 12),
        NxFormGrid(
          children: [
            NxSpan2(
              child: NxField(
                label: 'Product',
                required: true,
                error: _errors['product'],
                child: NxSelect<String>(
                  options: productOptions(products, keepId: _productId),
                  value: _productId,
                  searchable: true,
                  searchPlaceholder: 'Search by SKU or name',
                  placeholder: 'Choose a product',
                  error: _errors['product'] != null,
                  onChanged: (v) => setState(() => _productId = v),
                ),
              ),
            ),
            NxField(
              label: 'Quantity${product == null ? '' : ' (${product.uom})'}',
              required: true,
              error: _errors['qty'],
              child: NxInput(
                controller: _qty,
                placeholder: '0',
                inputFormatters: NxInput.decimals(),
                error: _errors['qty'] != null,
                onChanged: (_) => setState(() {}),
              ),
            ),
            NxField(
              label: 'Destination',
              required: true,
              error: _errors['dest'],
              child: NxSelect<String>(
                options: [for (final l in leaves.value ?? const <LeafLocation>[]) l.option()],
                value: _locationId,
                searchable: true,
                searchPlaceholder: 'Search slots by code or name',
                placeholder: leaves.isLoading ? 'Loading locations…' : 'Choose a slot',
                error: _errors['dest'] != null,
                onChanged: (v) => setState(() => _locationId = v),
              ),
            ),
            NxField(
              label: 'Supplier',
              required: true,
              error: _errors['supplier'],
              child: NxInput(controller: _supplier, placeholder: 'Required', error: _errors['supplier'] != null),
            ),
            NxField(
              label: 'Reference (optional)',
              child: NxInput(controller: _reference, placeholder: 'GRN-2026-00050'),
            ),
            NxSpan2(
              child: NxField(label: 'Notes (optional)', child: NxInput(controller: _notes, maxLines: 3, minLines: 2)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        BalancePreview(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product == null || leaf == null
                    ? 'Choose a product and a destination'
                    : '${product.name} at ${leaf.code}',
                style: TextStyle(fontSize: 12, color: n.n400),
              ),
              const SizedBox(height: 4),
              BeforeAfter(
                before: fmtNum(before),
                after: fmtNum(before + qty),
                delta: qty > 0 ? '+${fmtNum(qty)}' : null,
                deltaColor: n.ok,
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            NxButton.primary(
              label: _saving ? 'Receiving…' : 'Receive stock',
              icon: PhosphorIconsRegular.boxArrowDown,
              onPressed: _saving ? null : () => _submit(product),
            ),
            const SizedBox(width: 8),
            NxButton.ghost(label: 'Cancel', color: n.n400, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
      ],
    );
  }
}
