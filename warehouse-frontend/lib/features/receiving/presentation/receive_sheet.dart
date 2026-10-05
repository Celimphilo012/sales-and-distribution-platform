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
import '../../inventory/domain/ledger_entry.dart';
import '../../inventory/presentation/widgets/balance_preview.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/domain/tracking_mode.dart';
import '../../products/presentation/product_options.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/receiving_providers.dart';
import 'scan_receive_sheet.dart';

/// "Receive stock" as a right-hand sheet (from a product, a slot, Inventory…).
Future<void> showReceiveSheet(BuildContext context, {String? productId, String? locationId}) => showNxSheet<void>(
  context,
  kicker: 'Receive stock',
  builder: (_) => SingleChildScrollView(
    padding: const EdgeInsets.all(16),
    child: ReceiveForm(productId: productId, locationId: locationId),
  ),
);

/// The receive form: product, quantity, destination slot, supplier,
/// reference, notes, with a live balance preview. Records ONE RECEIVE
/// transaction. Product and destination are SEARCHABLE pickers.
///
/// [page] lays it out like the prototype's Stock Receiving screen — the form
/// on the left, the balance preview and a "Recent" receipts list on the
/// right — and clears itself after each receipt instead of closing.
class ReceiveForm extends ConsumerStatefulWidget {
  const ReceiveForm({super.key, this.productId, this.locationId, this.page = false});

  final String? productId;
  final String? locationId;
  final bool page;

  @override
  ConsumerState<ReceiveForm> createState() => _ReceiveFormState();
}

class _ReceiveFormState extends ConsumerState<ReceiveForm> {
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

  void _clear() => setState(() {
    _productId = null;
    _locationId = null;
    for (final c in [_qty, _supplier, _reference, _notes]) {
      c.clear();
    }
    _errors.clear();
    _error = null;
  });

  Future<void> _submit(Product? product) async {
    if (product?.trackingMode == TrackingMode.serial) return; // unit-tracked — use Scan to receive instead
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
      final before = ref.read(productLocationBalanceProvider((productId: _productId!, locationId: _locationId!))).value?.onHand ?? 0;
      invalidateStockViews(ref);
      if (!mounted) return;
      final leaf = ref.read(leafLocationsProvider).value?.where((l) => l.id == _locationId).firstOrNull;
      final router = GoRouter.of(context);
      final lists = ref.read(nxListStatesProvider.notifier);
      final pid = _productId!;
      NxToast.ok(
        'Received ${fmtNum(qty)} ${product?.uom ?? ''} of ${product?.name ?? ''}',
        '${leaf?.code ?? ''} on hand is now ${fmtNum(before + qty)}.',
        NxToastAction('View stock', () {
          lists.preset('inventory', filters: {'pid': pid});
          router.go(RoutePaths.inventory);
        }),
      );
      if (widget.page) {
        setState(() {
          _qty.clear();
          _reference.clear();
          _notes.clear();
        });
      } else {
        Navigator.of(context).pop();
      }
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
    final isSerial = product?.trackingMode == TrackingMode.serial;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final before = _productId != null && _locationId != null
        ? ref.watch(productLocationBalanceProvider((productId: _productId!, locationId: _locationId!))).value?.onHand ?? 0
        : 0.0;

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
        if (isSerial)
          NxSpan2(
            child: NxField(
              label: 'Quantity',
              hint: 'This product is unit-tracked — each physical unit carries its own code, scanned in instead of a typed quantity.',
              child: NxButton(
                label: 'Scan to receive instead',
                icon: PhosphorIconsRegular.qrCode,
                onPressed: () {
                  if (!widget.page) Navigator.of(context).pop();
                  showScanReceiveSheet(context, locationId: _locationId);
                },
              ),
            ),
          )
        else
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
          label: widget.page ? 'Destination location' : 'Destination',
          required: true,
          error: _errors['dest'],
          child: ScanPicker(
            tooltip: 'Scan the location',
            onScan: () async {
              final id = await scanLeafId(context, leaves.value ?? const <LeafLocation>[]);
              if (id != null && mounted) setState(() => _locationId = id);
            },
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
        ),
        NxField(
          label: 'Supplier',
          required: true,
          error: _errors['supplier'],
          child: NxInput(controller: _supplier, placeholder: 'Required', error: _errors['supplier'] != null),
        ),
        NxField(label: 'Reference (optional)', child: NxInput(controller: _reference, placeholder: 'GRN-2026-00050')),
        NxSpan2(child: NxField(label: 'Notes (optional)', child: NxInput(controller: _notes, maxLines: 3, minLines: 2))),
      ],
    );

    final preview = BalancePreview(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product == null || leaf == null ? 'Choose a product and a destination' : '${product.name} at ${leaf.pathLabel}',
            style: TextStyle(fontSize: 12, color: n.n400),
          ),
          const SizedBox(height: 4),
          BeforeAfter(before: fmtNum(before), after: fmtNum(before + qty), delta: qty > 0 ? '+${fmtNum(qty)}' : null, deltaColor: n.ok),
          if (leaf != null) ...[
            const SizedBox(height: 2),
            Text('on hand at ${leaf.code}', style: TextStyle(fontSize: 11, color: n.n500)),
          ],
        ],
      ),
    );

    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        NxButton.primary(
          label: _saving ? 'Receiving…' : 'Receive stock',
          icon: PhosphorIconsRegular.boxArrowDown,
          onPressed: _saving || isSerial ? null : () => _submit(product),
        ),
        widget.page
            ? NxButton.ghost(label: 'Clear', color: n.n400, onPressed: _saving ? null : _clear)
            : NxButton.ghost(label: 'Cancel', color: n.n400, onPressed: () => Navigator.of(context).pop()),
      ],
    );
    final error = _error == null ? null : Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)));

    if (!widget.page) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Records a RECEIVE transaction and increases on-hand at the destination.', style: TextStyle(fontSize: 12, color: n.n400)),
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

    final form = NxSection(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields, ?error, const SizedBox(height: 14), buttons]),
    );
    final aside = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [preview, const SizedBox(height: 12), const _RecentPanel(type: 'RECEIVE')],
    );
    return _FormWithAside(form: form, aside: aside);
  }
}

