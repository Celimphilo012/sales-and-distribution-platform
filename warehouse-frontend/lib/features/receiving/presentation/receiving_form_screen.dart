import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/presentation/widgets/movement_confirmation_card.dart';
import '../../inventory/presentation/widgets/product_picker_field.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/widgets/leaf_location_field.dart';
import '../../products/domain/product.dart';
import '../data/receiving_providers.dart';

/// STEP 6e-1 — RECEIVING: the first stock-MOVING screen in this app. Calls
/// the real `POST /inventory/receiving` (a RECEIVE transaction, +on_hand at
/// the destination) — `InventoryService.applyTransaction()` on the backend
/// remains the only thing that ever writes `inventory_balances` (rule 2);
/// this screen is just a client of that API, same as receiving/transfer
/// staff would use in person.
class ReceivingFormScreen extends ConsumerWidget {
  const ReceivingFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canReceive = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.receive') ?? false));
    if (!canReceive) {
      return const EmptyStateView(
        title: "You don't have permission to receive stock",
        message: 'Ask an administrator for the inventory.receive permission.',
        icon: Icons.lock_outline,
      );
    }
    return const _ReceivingFormBody();
  }
}

class _ReceivingFormBody extends ConsumerStatefulWidget {
  const _ReceivingFormBody();

  @override
  ConsumerState<_ReceivingFormBody> createState() => _ReceivingFormBodyState();
}

class _ReceivingFormBodyState extends ConsumerState<_ReceivingFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _supplierController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  Product? _product;
  Location? _destination;
  bool _saving = false;
  String? _errorMessage;

  // Set right after a successful submit; shows the confirmation card for
  // exactly that receive until the user starts a new one.
  ({Product product, Location destination})? _lastReceived;

  @override
  void dispose() {
    _quantityController.dispose();
    _supplierController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_product == null) {
      setState(() => _errorMessage = 'Choose a product.');
      return;
    }
    if (_destination == null) {
      setState(() => _errorMessage = 'Choose a destination location.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final product = _product!;
    final destination = _destination!;
    try {
      final quantity = double.parse(_quantityController.text.trim());
      await ref.read(receivingApiProvider).receive(
        supplier: _supplierController.text.trim(),
        productId: product.id,
        quantity: quantity,
        toLocationId: destination.id,
        reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      ref.invalidate(productLocationBalanceProvider((productId: product.id, locationId: destination.id)));
      ref.invalidate(locationBalancesProvider(destination.id));
      ref.invalidate(productStockBreakdownProvider(product.id));

      if (!mounted) return;
      setState(() {
        _lastReceived = (product: product, destination: destination);
        _product = null;
        _destination = null;
        _quantityController.clear();
        _referenceController.clear();
        _notesController.clear();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Received ${quantity.toString()} ${product.uom} of ${product.name}')));
    } on AppError catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text('Stock Receiving', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: AppCard(
              title: 'Receive stock',
              subtitle: 'Records a RECEIVE transaction and increases on-hand at the destination.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductPickerField(
                    label: 'Product',
                    value: _product,
                    onChanged: (product) => setState(() => _product = product),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppNumberField(
                    label: 'Quantity',
                    controller: _quantityController,
                    allowDecimal: true,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a quantity greater than 0';
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LeafLocationField(
                    label: 'Destination location',
                    value: _destination,
                    onChanged: (location) => setState(() => _destination = location),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Supplier',
                    controller: _supplierController,
                    hintText: 'Acme Distributors',
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Supplier is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Reference (optional)',
                    controller: _referenceController,
                    hintText: 'GRN-2026-00042',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(label: 'Notes (optional)', controller: _notesController, maxLines: 3),
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
                        : const Icon(Icons.move_to_inbox_outlined),
                    label: Text(_saving ? 'Receiving…' : 'Receive stock'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_lastReceived != null) ...[
          const SizedBox(height: AppSpacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: MovementConfirmationCard(
              title: 'Received — updated balance',
              productId: _lastReceived!.product.id,
              locations: [
                MovementLocationResult(
                  label: '${_lastReceived!.destination.name} (${_lastReceived!.destination.code})',
                  locationId: _lastReceived!.destination.id,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
