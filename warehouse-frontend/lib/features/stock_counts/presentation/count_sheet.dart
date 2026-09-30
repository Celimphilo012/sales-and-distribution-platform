import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/persistence/shared_preferences_provider.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../../shared/scan/scan_code.dart';
import '../../../shared/scan/scan_dialog.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../locations/data/leaf_locations_provider.dart';
import '../../scan/scan_lookup.dart';
import '../../stock_adjustments/data/stock_adjustments_providers.dart';
import '../data/stock_counts_api.dart';
import '../data/stock_counts_providers.dart';
import '../domain/stock_count.dart';

// ─── Drafts ─────────────────────────────────────────────────────────────────

const _draftsKey = 'counts.drafts';

/// Counted quantities typed into an OPEN count but not yet submitted —
/// countId → productId → text. Kept on this device so a long count survives
/// leaving the sheet or reloading the page.
class CountDrafts extends Notifier<Map<String, Map<String, String>>> {
  @override
  Map<String, Map<String, String>> build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_draftsKey);
    if (raw == null) return const {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in decoded.entries) e.key: (e.value as Map<String, dynamic>).map((k, v) => MapEntry(k, '$v'))};
    } on FormatException {
      return const {};
    }
  }

  void set(String countId, String productId, String value) {
    state = {
      ...state,
      countId: {...?state[countId], productId: value},
    };
    _save();
  }

  void clear(String countId) {
    state = {...state}..remove(countId);
    _save();
  }

  void _save() => ref.read(sharedPreferencesProvider).setString(_draftsKey, jsonEncode(state));
}

final countDraftsProvider = NotifierProvider<CountDrafts, Map<String, Map<String, String>>>(CountDrafts.new);

/// "Aisle A › Level 03" — the last two names of a slot's path.
String countLocationName(StockCount c, Map<String, LeafLocation> leaves) {
  final leaf = leaves[c.locationId];
  if (leaf == null || leaf.path.isEmpty) return c.location.name;
  final p = leaf.path;
  return p.length <= 2 ? p.join(' › ') : p.sublist(p.length - 2).join(' › ');
}

// ─── The sheet ──────────────────────────────────────────────────────────────

/// A stock count (the prototype's count sheet): expected vs counted per
/// product with a live variance; submitting sends variances to adjustment
/// review. Stock never moves here.
Future<void> showCountSheet(BuildContext context, String countId) =>
    showNxSheet<void>(context, kicker: 'Stock count', builder: (_) => _CountSheet(countId: countId));

class _CountSheet extends ConsumerStatefulWidget {
  const _CountSheet({required this.countId});

  final String countId;

  @override
  ConsumerState<_CountSheet> createState() => _CountSheetState();
}

class _CountSheetState extends ConsumerState<_CountSheet> {
  final Map<String, TextEditingController> _inputs = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _input(StockCountItem item, bool done, Map<String, String> draft) =>
      _inputs.putIfAbsent(item.productId, () {
        final text = done ? (item.countedQty == null ? '' : fmtPlain(item.countedQty!)) : (draft[item.productId] ?? '');
        return TextEditingController(text: text);
      });

  /// Scan-to-count: every scan of a product label in this count adds 1 to
  /// its counted quantity (kept as a draft like typed entries).
  Future<void> _scanToCount(StockCount c) => showScanDialog(
    context,
    title: 'Scan to count',
    sub: 'Each scan of a product label adds 1 to its count. Type a figure in the sheet for bulk quantities.',
    onScan: (code) {
      final item = code.match(ScanKind.product, c.items, id: (i) => i.productId, code: (i) => i.product.sku);
      if (item == null) {
        return ScanFeedback(
          code.kind == ScanKind.location ? 'That is a location label — scan the products.' : 'Not part of this count (nothing of it was here when the count started).',
          ok: false,
        );
      }
      final ctl = _input(item, false, ref.read(countDraftsProvider)[c.id] ?? const {});
      final next = (double.tryParse(ctl.text.trim()) ?? 0) + 1;
      ctl.text = fmtPlain(next);
      ref.read(countDraftsProvider.notifier).set(c.id, item.productId, ctl.text);
      if (mounted) setState(() {});
      return ScanFeedback('${item.product.sku} · ${item.product.name} — counted ${fmtPlain(next)}');
    },
  );

