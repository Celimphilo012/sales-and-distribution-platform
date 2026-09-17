import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dropdown_field.dart';
import '../../../../shared/widgets/app_number_field.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../inventory/presentation/widgets/product_picker_field.dart';
import '../../../locations/domain/location.dart';
import '../../../locations/presentation/widgets/leaf_location_field.dart';
import '../../../products/domain/product.dart';
import '../../data/stock_adjustments_providers.dart';
import '../../domain/stock_adjustment.dart';

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
  Location? _location;
  AdjustmentBucket _bucket = AdjustmentBucket.onHand;
  AdjustmentDirection _direction = AdjustmentDirection.increase;
  bool _saving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _deltaController.dispose();
    _reasonController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_product == null) {
      setState(() => _errorMessage = 'Choose a product.');
      return;
    }
    if (_location == null) {
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
            locationId: _location!.id,
            bucket: _bucket,
            delta: double.parse(_deltaController.text.trim()),
            direction: _direction,
            reason: _reasonController.text.trim(),
            reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
          );

      if (!mounted) return;
      setState(() {
        _product = null;
        _location = null;
        _bucket = AdjustmentBucket.onHand;
        _direction = AdjustmentDirection.increase;
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
                onChanged: (product) => setState(() => _product = product),
              ),
              const SizedBox(height: AppSpacing.md),
              LeafLocationField(
                label: 'Location',
                value: _location,
                onChanged: (location) => setState(() => _location = location),
              ),
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
