import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../shared/scan/scan_dialog.dart';
import '../../scan/scan_lookup.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_balance.dart';
import '../../inventory/presentation/widgets/balance_preview.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/product_options.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../receiving/presentation/receive_sheet.dart' show FormWithAside, RecentMovementsPanel;
import '../data/transfers_providers.dart';

/// "Transfer stock" — the prototype's transfer sheet: a SEARCHABLE product,
/// the slots where it has stock (with what's available at each) to move
/// from, quantity, a SEARCHABLE destination, and a before → after preview of
/// both ends. Records ONE TRANSFER transaction.
Future<void> showTransferSheet(BuildContext context, {String? productId, String? fromLocationId}) => showNxSheet<void>(
  context,
  kicker: 'Transfer stock',
  builder: (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: TransferForm(productId: productId, fromLocationId: fromLocationId),
  ),
);

/// The transfer form. [page] lays it out like the prototype's Stock Transfers
/// screen — the form on the left, the balance preview and "Recent" transfers
/// on the right — and clears itself after each transfer instead of closing.
class TransferForm extends ConsumerStatefulWidget {
  const TransferForm({super.key, this.productId, this.fromLocationId, this.page = false});

  final String? productId;
  final String? fromLocationId;
  final bool page;

  @override
  ConsumerState<TransferForm> createState() => _TransferFormState();
}