  Future<void> _submit(StockCount c) async {
    final items = <SubmitCountItem>[];
    for (final i in c.items) {
      final v = double.tryParse(_inputs[i.productId]?.text.trim() ?? '');
      if (v == null || v < 0) {
        final empty = c.items.where((x) => double.tryParse(_inputs[x.productId]?.text.trim() ?? '') == null).length;
        NxToast.warn('Count every item before submitting', '$empty still empty.');
        return;
      }
      items.add(SubmitCountItem(productId: i.productId, countedQty: v));
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final done = await ref.read(stockCountsApiProvider).submit(c.id, items: items);
      ref.read(countDraftsProvider.notifier).clear(c.id);
      ref.invalidate(stockCountsListProvider);
      ref.invalidate(stockCountProvider(c.id));
      ref.invalidate(stockAdjustmentsListProvider);
      invalidateStockViews(ref);
      if (mounted) Navigator.of(context).pop();
      final net = done.items.fold<double>(0, (s, i) => s + (i.difference ?? 0));
      NxToast.ok(
        'Stock count submitted',
        '${c.location.code}${net != 0 ? ' — variance ${fmtSigned(net)} sent for adjustment review.' : ' — no variance.'}',
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
    final async = ref.watch(stockCountProvider(widget.countId));
    final leaves = {for (final l in ref.watch(leafLocationsProvider).value ?? const <LeafLocation>[]) l.id: l};
    final canCount = ref.watch(authProvider.select((s) => s.value?.user?.can('inventory.count') ?? false));
    return async.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(e is AppError ? e.message : 'Could not load this count.', style: TextStyle(color: n.bad)),
      ),
      data: (c) {
        final done = c.status == StockCountStatus.submitted;
        final draft = ref.watch(countDraftsProvider)[c.id] ?? const {};
        double? valueOf(StockCountItem i) => done ? i.countedQty : double.tryParse(_input(i, done, draft).text.trim());
        final counted = c.items.where((i) => valueOf(i) != null).length;
        final total = c.items.length;
        return NxSheetBody(
          children: [
            Text(countLocationName(c, leaves), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text)),
            const SizedBox(height: 2),
            Text(
              '${c.location.code} · started ${fmtDateTime(c.startedAt)} by ${c.startedByUser.fullName}',
              style: TextStyle(fontSize: 12, color: n.n400),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: NxBar(fraction: total == 0 ? 0 : counted / total, height: 6)),
                const SizedBox(width: 8),
                Text('$counted / $total counted', style: TextStyle(fontSize: 12, color: n.n400)),
              ],
            ),
            if (!done && canCount && c.items.isNotEmpty) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: NxButton(label: 'Scan to count', small: true, icon: PhosphorIconsRegular.qrCode, onPressed: () => _scanToCount(c)),
              ),
            ],
            const SizedBox(height: 14),
            if (c.items.isEmpty)
              Text('This location held no stock when the count started.', style: TextStyle(fontSize: 12, color: n.n400))
            else
              NxSection(
                child: Column(
                  children: [
                    _row(
                      context,
                      header: true,
                      product: const Text('PRODUCT'),
                      expected: const Text('EXPECTED', textAlign: TextAlign.right),
                      counted: const Text('COUNTED', textAlign: TextAlign.right),
                      variance: const Text('VAR.', textAlign: TextAlign.right),
                    ),
                    for (final i in c.items)
                      () {
                        final v = valueOf(i);
                        final diff = done ? i.difference : (v == null ? null : v - i.expectedQty);
                        return _row(
                          context,
                          product: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(i.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                              Text(i.product.sku, style: TextStyle(fontSize: 11, color: n.n500)),
                            ],
                          ),
                          expected: Text(fmtNum(i.expectedQty), textAlign: TextAlign.right, style: TextStyle(color: n.n400, fontFeatures: tabular)),
                          counted: NxInput(
                            controller: _input(i, done, draft),
                            enabled: !done && canCount,
                            dense: true,
                            textAlign: TextAlign.right,
                            inputFormatters: NxInput.decimals(),
                            onChanged: (x) {
                              ref.read(countDraftsProvider.notifier).set(c.id, i.productId, x);
                              setState(() {});
                            },
                          ),
                          variance: Text(
                            diff == null ? '' : fmtSigned(diff),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontFeatures: tabular,
                              color: diff == null || diff == 0 ? n.n400 : (diff > 0 ? n.ok : n.bad),
                            ),
                          ),
                        );
                      }(),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)),
            ],
            if (!done && canCount && c.items.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  NxButton.primary(
                    label: _saving ? 'Submitting…' : 'Submit count',
                    icon: PhosphorIconsRegular.check,
                    onPressed: _saving ? null : () => _submit(c),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text('Your entries are kept on this device until you submit.', style: TextStyle(fontSize: 11, color: n.n500)),
                  ),
                ],
              ),
            ],
            if (!done && !canCount) ...[
              const SizedBox(height: 12),
              Text('You can view this count, but recording it needs the inventory.count permission.', style: TextStyle(fontSize: 12, color: n.n400)),
            ],
          ],
        );
      },
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget product,
    required Widget expected,
    required Widget counted,
    required Widget variance,
    bool header = false,
  }) {
    final n = context.nx;
    final style = header
        ? TextStyle(fontSize: 10, letterSpacing: 0.8, color: n.n500)
        : TextStyle(fontSize: 13, color: n.text);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 7 : 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
      child: DefaultTextStyle.merge(
        style: style,
        child: Row(
          children: [
            Expanded(child: product),
            const SizedBox(width: 8),
            SizedBox(width: 62, child: expected),
            const SizedBox(width: 8),
            SizedBox(width: 84, child: counted),
            const SizedBox(width: 8),
            SizedBox(width: 48, child: variance),
          ],
        ),
      ),
    );
  }
}

