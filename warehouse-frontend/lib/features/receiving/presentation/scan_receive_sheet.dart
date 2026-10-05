import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/scan/scan_code.dart';
import '../../../shared/scan/scan_dialog.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../products/domain/product.dart';
import '../../products/domain/tracking_mode.dart';
import '../../products/presentation/products_list_providers.dart';
import '../../scan/scan_lookup.dart';
import '../data/receiving_providers.dart';

/// "Scan to receive" — a delivery counted by scanning: pick (or scan) the
/// slot, then every scan of a BULK product's label adds 1 to that product's
/// line (quantity stays editable, e.g. for a whole carton). A SERIAL
/// product's label instead just opens its line — its quantity is never
/// typed, only ever the count of distinct unit codes scanned into it via
/// "Scan units" (each unit carries its own code, so the same physical item
/// can't be counted twice). "Receive" records ONE RECEIVE ledger transaction
/// per product (rule 2 — nothing is written until then).
Future<void> showScanReceiveSheet(BuildContext context, {String? locationId}) =>
    showNxSheet<void>(context, kicker: 'Scan to receive', builder: (_) => _ScanReceive(locationId: locationId));

class _Line {
  _Line(this.product) : qty = TextEditingController(text: '0');

  final Product product;

  /// Only meaningful for a BULK line — a SERIAL line's quantity is always
  /// [unitCodes.length], never typed.
  final TextEditingController qty;

  /// Only meaningful for a SERIAL line — the distinct unit codes scanned so far.
  final List<String> unitCodes = [];

  /// Set once this line is recorded (kept on screen, greyed, so a partial
  /// failure shows exactly what went through).
  bool done = false;
  String? error;

  bool get isSerial => product.trackingMode == TrackingMode.serial;
  double get value => isSerial ? unitCodes.length.toDouble() : (double.tryParse(qty.text.trim()) ?? 0);
}

class _ScanReceive extends ConsumerStatefulWidget {
  const _ScanReceive({this.locationId});

  final String? locationId;

  @override
  ConsumerState<_ScanReceive> createState() => _ScanReceiveState();
}