/// The prototype's Receiving / Transfers page layout: the form, and beside it
/// (below it on a phone or tablet) the preview + recent activity column.
class _FormWithAside extends StatelessWidget {
  const _FormWithAside({required this.form, required this.aside});

  final Widget form;
  final Widget aside;

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.of(context).size.width >= 1024;
    if (!desktop) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [form, const SizedBox(height: 12), aside]);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 15, child: form),
        const SizedBox(width: 12),
        Expanded(flex: 10, child: ConstrainedBox(constraints: const BoxConstraints(minWidth: 280), child: aside)),
      ],
    );
  }
}

/// "Recent" — the latest ledger rows of [type] (RECEIVE or TRANSFER): what,
/// where, who, how many, when. Public so the transfer page shows the same panel.
class RecentMovementsPanel extends StatelessWidget {
  const RecentMovementsPanel({super.key, required this.type});

  final String type;

  @override
  Widget build(BuildContext context) => _RecentPanel(type: type);
}

class _RecentPanel extends ConsumerWidget {
  const _RecentPanel({required this.type});

  final String type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(ledgerByTypeProvider(type));
    final receive = type == 'RECEIVE';
    String where(LedgerEntry r) => receive
        ? 'to ${r.toCode ?? '—'}${r.supplier == null ? '' : ' · ${r.supplier}'}'
        : '${r.fromCode ?? '—'} → ${r.toCode ?? '—'}';
    return NxSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Text('Recent', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
          ),
          ...async.when(
            loading: () => [Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 12), child: Text('Loading…', style: TextStyle(fontSize: 12, color: n.n400)))],
            error: (e, _) => [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Text(e is AppError ? e.message : 'Could not load recent activity.', style: TextStyle(fontSize: 12, color: n.bad)),
              ),
            ],
            data: (rows) => rows.isEmpty
                ? [
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
                      child: Text(receive ? 'Nothing received yet.' : 'Nothing transferred yet.', style: TextStyle(fontSize: 12, color: n.n400)),
                    ),
                  ]
                : [
                    for (final r in rows.take(8))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(r.productName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                                  Text(
                                    '${where(r)} · ${r.performedByName ?? '—'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: n.n500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  receive ? '+${fmtNum(r.quantity)}' : fmtNum(r.quantity),
                                  style: TextStyle(fontSize: 13, color: receive ? n.ok : n.text, fontFeatures: tabular),
                                ),
                                Text(fmtWhen(r.createdAt), style: TextStyle(fontSize: 11, color: n.n500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// The form + preview + recent layout, reused by the transfer page.
class FormWithAside extends StatelessWidget {
  const FormWithAside({super.key, required this.form, required this.aside});

  final Widget form;
  final Widget aside;

  @override
  Widget build(BuildContext context) => _FormWithAside(form: form, aside: aside);
}
