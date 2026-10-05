import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../shared/scan/scan_dialog.dart';
import '../../scan/scan_lookup.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_balance.dart';
import '../../inventory/presentation/widgets/balance_preview.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_options.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/stock_adjustments_providers.dart';
import '../domain/stock_adjustment.dart';

/// The buckets a request can change (reservations belong to orders).
const _buckets = [AdjustmentBucket.onHand, AdjustmentBucket.damaged, AdjustmentBucket.lost, AdjustmentBucket.expired];

double _bucketQty(InventoryBalance? b, AdjustmentBucket bucket) => b == null
    ? 0
    : switch (bucket) {
        AdjustmentBucket.onHand => b.onHand,
        AdjustmentBucket.reserved => b.reserved,
        AdjustmentBucket.damaged => b.damaged,
        AdjustmentBucket.lost => b.lost,
        AdjustmentBucket.expired => b.expired,
      };

/// "Request adjustment" — the prototype's adjustment form (560px), with a
/// SEARCHABLE product and location (slots holding the product listed first,
/// with their quantity), an optional reference, and an optional evidence
/// PHOTO. A request never moves stock; a different reviewer approves it.
Future<void> showAdjustmentForm(BuildContext context, {String? productId, String? locationId}) =>
    showNxDialog<void>(context, width: 560, builder: (_) => _AdjustmentForm(productId: productId, locationId: locationId));

class _AdjustmentForm extends ConsumerStatefulWidget {
  const _AdjustmentForm({this.productId, this.locationId});

  final String? productId;
  final String? locationId;

  @override
  ConsumerState<_AdjustmentForm> createState() => _AdjustmentFormState();
}

