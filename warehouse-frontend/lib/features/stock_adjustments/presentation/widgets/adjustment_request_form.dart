import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dropdown_field.dart';
import '../../../../shared/widgets/app_number_field.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../inventory/data/inventory_providers.dart';
import '../../../inventory/domain/inventory_balance.dart';
import '../../../inventory/domain/product_location_stock.dart';
import '../../../inventory/presentation/widgets/product_location_chooser.dart';
import '../../../inventory/presentation/widgets/product_picker_field.dart';
import '../../../locations/domain/location.dart';
import '../../../locations/presentation/widgets/leaf_location_field.dart';
import '../../../products/domain/product.dart';
import '../../data/stock_adjustments_providers.dart';
import '../../domain/stock_adjustment.dart';

/// A catalogue [Product] reduced to the fields [ProductLocationChooser]
/// needs — the same shape the balances API embeds.
InventoryBalanceProductRef _productRefOf(Product product) =>
    InventoryBalanceProductRef(id: product.id, sku: product.sku, name: product.name, uom: product.uom);

/// REQUEST an adjustment (`inventory.adjust.request`, gated by the caller).
/// Submitting only creates a PENDING `StockAdjustment` — moves no stock
/// (`StockAdjustmentsService.createRequest`) — a manager approves it
/// separately via [AdjustmentSummaryTile]'s trailing controls elsewhere on
/// this screen.
class AdjustmentRequestForm extends ConsumerStatefulWidget {
  const AdjustmentRequestForm({super.key, required this.onSubmitted});

  final VoidCallback onSubmitted;

  @override
  ConsumerState<AdjustmentRequestForm> createState() => _AdjustmentRequestFormState();
}

