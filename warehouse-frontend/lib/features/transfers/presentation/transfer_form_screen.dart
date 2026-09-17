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
import '../data/transfers_providers.dart';

/// STEP 6e-1 — TRANSFERS: moves stock between two leaf locations in one
/// TRANSFER transaction (-qty from, +qty to — atomic on the backend, §H
/// point 3). Same-location transfers are rejected both here (the FROM/TO
/// pickers exclude each other's current pick) and on the backend (400,
/// surfaced verbatim if it ever slips through a race).
class TransferFormScreen extends ConsumerWidget {
  const TransferFormScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canTransfer = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.transfer') ?? false));
    if (!canTransfer) {
      return const EmptyStateView(
        title: "You don't have permission to transfer stock",
        message: 'Ask an administrator for the inventory.transfer permission.',
        icon: Icons.lock_outline,
      );
    }
    return const _TransferFormBody();
  }
}

class _TransferFormBody extends ConsumerStatefulWidget {
  const _TransferFormBody();

  @override
  ConsumerState<_TransferFormBody> createState() => _TransferFormBodyState();
}

class _TransferFormBodyState extends ConsumerState<_TransferFormBody> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _referenceController = TextEditingController();

  Product? _product;
  Location? _from;
  Location? _to;
  bool _saving = false;
  String? _errorMessage;

  ({Product product, Location from, Location to})? _lastTransfer;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  bool get _sameLocation => _from != null && _to != null && _from!.id == _to!.id;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_product == null) {
      setState(() => _errorMessage = 'Choose a product.');
      return;
    }
    if (_from == null || _to == null) {
      setState(() => _errorMessage = 'Choose both a from and a to location.');
      return;
    }
    if (_sameLocation) {
      setState(() => _errorMessage = 'The from and to locations must be different.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    final product = _product!;
    final from = _from!;
    final to = _to!;
    try {
      final quantity = double.parse(_quantityController.text.trim());
      await ref.read(transfersApiProvider).transfer(
        productId: product.id,
        quantity: quantity,
        fromLocationId: from.id,
        toLocationId: to.id,
        reason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
        reference: _referenceController.text.trim().isEmpty ? null : _referenceController.text.trim(),
      );

      ref.invalidate(productLocationBalanceProvider((productId: product.id, locationId: from.id)));
      ref.invalidate(productLocationBalanceProvider((productId: product.id, locationId: to.id)));
      ref.invalidate(locationBalancesProvider(from.id));
      ref.invalidate(locationBalancesProvider(to.id));
      ref.invalidate(productStockBreakdownProvider(product.id));

      if (!mounted) return;
      setState(() {
        _lastTransfer = (product: product, from: from, to: to);
        _product = null;
        _from = null;
        _to = null;
        _quantityController.clear();
        _reasonController.clear();
        _referenceController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transferred ${quantity.toString()} ${product.uom} of ${product.name}')),
      );
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
        Text('Stock Transfers', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Form(
            key: _formKey,
            child: AppCard(
              title: 'Transfer stock',
              subtitle: 'Records one TRANSFER transaction: on-hand moves from one leaf location to another.',
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
                    label: 'From location',
                    value: _from,
                    excludeLocationId: _to?.id,
                    onChanged: (location) => setState(() => _from = location),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LeafLocationField(
                    label: 'To location',
                    value: _to,
                    excludeLocationId: _from?.id,
                    onChanged: (location) => setState(() => _to = location),
                    errorText: _sameLocation ? 'Must differ from the from location' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(label: 'Reason (optional)', controller: _reasonController),
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
                        : const Icon(Icons.swap_horiz_outlined),
                    label: Text(_saving ? 'Transferring…' : 'Transfer stock'),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_lastTransfer != null) ...[
          const SizedBox(height: AppSpacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: MovementConfirmationCard(
              title: 'Transferred — updated balances',
              productId: _lastTransfer!.product.id,
              locations: [
                MovementLocationResult(
                  label: '${_lastTransfer!.from.name} (${_lastTransfer!.from.code}) — from',
                  locationId: _lastTransfer!.from.id,
                ),
                MovementLocationResult(
                  label: '${_lastTransfer!.to.name} (${_lastTransfer!.to.code}) — to',
                  locationId: _lastTransfer!.to.id,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