class _AdjustmentFormState extends ConsumerState<_AdjustmentForm> {
  late String? _productId = widget.productId;
  late String? _locationId = widget.locationId;
  AdjustmentBucket _bucket = AdjustmentBucket.onHand;
  AdjustmentDirection _direction = AdjustmentDirection.decrease;
  final _qty = TextEditingController();
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  Uint8List? _photo;
  String? _photoName;
  bool _picking = false;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    for (final c in [_qty, _reason, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      // FileType.image, not custom+extensions — the latter's accept=".jpg,.png,…" frequently
      // suppresses iOS Safari's "Take Photo" option; accept="image/*" shows it reliably.
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.length > 8 * 1024 * 1024) {
        setState(() => _errors['photo'] = 'That photo is over 8 MB — choose a smaller one');
        return;
      }
      setState(() {
        _photo = bytes;
        _photoName = file.name;
        _errors.remove('photo');
      });
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit(Product? product) async {
    final qty = double.tryParse(_qty.text.trim());
    final errors = <String, String>{
      if (_productId == null) 'product': 'Choose a product',
      if (_locationId == null) 'loc': 'Choose a location',
      if (qty == null || qty <= 0) 'qty': 'Must be greater than 0',
      if (_reason.text.trim().isEmpty) 'reason': 'Say what happened, and how you know',
    };
    setState(() {
      _errors
        ..removeWhere((k, _) => k != 'photo')
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(stockAdjustmentsApiProvider).create(
        productId: _productId!,
        locationId: _locationId!,
        bucket: _bucket,
        delta: qty!,
        direction: _direction,
        reason: _reason.text.trim(),
        reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        photoBytes: _photo,
        photoFileName: _photoName,
      );
      ref.invalidate(stockAdjustmentsListProvider);
      if (mounted) Navigator.of(context).pop();
      NxToast.info('Request sent for approval', '${created.product.name}${_photo != null ? ' · photo attached' : ''}');
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final products = ref.watch(productsListProvider).value ?? const <Product>[];
    final leaves = ref.watch(leafLocationsProvider).value ?? const <LeafLocation>[];
    final balances = ref.watch(allBalancesProvider).value ?? const <InventoryBalance>[];
    final product = products.where((p) => p.id == _productId).firstOrNull;
    final held = {for (final b in balances.where((b) => b.productId == _productId)) b.locationId: b};
    final locOptions = [
      for (final l in leaves.where((l) => held.containsKey(l.id))) l.option(trailing: '${fmtNum(held[l.id]!.onHand)} on hand'),
      for (final l in leaves.where((l) => !held.containsKey(l.id))) l.option(),
    ];
    final balance = held[_locationId];
    final before = _bucketQty(balance, _bucket);
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final inc = _direction == AdjustmentDirection.increase;
    final after = inc ? before + qty : before - qty;

    return NxDialogFrame(
      title: 'Request adjustment',
      sub: 'A request never moves stock — a different reviewer approves it.',
      body: NxFormGrid(
        children: [
          NxSpan2(
            child: NxField(
              label: 'Product',
              required: true,
              error: _errors['product'],
              child: ScanPicker(
                tooltip: 'Scan the product',
                onScan: () async {
                  final id = await scanProductId(context, products);
                  if (id != null && mounted) setState(() => _productId = id);
                },
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
          ),
          NxSpan2(
            child: NxField(
              label: 'Location',
              required: true,
              error: _errors['loc'],
              hint: _productId != null && held.isNotEmpty ? 'Slots holding this product are listed first' : null,
              child: ScanPicker(
                tooltip: 'Scan the location',
                onScan: () async {
                  final id = await scanLeafId(context, leaves);
                  if (id != null && mounted) setState(() => _locationId = id);
                },
                child: NxSelect<String>(
                  options: locOptions,
                  value: _locationId,
                  searchable: true,
                  searchPlaceholder: 'Search slots by code or name',
                  placeholder: 'Choose a slot',
                  error: _errors['loc'] != null,
                  onChanged: (v) => setState(() => _locationId = v),
                ),
              ),
            ),
          ),
          NxSpan2(
            child: NxField(
              label: 'Bucket',
              child: Align(
                alignment: Alignment.centerLeft,
                child: NxSeg<AdjustmentBucket>(
                  options: [for (final b in _buckets) (b, b.label, null)],
                  value: _bucket,
                  onChanged: (v) => setState(() => _bucket = v),
                ),
              ),
            ),
          ),
          NxField(
            label: 'Direction',
            child: Align(
              alignment: Alignment.centerLeft,
              child: NxSeg<AdjustmentDirection>(
                options: const [(AdjustmentDirection.increase, 'Increase', null), (AdjustmentDirection.decrease, 'Decrease', null)],
                value: _direction,
                onChanged: (v) => setState(() => _direction = v),
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
          NxSpan2(
            child: NxField(
              label: 'Reason',
              required: true,
              error: _errors['reason'],
              child: NxInput(
                controller: _reason,
                placeholder: 'What happened, and how you know',
                maxLines: 4,
                minLines: 3,
                error: _errors['reason'] != null,
              ),
            ),
          ),
          NxField(label: 'Reference (optional)', child: NxInput(controller: _reference, placeholder: 'Incident or ticket no.')),
          NxField(
            label: 'Photo (optional)',
            error: _errors['photo'],
            hint: _photo == null ? 'Evidence for the reviewer — JPG, PNG or WebP' : null,
            child: _photo == null
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: NxButton(
                      label: _picking ? 'Opening…' : 'Add a photo',
                      icon: PhosphorIconsRegular.camera,
                      onPressed: _picking ? null : _pickPhoto,
                    ),
                  )
                : Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(NxRadius.md),
                        child: Image.memory(_photo!, width: 56, height: 56, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_photoName ?? 'photo', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: n.text)),
                            Wrap(
                              spacing: 4,
                              children: [
                                NxButton.ghost(label: 'Change', small: true, onPressed: _picking ? null : _pickPhoto),
                                NxButton.ghost(
                                  label: 'Remove',
                                  small: true,
                                  color: n.bad,
                                  onPressed: () => setState(() {
                                    _photo = null;
                                    _photoName = null;
                                  }),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (_productId != null && _locationId != null)
            NxSpan2(
              child: BalancePreview(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_bucket.label} at ${leaves.where((l) => l.id == _locationId).firstOrNull?.code ?? ''} — if approved', style: TextStyle(fontSize: 12, color: n.n400)),
                    const SizedBox(height: 4),
                    BeforeAfter(
                      before: fmtNum(before),
                      after: fmtNum(after),
                      delta: qty > 0 ? '${inc ? '+' : '−'}${fmtNum(qty)}' : null,
                      deltaColor: inc ? n.ok : n.bad,
                    ),
                    if (after < 0) ...[
                      const SizedBox(height: 4),
                      Text('That would take the bucket below zero — it will be refused.', style: TextStyle(fontSize: 12, color: n.warn)),
                    ],
                  ],
                ),
              ),
            ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Sending…' : 'Send for approval', onPressed: _saving ? null : () => _submit(product)),
      ],
    );
  }
}
