import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/quantity_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_balance.dart';
import '../../inventory/domain/product_location_stock.dart';
import '../../inventory/presentation/widgets/movement_confirmation_card.dart';
import '../../locations/domain/location.dart';
import '../../locations/presentation/widgets/leaf_location_field.dart';
import '../data/transfers_providers.dart';
import 'widgets/transfer_product_field.dart';
import 'widgets/transfer_source_chooser.dart';

/// STEP 6e-1 — TRANSFERS: moves stock between two leaf locations in one
/// TRANSFER transaction (-qty from, +qty to — atomic on the backend, §H
/// point 3). Same-location transfers are rejected both here (the FROM/TO
/// pickers exclude each other's current pick) and on the backend (400,
/// surfaced verbatim if it ever slips through a race).
///
/// The product and From location inform each other, in either order:
///  * product first → the form looks up where that product is stocked; if
///    exactly one location holds it, From is filled in automatically, and if
///    several do, they're offered to choose from;
///  * From first → the product field lists the items held in that location
///    (searchable), so only movable stock can be picked.
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

  InventoryBalanceProductRef? _product;

  /// The From location the USER chose. When null, the effective From may
  /// still be auto-detected — see [_autoFrom].
  Location? _from;
  Location? _to;
  bool _saving = false;
  String? _errorMessage;

  ({InventoryBalanceProductRef product, Location from, Location to})? _lastTransfer;

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  /// Locations that currently hold on-hand stock of the chosen product —
  /// only looked up while the user hasn't picked a From themselves. [listen]
  /// is true from `build` (subscribes so the UI updates) and false from
  /// event handlers (reads the already-loaded value).
  List<ProductLocationStock> _sourcesFor({required bool listen}) {
    final product = _product;
    if (product == null || _from != null) return const [];
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
  /// it recomputes; pick a From yourself and yours wins.
  Location? _autoFrom(List<ProductLocationStock> sources) =>
      sources.length == 1 && sources.first.path.isNotEmpty ? sources.first.path.last : null;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final product = _product;
    final from = _from ?? _autoFrom(_sourcesFor(listen: false));
    final to = _to;
    if (product == null) {
      setState(() => _errorMessage = 'Choose a product.');
      return;
    }
    if (from == null || to == null) {
      setState(() => _errorMessage = 'Choose both a from and a to location.');
      return;
    }
    if (from.id == to.id) {
      setState(() => _errorMessage = 'The from and to locations must be different.');
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

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
        // Ready for the next item from the same place: keep the From
        // (its item list refreshes with the new balances), clear the rest.
        _from = from;
        _product = null;
        _to = null;
        _quantityController.clear();
        _reasonController.clear();
        _referenceController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transferred ${formatQuantity(quantity)} ${product.uom} of ${product.name}')),
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
    final product = _product;

    final sourcesAsync = (product != null && _from == null) ? ref.watch(productStockBreakdownProvider(product.id)) : null;
    final sources = _sourcesFor(listen: true);
    final autoFrom = _autoFrom(sources);
    final from = _from ?? autoFrom;

    // The chosen product's balance at the effective From — drives the
    // "available" hint, the quantity ceiling and the not-stocked-here error.
    final fromBalancesAsync = from != null ? ref.watch(locationBalancesProvider(from.id)) : null;
    InventoryBalance? atFrom;
    if (product != null) {
      for (final b in fromBalancesAsync?.value ?? const <InventoryBalance>[]) {
        if (b.productId == product.id) atFrom = b;
      }
    }
    final notStockedAtFrom =
        product != null && from != null && fromBalancesAsync?.hasValue == true && (atFrom == null || atFrom.onHand <= 0);
    final sameLocation = from != null && _to != null && from.id == _to!.id;

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
                  TransferProductField(
                    from: from,
                    value: product,
                    onChanged: (picked) => setState(() {
                      _product = picked;
                      _errorMessage = null;
                    }),
                    onClear: () => setState(() => _product = null),
                    errorText: notStockedAtFrom ? 'No stock of this item in ${from.name}' : null,
                  ),
                  if (product != null && _from == null) ...[
                    if (sourcesAsync?.isLoading ?? false)
                      const Padding(
                        padding: EdgeInsets.only(top: AppSpacing.sm),
                        child: LinearProgressIndicator(),
                      )
                    else if (sourcesAsync?.hasError ?? false)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          'Could not look up where this item is stored — choose the From location manually.',
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      )
                    else if (sources.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          'No stock of this item on hand in any location — there is nothing to transfer.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                        ),
                      )
                    else if (sources.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: TransferSourceChooser(
                          product: product,
                          sources: sources,
                          onPick: (location) => setState(() => _from = location),
                        ),
                      ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  LeafLocationField(
                    label: 'From location',
                    value: from,
                    excludeLocationId: _to?.id,
                    onChanged: (location) => setState(() => _from = location),
                  ),
                  if (_from == null && autoFrom != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        'Detected automatically — the only location holding ${product!.name}. Change it to override.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  AppNumberField(
                    label: 'Quantity',
                    controller: _quantityController,
                    allowDecimal: true,
                    helperText: atFrom != null
                        ? 'Available here: ${formatQuantity(atFrom.available)} ${product!.uom}'
                        : null,
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a quantity greater than 0';
                      if (atFrom != null && n > atFrom.available) {
                        return 'Only ${formatQuantity(atFrom.available)} ${product!.uom} available here';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LeafLocationField(
                    label: 'To location',
                    value: _to,
                    excludeLocationId: from?.id,
                    onChanged: (location) => setState(() => _to = location),
                    errorText: sameLocation ? 'Must differ from the from location' : null,
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
                    onPressed: (_saving || notStockedAtFrom) ? null : _submit,
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