class _ScanReceiveState extends ConsumerState<_ScanReceive> {
  late String? _locationId = widget.locationId;
  final _supplier = TextEditingController();
  final _reference = TextEditingController();
  final List<_Line> _lines = [];
  final Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    _supplier.dispose();
    _reference.dispose();
    for (final l in _lines) {
      l.qty.dispose();
    }
    super.dispose();
  }

  List<_Line> get _pending => _lines.where((l) => !l.done).toList();

  _Line? _lineFor(Product p) => _pending.where((l) => l.product.id == p.id).firstOrNull;

  /// BULK: adds one of [p] (a new line, or +1 on its open line). SERIAL: just opens/keeps its
  /// line (its quantity only ever comes from [_scanUnitsFor]). Returns the line, for feedback.
  _Line _onProductScanned(Product p) {
    final isSerial = p.trackingMode == TrackingMode.serial;
    final existing = _lineFor(p);
    setState(() {
      if (existing != null) {
        if (!isSerial) existing.qty.text = fmtPlain(existing.value + 1);
        return;
      }
      final line = _Line(p);
      if (!isSerial) line.qty.text = '1';
      _lines.insert(0, line);
      _errors.remove('lines');
    });
    return _lineFor(p)!;
  }

  Future<void> _scanItems(List<Product> products) => showScanDialog(
    context,
    title: 'Scan items',
    sub: 'Scan a product label to add it — bulk items add +1 each scan; unit-tracked items open a '
        'line, then use its "Scan units" to add each one.',
    onScan: (code) {
      if (code.kind == ScanKind.unit) {
        return ScanFeedback('That’s a unit’s own code — open its product line below and use “Scan units”.', ok: false);
      }
      final p = matchScannedProduct(code, products);
      if (p == null) {
        return ScanFeedback(
          code.kind == ScanKind.location ? 'That is a location label — scan the products.' : 'No active product has the code “${code.value}”.',
          ok: false,
        );
      }
      final wasOpen = _lineFor(p) != null;
      final line = _onProductScanned(p);
      if (p.trackingMode == TrackingMode.serial) {
        return ScanFeedback(
          wasOpen ? '${p.sku} · ${p.name} — already on this delivery, use “Scan units”' : '${p.sku} · ${p.name} — opened, use “Scan units” to add each one',
        );
      }
      return ScanFeedback('${p.sku} · ${p.name} — ${fmtPlain(line.value)} ${p.uom}');
    },
  );

  /// The per-line loop for a SERIAL product: every scan must be that physical item's OWN code
  /// (never the product label), and the same code can't be scanned twice onto this line — that's
  /// what makes the resulting count a real physical count instead of a guess.
  Future<void> _scanUnitsFor(_Line line) => showScanDialog(
    context,
    title: 'Scan units — ${line.product.name}',
    sub: 'Scan the code on each physical item — never the product’s own label. Keep scanning; close when the delivery is done.',
    onScan: (code) {
      if (code.kind == ScanKind.product) {
        return ScanFeedback('That’s the product label — scan the unique code on the item itself.', ok: false);
      }
      if (code.kind == ScanKind.location) {
        return ScanFeedback('That is a location label — scan the item, not the slot.', ok: false);
      }
      if (line.unitCodes.contains(code.value)) {
        return ScanFeedback('Already scanned on this line.', ok: false);
      }
      setState(() {
        line.unitCodes.add(code.value);
        _errors.remove('lines');
      });
      return ScanFeedback('${line.unitCodes.length} scanned so far');
    },
  );

  Future<void> _receive() async {
    final pending = _pending;
    final errors = <String, String>{
      if (_locationId == null) 'dest': 'Choose or scan the slot',
      if (_supplier.text.trim().isEmpty) 'supplier': 'Supplier is required',
      if (pending.isEmpty) 'lines': 'Scan at least one item',
      if (pending.any((l) => l.value <= 0))
        'lines': 'Every line needs at least one scan (remove the ones you don’t want, or Scan units on a unit-tracked line)',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;

    setState(() => _saving = true);
    final api = ref.read(receivingApiProvider);
    final reference = _reference.text.trim();
    var ok = 0;
    var units = 0.0;
    // One receipt per product. Each line commits on its own, so a failure
    // part-way leaves the recorded lines marked done and the rest to retry.
    for (final l in pending) {
      try {
        await api.receive(
          supplier: _supplier.text.trim(),
          productId: l.product.id,
          quantity: l.isSerial ? null : l.value,
          unitCodes: l.isSerial ? l.unitCodes : null,
          toLocationId: _locationId!,
          reference: reference.isEmpty ? null : reference,
          notes: 'Scanned delivery',
        );
        ok++;
        units += l.value;
        if (mounted) {
          setState(() {
            l.done = true;
            l.error = null;
          });
        }
      } on AppError catch (e) {
        if (mounted) setState(() => l.error = e.message);
      }
    }
    if (ok > 0) invalidateStockViews(ref);
    if (!mounted) return;
    setState(() => _saving = false);
    final leaf = ref.read(leafLocationsProvider).value?.where((x) => x.id == _locationId).firstOrNull;
    final failed = _pending.length;
    if (failed == 0) {
      Navigator.of(context).pop();
      NxToast.ok('Delivery received', '$ok product${ok == 1 ? '' : 's'} · ${fmtNum(units)} units into ${leaf?.code ?? 'the slot'}.');
    } else {
      NxToast.error(
        ok == 0 ? 'Nothing received' : '$ok received, $failed not',
        'Fix or remove the lines marked in red, then receive again — recorded lines are not sent twice.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final products = ref.watch(productsListProvider).value ?? const <Product>[];
    final leaves = ref.watch(leafLocationsProvider);
    final pending = _pending;
    final units = pending.fold<double>(0, (s, l) => s + l.value);

    return NxSheetBody(
      children: [
        Text(
          'Scan each item as it comes off the delivery — every scan adds 1. Nothing is recorded until you press Receive.',
          style: TextStyle(fontSize: 12, color: n.n400, height: 1.4),
        ),
        const SizedBox(height: 12),
        NxField(
          label: 'Into slot',
          required: true,
          error: _errors['dest'],
          child: ScanPicker(
            tooltip: 'Scan the slot',
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
        const SizedBox(height: 10),
        NxField(
          label: 'Supplier',
          required: true,
          error: _errors['supplier'],
          child: NxInput(controller: _supplier, placeholder: 'Required', error: _errors['supplier'] != null),
        ),
        const SizedBox(height: 10),
        NxField(label: 'Reference (optional)', child: NxInput(controller: _reference, placeholder: 'GRN / delivery note no.')),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                pending.isEmpty ? 'No items scanned yet' : '${pending.length} product${pending.length == 1 ? '' : 's'} · ${fmtNum(units)} units',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text),
              ),
            ),
            NxButton.primary(
              label: 'Scan items',
              small: true,
              icon: PhosphorIconsRegular.qrCode,
              onPressed: _saving || products.isEmpty ? null : () => _scanItems(products),
            ),
          ],
        ),
        if (_errors['lines'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_errors['lines']!, style: TextStyle(fontSize: 11, color: n.bad)),
          ),
        const SizedBox(height: 8),
        if (_lines.isNotEmpty)
          NxSection(
            child: Column(
              children: [
                for (final l in _lines)
                  Container(
                    key: ValueKey(l),
                    padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: l.done ? n.n500 : n.text),
                              ),
                              Text(
                                l.done
                                    ? '${l.product.sku} · received'
                                    : l.error ?? '${l.product.sku}${l.isSerial ? ' · unit-tracked' : ' · ${l.product.uom}'}',
                                maxLines: l.error != null ? 4 : 2,
                                style: TextStyle(fontSize: 11, color: l.error != null ? n.bad : (l.done ? n.ok : n.n500)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (l.done)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text('+${fmtPlain(l.value)}', style: TextStyle(fontSize: 13, color: n.ok, fontFeatures: tabular)),
                          )
                        else if (l.isSerial) ...[
                          NxButton(
                            label: '${l.unitCodes.length} scanned',
                            small: true,
                            icon: PhosphorIconsRegular.qrCode,
                            onPressed: _saving ? null : () => _scanUnitsFor(l),
                          ),
                          NxIconButton(
                            icon: PhosphorIconsRegular.x,
                            tooltip: 'Remove line',
                            size: 30,
                            iconSize: 14,
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _lines.remove(l);
                                    l.qty.dispose();
                                  }),
                          ),
                        ] else ...[
                          SizedBox(
                            width: 84,
                            child: NxInput(
                              controller: l.qty,
                              dense: true,
                              enabled: !_saving,
                              textAlign: TextAlign.right,
                              inputFormatters: NxInput.decimals(),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          NxIconButton(
                            icon: PhosphorIconsRegular.x,
                            tooltip: 'Remove line',
                            size: 30,
                            iconSize: 14,
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _lines.remove(l);
                                    l.qty.dispose();
                                  }),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NxButton.primary(
              label: _saving ? 'Receiving…' : 'Receive ${pending.isEmpty ? '' : '${fmtNum(units)} units'}'.trim(),
              icon: PhosphorIconsRegular.boxArrowDown,
              onPressed: _saving ? null : _receive,
            ),
            NxButton.ghost(label: 'Cancel', color: n.n400, onPressed: _saving ? null : () => Navigator.of(context).pop()),
          ],
        ),
      ],
    );
  }
}