class _AdjustmentRequestFormState extends ConsumerState<AdjustmentRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _deltaController = TextEditingController();
  final _reasonController = TextEditingController();
  final _referenceController = TextEditingController();

  Product? _product;

  /// The location the USER chose. When null, the effective location may
  /// still be auto-detected — see [_autoLocation].
  Location? _location;
  AdjustmentBucket _bucket = AdjustmentBucket.onHand;
  AdjustmentDirection _direction = AdjustmentDirection.increase;
  bool _saving = false;
  String? _errorMessage;

  Uint8List? _photoBytes;
  String? _photoFileName;
  bool _pickingPhoto = false;

  @override
  void dispose() {
    _deltaController.dispose();
    _reasonController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _pickingPhoto = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) return; // user cancelled
      final bytes = await file.readAsBytes();
      setState(() {
        _photoBytes = bytes;
        _photoFileName = file.name;
      });
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _removePhoto() => setState(() {
    _photoBytes = null;
    _photoFileName = null;
  });

  /// Active leaf locations currently holding on-hand stock of [_product] —
  /// only looked up while the user hasn't chosen a location themselves.
  /// [listen] is true from `build` (subscribes so the UI updates) and false
  /// from `_submit` (reads the already-loaded value without subscribing).
  List<ProductLocationStock> _sourcesFor({required bool listen}) {
    final product = _product;
    if (product == null || _location != null) return const [];
    final async = listen
        ? ref.watch(productStockBreakdownProvider(product.id))
        : ref.read(productStockBreakdownProvider(product.id));
    return [
      for (final s in async.value ?? const <ProductLocationStock>[])
        if (s.balance.onHand > 0) s,
    ];
  }

  /// The single location holding the product, if there's exactly one. Kept
  /// DERIVED (not stored) so it can never go stale: change the product and
  /// it recomputes; pick a location yourself and yours wins.
  Location? _autoLocation(List<ProductLocationStock> sources) =>
      sources.length == 1 && sources.first.path.isNotEmpty ? sources.first.path.last : null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_product == null) {
      setState(() => _errorMessage = 'Choose a product.');
      return;
    }
    final location = _location ?? _autoLocation(_sourcesFor(listen: false));
    if (location == null) {
      setState(() => _errorMessage = 'Choose a location.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(stockAdjustmentsApiProvider)
          .create(
            productId: _product!.id,
            locationId: location.id,
            bucket: _bucket,
            delta: double.parse(_deltaController.text.trim()),
            direction: _direction,
            reason: _reasonController.text.trim(),
            reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
            photoBytes: _photoBytes,
            photoFileName: _photoFileName,
          );

      if (!mounted) return;
      setState(() {
        _product = null;
        _location = null;
        _bucket = AdjustmentBucket.onHand;
        _direction = AdjustmentDirection.increase;
        _photoBytes = null;
        _photoFileName = null;
        _deltaController.clear();
        _reasonController.clear();
        _referenceController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Adjustment requested — pending manager approval.')));
      widget.onSubmitted();
    } on AppError catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = _product;

    final sourcesAsync =
        (product != null && _location == null) ? ref.watch(productStockBreakdownProvider(product.id)) : null;
    final sources = _sourcesFor(listen: true);
    final autoLocation = _autoLocation(sources);
    final effectiveLocation = _location ?? autoLocation;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Form(
        key: _formKey,
        child: AppCard(
          title: 'Request an adjustment',
          subtitle: 'Creates a PENDING request. A manager must approve it before stock moves.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductPickerField(
                label: 'Product',
                value: _product,
                // A newly-picked product's own location(s) haven't been
                // looked up yet — drop any previous manual pick so
                // auto-detect re-evaluates fresh for it.
                onChanged: (picked) => setState(() {
                  _product = picked;
                  _location = null;
                }),
              ),
              const SizedBox(height: AppSpacing.md),
              LeafLocationField(
                label: 'Location',
                value: effectiveLocation,
                onChanged: (location) => setState(() => _location = location),
              ),
              if (_location == null && product != null) ...[
                if (sourcesAsync?.isLoading ?? false)
                  const Padding(
                    padding: EdgeInsets.only(top: AppSpacing.sm),
                    child: LinearProgressIndicator(),
                  )
                else if (sourcesAsync?.hasError ?? false)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: Text(
                      'Could not look up where this item is currently stocked — choose the location manually.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                    ),
                  )
                else if (autoLocation != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'Detected automatically — the only location holding ${product.name}. Change it to override.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  )
                else if (sources.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ProductLocationChooser(
                      product: _productRefOf(product),
                      sources: sources,
                      promptLabel: 'Choose which location to adjust:',
                      onPick: (location) => setState(() => _location = location),
                    ),
                  ),
                // Zero sources: no message — unlike a transfer, an
                // adjustment doesn't require pre-existing stock (e.g.
                // recording newly-found surplus), so falling back to a
                // silent manual pick is correct, not an error state.
              ],
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<AdjustmentBucket>(
                label: 'Bucket',
                value: _bucket,
                items: AdjustmentBucket.values,
                itemLabel: (b) => b.label,
                onChanged: (value) {
                  if (value != null) setState(() => _bucket = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<AdjustmentDirection>(
                label: 'Direction',
                value: _direction,
                items: AdjustmentDirection.values,
                itemLabel: (d) => d.label,
                onChanged: (value) {
                  if (value != null) setState(() => _direction = value);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppNumberField(
                label: 'Delta (magnitude — always positive)',
                controller: _deltaController,
                allowDecimal: true,
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a magnitude greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Reason',
                controller: _reasonController,
                hintText: 'Damaged carton found during put-away',
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Reason is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'Reference (optional)', controller: _referenceController),
              const SizedBox(height: AppSpacing.md),
              _PhotoPicker(
                bytes: _photoBytes,
                fileName: _photoFileName,
                picking: _pickingPhoto,
                onPick: _pickPhoto,
                onRemove: _removePhoto,
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                      )
                    : const Icon(Icons.request_page_outlined),
                label: Text(_saving ? 'Requesting…' : 'Request adjustment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Optional evidence photo — most useful for a DAMAGED/LOST correction, but
/// not restricted to those buckets; a manager can open it while reviewing
/// (see [AdjustmentSummaryTile]'s own photo display in the pending queue).
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker({
    required this.bytes,
    required this.fileName,
    required this.picking,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? bytes;
  final String? fileName;
  final bool picking;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photo (optional)', style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: Image.memory(bytes!, width: 64, height: 64, fit: BoxFit.cover),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (fileName != null)
                    Text(fileName!, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall)
                  else
                    Text(
                      'Attach a photo — e.g. the damaged carton found.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: picking ? null : onPick,
                        icon: picking
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: Text(bytes == null ? 'Choose photo' : 'Change'),
                      ),
                      if (bytes != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        TextButton(onPressed: onRemove, child: const Text('Remove')),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