class _TransferFormState extends ConsumerState<TransferForm> {
  late String? _productId = widget.productId;
  late String? _from = widget.fromLocationId;
  String? _to;
  final _qty = TextEditingController();
  final _reference = TextEditingController();
  final _reason = TextEditingController();
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_qty, _reference, _reason]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({required Product? product, required double available, required Map<String, LeafLocation> leaves}) async {
    final qty = double.tryParse(_qty.text.trim());
    final errors = <String, String>{
      if (_productId == null) 'product': 'Choose a product',
      if (_from == null) 'from': 'Choose where it comes from',
      if (qty == null || qty <= 0) 'qty': 'Enter a quantity above 0',
      if (qty != null && qty > available && _from != null) 'qty': 'Only ${fmtNum(available)} available at the source',
      if (_to == null) 'to': 'Choose a destination',
      if (_to != null && _to == _from) 'to': 'Source and destination are the same location',
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
      await ref.read(transfersApiProvider).transfer(
        productId: _productId!,
        quantity: qty!,
        fromLocationId: _from!,
        toLocationId: _to!,
        reference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      invalidateStockViews(ref);
      if (!mounted) return;
      final router = GoRouter.of(context);
      final lists = ref.read(nxListStatesProvider.notifier);
      final pid = _productId!;
      final route = '${leaves[_from]?.code ?? ''} → ${leaves[_to]?.code ?? ''}';
      if (widget.page) {
        setState(() {
          _qty.clear();
          _reference.clear();
          _reason.clear();
        });
      } else {
        Navigator.of(context).pop();
      }
      NxToast.ok(
        'Moved ${fmtNum(qty)} ${product?.uom ?? ''} of ${product?.name ?? ''}',
        route,
        NxToastAction('View stock', () {
          lists.preset('inventory', filters: {'pid': pid});
          router.go(RoutePaths.inventory);
        }),
      );
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
    final leavesList = ref.watch(leafLocationsProvider).value ?? const <LeafLocation>[];
    final leaves = {for (final l in leavesList) l.id: l};
    final balances = ref.watch(allBalancesProvider).value ?? const <InventoryBalance>[];
    final product = products.where((p) => p.id == _productId).firstOrNull;
    final sources = balances.where((b) => b.productId == _productId && b.available > 0).toList()
      ..sort((a, b) => (leaves[a.locationId]?.code ?? a.location.code).compareTo(leaves[b.locationId]?.code ?? b.location.code));
    final fromRow = balances.where((b) => b.productId == _productId && b.locationId == _from).firstOrNull;
    final toRow = balances.where((b) => b.productId == _productId && b.locationId == _to).firstOrNull;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final available = fromRow?.available ?? 0;
    String code(String? id) => id == null ? '—' : (leaves[id]?.code ?? balances.where((b) => b.locationId == id).firstOrNull?.location.code ?? '—');

    final fields = NxFormGrid(
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
                    if (id != null && mounted) {
                      setState(() {
                        _productId = id;
                        _from = null;
                      });
                    }
                  },
                  child: NxSelect<String>(
                    options: productOptions(products, keepId: _productId),
                    value: _productId,
                    searchable: true,
                    searchPlaceholder: 'Search by SKU or name',
                    placeholder: 'Choose a product',
                    error: _errors['product'] != null,
                    onChanged: (v) => setState(() {
                      _productId = v;
                      _from = null;
                    }),
                  ),
                ),
              ),
            ),
            NxSpan2(
              child: NxField(
                label: 'From — where this product has stock',
                required: true,
                error: _errors['from'],
                child: _productId == null
                    ? Text('Choose a product first.', style: TextStyle(fontSize: 12, color: n.n400))
                    : sources.isEmpty
                    ? Text('This product has no available stock anywhere.', style: TextStyle(fontSize: 12, color: n.n400))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final b in sources)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: _SourceOption(
                                label: leaves[b.locationId]?.label ?? '${b.location.code} — ${b.location.name}',
                                available: '${fmtNum(b.available)} avail.',
                                selected: b.locationId == _from,
                                onTap: () => setState(() => _from = b.locationId),
                              ),
                            ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: NxButton.ghost(
                              label: 'Scan the source slot',
                              icon: PhosphorIconsRegular.qrCode,
                              small: true,
                              onPressed: () async {
                                final held = sources.map((b) => leaves[b.locationId]).whereType<LeafLocation>();
                                final id = await scanLeafId(context, held);
                                if (id != null && mounted) setState(() => _from = id);
                              },
                            ),
                          ),
                        ],
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
              label: 'To location',
              required: true,
              error: _errors['to'],
              child: ScanPicker(
                tooltip: 'Scan the destination',
                onScan: () async {
                  final id = await scanLeafId(context, leavesList.where((l) => l.id != _from));
                  if (id != null && mounted) setState(() => _to = id);
                },
                child: NxSelect<String>(
                  options: [for (final l in leavesList.where((l) => l.id != _from)) l.option()],
                  value: _to,
                  searchable: true,
                  searchPlaceholder: 'Search slots by code or name',
                  placeholder: 'Choose a slot',
                  error: _errors['to'] != null,
                  onChanged: (v) => setState(() => _to = v),
                ),
              ),
            ),
            NxField(label: 'Reference (optional)', child: NxInput(controller: _reference, placeholder: 'TRF-…')),
            NxField(label: 'Reason (optional)', child: NxInput(controller: _reason, placeholder: 'Putaway, replenish pick face…')),
          ],
        );
    final preview = BalancePreview(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PreviewLine(label: 'From ${code(_from)}', before: fromRow?.onHand ?? 0, after: (fromRow?.onHand ?? 0) - qty),
              const SizedBox(height: 6),
              _PreviewLine(label: 'To ${code(_to)}', before: toRow?.onHand ?? 0, after: (toRow?.onHand ?? 0) + qty),
              const SizedBox(height: 6),
              Text('${fmtNum(available)} available to move from the source', style: TextStyle(fontSize: 11, color: n.n500)),
              if (_from != null && qty > available) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(PhosphorIconsRegular.warning, size: 13, color: n.warn),
                    const SizedBox(width: 4),
                    Text('Quantity is more than what’s available.', style: TextStyle(fontSize: 12, color: n.warn)),
                  ],
                ),
              ],
            ],
          ),
        );
    final error = _error == null
        ? null
        : Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)));
    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        NxButton.primary(
          label: _saving ? 'Moving…' : 'Transfer stock',
          icon: PhosphorIconsRegular.arrowsLeftRight,
          onPressed: _saving ? null : () => _submit(product: product, available: available, leaves: leaves),
        ),
        if (widget.page)
          NxButton.ghost(label: 'Clear', color: n.n400, onPressed: _saving ? null : _clear)
        else
          NxButton.ghost(label: 'Cancel', color: n.n400, onPressed: () => Navigator.of(context).pop()),
      ],
    );

    if (!widget.page) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Moves available stock between two locations as one TRANSFER transaction.', style: TextStyle(fontSize: 12, color: n.n400)),
          const SizedBox(height: 12),
          fields,
          const SizedBox(height: 14),
          preview,
          ?error,
          const SizedBox(height: 14),
          buttons,
        ],
      );
    }
    return FormWithAside(
      form: NxSection(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields, ?error, const SizedBox(height: 14), buttons]),
      ),
      aside: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [preview, const SizedBox(height: 12), const RecentMovementsPanel(type: 'TRANSFER')],
      ),
    );
  }

  void _clear() => setState(() {
    _productId = null;
    _from = null;
    _to = null;
    for (final c in [_qty, _reference, _reason]) {
      c.clear();
    }
    _errors.clear();
    _error = null;
  });
}

class _SourceOption extends StatelessWidget {
  const _SourceOption({required this.label, required this.available, required this.selected, required this.onTap});

  final String label;
  final String available;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Material(
      color: selected ? n.accent.withValues(alpha: 0.08) : Colors.transparent,
      borderRadius: BorderRadius.circular(NxRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NxRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NxRadius.md),
            border: Border.all(color: selected ? n.accent : n.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: selected ? n.accent : n.divider, width: 1.5),
                ),
                padding: const EdgeInsets.all(2.5),
                child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? n.accent : Colors.transparent)),
              ),
              const SizedBox(width: 9),
              Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text))),
              const SizedBox(width: 9),
              Text(available, style: TextStyle(fontSize: 12, color: n.n400, fontFeatures: tabular)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreviewLine extends StatelessWidget {
  const _PreviewLine({required this.label, required this.before, required this.after});

  final String label;
  final double before;
  final double after;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: 110, child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n400))),
        Expanded(child: BeforeAfter(before: fmtNum(before), after: fmtNum(after), large: false)),
      ],
    );
  }
}