// ─── Start ──────────────────────────────────────────────────────────────────

/// "Start a stock count": pick a storage slot (SEARCHABLE), snapshot it, and
/// open the new count's sheet.
Future<void> showStartCountDialog(BuildContext context, {String? locationId}) =>
    showNxDialog<void>(context, builder: (_) => _StartCount(locationId: locationId));

class _StartCount extends ConsumerStatefulWidget {
  const _StartCount({this.locationId});

  final String? locationId;

  @override
  ConsumerState<_StartCount> createState() => _StartCountState();
}

class _StartCountState extends ConsumerState<_StartCount> {
  late String? _loc = widget.locationId;
  bool _saving = false;
  String? _error;

  Future<void> _start() async {
    if (_loc == null) {
      setState(() => _error = 'Choose a location');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final c = await ref.read(stockCountsApiProvider).start(locationId: _loc!);
      ref.invalidate(stockCountsListProvider);
      if (!mounted) return;
      final nav = Navigator.of(context);
      final root = nav.context;
      nav.pop();
      NxToast.ok('Stock count started', '${c.items.length} products snapshotted at ${c.location.code}.');
      if (root.mounted) showCountSheet(root, c.id);
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final leaves = ref.watch(leafLocationsProvider);
    return NxDialogFrame(
      title: 'Start a stock count',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Snapshots the current on-hand quantity for every product with a balance at the chosen location. Only a storage slot (leaf location) can be counted.',
            style: TextStyle(fontSize: 13, color: n.text.withValues(alpha: 0.85), height: 1.5),
          ),
          const SizedBox(height: 12),
          NxField(
            label: 'Location',
            error: _error,
            child: ScanPicker(
              tooltip: 'Scan the location',
              onScan: () async {
                final id = await scanLeafId(context, leaves.value ?? const <LeafLocation>[]);
                if (id != null && mounted) setState(() => _loc = id);
              },
              child: NxSelect<String>(
                options: [for (final l in leaves.value ?? const <LeafLocation>[]) l.option()],
                value: _loc,
                searchable: true,
                searchPlaceholder: 'Search slots by code or name',
                placeholder: leaves.isLoading ? 'Loading locations…' : 'Choose a slot',
                error: _error != null,
                onChanged: (v) => setState(() => _loc = v),
              ),
            ),
          ),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Starting…' : 'Start count', onPressed: _saving ? null : _start),
      ],
    );
  }
}
