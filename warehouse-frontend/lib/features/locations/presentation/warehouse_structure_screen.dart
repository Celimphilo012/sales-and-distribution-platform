import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_balance.dart';
import '../../products/presentation/product_sheet.dart';
import '../../receiving/presentation/receive_sheet.dart';
import '../../stock_counts/presentation/count_sheet.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/leaf_locations_provider.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';
import 'location_dialogs.dart';

/// One location with everything the structure views show about it.
class _Loc {
  _Loc(this.l, {required this.depth, required this.leaf, required this.path, required this.units, required this.cap, required this.kids, required this.skus});

  final Location l;
  final int depth;
  final bool leaf;
  final List<String> path;
  final double units;

  /// Summed slot capacity (a leaf's own; 0 when none is set).
  final double cap;
  final List<String> kids;
  final int skus;

  String get id => l.id;
  bool get inactive => !l.isActive;
  double get util => cap > 0 ? units / cap : 0;
  String get area => path.isEmpty ? l.name : path.first;
}

/// The warehouse's location tree, indexed: depth-first order, leaf flags,
/// units (on hand) and capacity rolled up from the slots.
class _Index {
  _Index(List<Location> all, List<InventoryBalance> balances) {
    final byId = {for (final l in all) l.id: l};
    final kids = <String, List<String>>{};
    for (final l in all) {
      if (l.parentId != null && byId.containsKey(l.parentId)) kids.putIfAbsent(l.parentId!, () => []).add(l.id);
    }
    int byCode(String a, String b) => byId[a]!.code.compareTo(byId[b]!.code);
    for (final list in kids.values) {
      list.sort(byCode);
    }
    final onHand = <String, double>{};
    final skus = <String, int>{};
    for (final b in balances) {
      onHand[b.locationId] = (onHand[b.locationId] ?? 0) + b.onHand;
      if (b.onHand > 0 || b.reserved > 0) skus[b.locationId] = (skus[b.locationId] ?? 0) + 1;
    }
    final units = <String, double>{};
    final caps = <String, double>{};
    double u(String id) => units[id] ??= (kids[id] ?? const []).isEmpty
        ? (onHand[id] ?? 0)
        : kids[id]!.fold<double>(0, (s, k) => s + u(k));
    double c(String id) => caps[id] ??= (kids[id] ?? const []).isEmpty
        ? (byId[id]!.isActive ? (byId[id]!.capacity ?? 0).toDouble() : 0)
        : kids[id]!.fold<double>(0, (s, k) => s + c(k));
    void walk(String id, int depth, List<String> trail) {
      final l = byId[id]!;
      final path = [...trail, l.name];
      final node = _Loc(
        l,
        depth: depth,
        leaf: (kids[id] ?? const []).isEmpty,
        path: path,
        units: u(id),
        cap: c(id),
        kids: kids[id] ?? const [],
        skus: skus[id] ?? 0,
      );
      this.byId[id] = node;
      list.add(node);
      for (final k in node.kids) {
        walk(k, depth + 1, path);
      }
    }

    final roots = all.where((l) => l.parentId == null || !byId.containsKey(l.parentId)).map((l) => l.id).toList()..sort(byCode);
    for (final r in roots) {
      walk(r, 0, const []);
    }
  }

  final Map<String, _Loc> byId = {};
  final List<_Loc> list = [];
}

/// Warehouse Structure (prototype `locations`): the location tree of one
/// warehouse as a fill MAP, an expandable TREE, or a table / list / grid,
/// beside a detail panel for the selected location (its facts, actions and
/// the stock it holds). Types are free labels; depth is unlimited.
class WarehouseStructureScreen extends ConsumerStatefulWidget {
  const WarehouseStructureScreen({super.key, this.initialWarehouseId});

  final String? initialWarehouseId;

  @override
  ConsumerState<WarehouseStructureScreen> createState() => _WarehouseStructureScreenState();
}

class _WarehouseStructureScreenState extends ConsumerState<WarehouseStructureScreen> {
  late String? _warehouseId = widget.initialWarehouseId;
  bool _showInactive = false;
  String? _selected;
  final Set<String> _collapsed = {};

  void _refresh(String warehouseId) {
    invalidateWarehouseLocations(ref, warehouseId);
    ref.invalidate(leafLocationsProvider);
    ref.invalidate(allBalancesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final warehousesAsync = ref.watch(warehousesProvider(true));
    return NxPageScroll(
      onRefresh: () async {
        invalidateWarehouses(ref);
        if (_warehouseId != null) _refresh(_warehouseId!);
      },
      child: warehousesAsync.when(
        loading: () => const NxLoading(message: 'Loading warehouses…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load warehouses.',
          onRetry: () => invalidateWarehouses(ref),
        ),
        data: (warehouses) {
          if (warehouses.isEmpty) {
            return const NxError(message: 'No warehouses yet — create one from Warehouses first.');
          }
          final wh = warehouses.where((w) => w.id == _warehouseId).firstOrNull ??
              warehouses.where((w) => w.isActive).firstOrNull ??
              warehouses.first;
          return _structure(context, wh, warehouses);
        },
      ),
    );
  }

  Widget _structure(BuildContext context, Warehouse wh, List<Warehouse> warehouses) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canManage = user?.can('warehouse.structure.manage') ?? false;
    final locsAsync = ref.watch(warehouseLocationsProvider((warehouseId: wh.id, includeInactive: true)));
    final balances = ref.watch(allBalancesProvider).value ?? const <InventoryBalance>[];

    return locsAsync.when(
      loading: () => const NxLoading(message: 'Loading the location tree…'),
      error: (e, _) => NxError(
        message: e is AppError ? e.message : 'Could not load locations.',
        onRetry: () => _refresh(wh.id),
      ),
      data: (all) {
        final idx = _Index(all, balances.where((b) => b.location.warehouseId == wh.id).toList());
        final rows = idx.list.where((r) => _showInactive || !r.inactive).toList();
        final types = {for (final l in all) l.locationType}.toList()..sort();
        final sel = idx.byId[_selected] ?? (rows.isEmpty ? null : rows.first);

        void select(_Loc r) => setState(() => _selected = r.id);
        NxTag status(_Loc r) => NxTag(r.inactive ? 'Inactive' : 'Active', tone: r.inactive ? Tone.neutral : Tone.ok);
        String pctS(_Loc r) => r.cap > 0 ? '${(r.util * 100).round()}%' : '—';
        Color fillColor(_Loc r) => r.util > 0.9 ? n.warn : n.a500;

        final picker = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              child: NxSelect<String>(
                dense: true,
                options: [
                  for (final w in warehouses) NxOption(w.id, '${w.name} (${w.code})', sub: w.isActive ? null : 'inactive'),
                ],
                value: wh.id,
                onChanged: (v) => setState(() {
                  _warehouseId = v;
                  _selected = null;
                  _collapsed.clear();
                }),
              ),
            ),
            NxChipToggle(
              label: 'Show inactive',
              selected: _showInactive,
              showCheck: true,
              onTap: () => setState(() => _showInactive = !_showInactive),
            ),
          ],
        );

        List<NxRowAction> rowActions(_Loc r) => [
          if (canManage) ...[
            NxRowAction(icon: PhosphorIconsRegular.plus, label: 'Add child', onPressed: () => showLocationForm(context, warehouseId: wh.id, parent: r.l, all: all)),
            NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showLocationForm(context, warehouseId: wh.id, location: r.l, all: all)),
            NxRowAction(icon: PhosphorIconsRegular.arrowsOutCardinal, label: 'Move', onPressed: () => showMoveLocation(context, location: r.l, all: all)),
          ],
        ];

        return NxListPage<_Loc>(
          stateKey: 'locations',
          title: 'Warehouse Structure',
          sub: '${wh.name} (${wh.code}) · any depth; types are free labels',
          views: const [NxView.map, NxView.tree, NxView.table, NxView.list, NxView.grid],
          actions: [
            if (canManage)
              NxButton.primary(label: 'Add location', icon: PhosphorIconsRegular.plus, onPressed: () => showLocationForm(context, warehouseId: wh.id, all: all)),
          ],
          rows: rows,
          search: (r) => '${r.l.name} ${r.l.code}',
          searchPlaceholder: 'Name or code',
          stats: (rs) {
            final leaves = rs.where((r) => r.leaf).toList();
            final cap = leaves.fold<double>(0, (s, r) => s + r.cap);
            final units = leaves.fold<double>(0, (s, r) => s + r.units);
            final nearFull = leaves.where((r) => r.util > 0.9).length;
            return [
              NxStat('Locations', fmtNum(rs.length), sub: '${rs.where((r) => r.inactive).length} inactive'),
              NxStat('Storage slots', fmtNum(leaves.length), sub: 'leaf locations'),
              NxStat('Units stored', fmtNum(units)),
              NxStat('Utilisation', cap > 0 ? '${(units / cap * 100).round()}%' : '—', sub: cap > 0 ? 'of ${fmtNum(cap)} capacity' : 'no capacities set'),
              NxStat('Empty slots', fmtNum(leaves.where((r) => r.units == 0 && !r.inactive).length), sub: 'ready for putaway', color: n.a300),
              NxStat('Near full', fmtNum(nearFull), sub: 'over 90%', color: nearFull > 0 ? n.warn : null),
            ];
          },
          filters: [
            NxMultiFilter('type', 'Type', options: [for (final t in types) (t, t)], get: (r) => r.l.locationType),
            NxSelectFilter('aisle', 'Top-level area', options: [for (final r in idx.list.where((r) => r.depth == 0)) (r.l.name, r.l.name)], get: (r) => r.area),
            NxRangeFilter('util', 'Utilisation %', get: (r) => (r.util * 100).round()),
            NxToggleFilter('leaf', 'Slots', text: 'Storage slots only', get: (r) => r.leaf),
          ],
          aboveContent: picker,
          columns: [
            NxColumn(
              key: 'name',
              label: 'Location',
              cell: (r) => Padding(
                padding: EdgeInsets.only(left: r.depth * 14.0),
                child: NxCellText(r.l.name, weight: r.leaf ? FontWeight.w400 : FontWeight.w500, sub: r.l.code),
              ),
            ),
            NxColumn(key: 'type', label: 'Type', sort: (r) => r.l.locationType, cell: (r) => Align(alignment: Alignment.centerLeft, child: NxTag(r.l.locationType))),
            NxColumn(key: 'path', label: 'Path', hide: NxHide.wide, cell: (r) => NxCellText(r.path.join(' › '), color: n.n400)),
            NxColumn(key: 'units', label: 'Units', align: TextAlign.right, sort: (r) => r.units, cell: (r) => NxCellText(fmtNum(r.units), align: TextAlign.right)),
            NxColumn(
              key: 'util',
              label: 'Fill',
              width: 150,
              hide: NxHide.md,
              sort: (r) => r.util,
              cell: (r) => r.cap > 0 ? NxLabeledBar(label: pctS(r), fraction: r.util, color: fillColor(r)) : NxCellText('—', color: n.n500),
            ),
            NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
            if (canManage) NxColumn(key: 'act', label: '', width: 104, cell: (r) => NxRowActions(rowActions(r))),
          ],
          listRow: (r) => NxListRowSpec(
            icon: r.leaf ? PhosphorIconsDuotone.cube : PhosphorIconsDuotone.folderSimple,
            iconColor: r.leaf ? n.n500 : n.a400,
            title: '${r.l.name} · ${r.l.code}',
            sub: r.path.join(' › '),
            right: fmtNum(r.units),
            rightSub: r.cap > 0 ? '${pctS(r)} full' : r.l.locationType,
            tag: r.inactive ? status(r) : null,
          ),
          card: (r) => NxCardSpec(
            icon: r.leaf ? PhosphorIconsDuotone.cube : PhosphorIconsDuotone.folderSimple,
            title: r.l.name,
            sub: '${r.l.code} · ${r.l.locationType}',
            metrics: [('Units', fmtNum(r.units), null), (r.leaf ? 'Capacity' : 'Children', r.leaf ? (r.cap > 0 ? fmtNum(r.cap) : '—') : fmtNum(r.kids.length), null)],
            tag: r.inactive ? status(r) : null,
            bar: r.cap > 0 ? r.util.clamp(0, 1).toDouble() : null,
            barColor: fillColor(r),
          ),
          // Table / list / grid: opening a row shows it in the tree beside its details.
          onOpen: (r) {
            select(r);
            ref.read(nxListStatesProvider.notifier).update('locations', (s) => s.copyWith(view: () => NxView.tree));
          },
          emptyTitle: 'No locations match',
          emptyMessage: 'Adjust filters, or add a root location.',
          contentOverride: (filtered, view) {
            if (view != NxView.map && view != NxView.tree) return null;
            final main = view == NxView.map
                ? _StructureMap(idx: idx, showInactive: _showInactive, selected: sel?.id, onSelect: select)
                : _StructureTree(
                    idx: idx,
                    visible: {for (final r in filtered) r.id},
                    collapsed: _collapsed,
                    selected: sel?.id,
                    onSelect: select,
                    onToggle: (id) => setState(() => _collapsed.contains(id) ? _collapsed.remove(id) : _collapsed.add(id)),
                  );
            final detail = sel == null
                ? NxSection(
                    padding: const EdgeInsets.all(16),
                    child: Text('No locations yet — add a root location to start.', style: TextStyle(fontSize: 13, color: n.n400)),
                  )
                : _Detail(
                    loc: sel,
                    idx: idx,
                    all: all,
                    warehouseId: wh.id,
                    balances: balances.where((b) => b.locationId == sel.id).toList(),
                    onChanged: () => _refresh(wh.id),
                  );
            final phone = MediaQuery.of(context).size.width < 600;
            if (phone) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [main, const SizedBox(height: 12), detail]);
            }
            return LayoutBuilder(
              builder: (context, box) {
                final side = math.max(300.0, box.maxWidth * 1 / 2.35);
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: main),
                    const SizedBox(width: 12),
                    SizedBox(width: side, child: detail),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─── Fill colours ───────────────────────────────────────────────────────────

Color _fillBg(Nocturne n, double f, {bool inactive = false}) {
  if (inactive) return n.n900;
  if (f <= 0) return n.n900;
  if (f > 0.9) return Nocturne.mix(n.warn, n.n900, 0.7);
  return Nocturne.mix(n.a500, n.n900, 0.18 + f * 0.72);
}

/// Diagonal stripes over an inactive cell.
class _Hatch extends CustomPainter {
  _Hatch(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Hatch old) => old.color != color;
}

class _Cell extends StatelessWidget {
  const _Cell({required this.loc, required this.selected, required this.onTap, required this.child, this.height, this.padding});

  final _Loc loc;
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double? height;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final f = loc.util;
    final light = f > 0.55 && !loc.inactive;
    return Tooltip(
      message: '${loc.l.name} · ${loc.l.code} · ${fmtNum(loc.units)} units${loc.cap > 0 ? ' · ${(f * 100).round()}% full' : ''}',
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: _fillBg(n, f, inactive: loc.inactive),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: CustomPaint(
            painter: loc.inactive ? _Hatch(n.n800) : null,
            child: Container(
              height: height,
              padding: padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: selected ? n.accent : n.divider, width: selected ? 2 : 1),
              ),
              child: DefaultTextStyle.merge(style: TextStyle(color: light ? n.n100 : n.n300), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Map ────────────────────────────────────────────────────────────────────

/// Top-level slots as zone tiles; every other top-level area as a card whose
/// rows are its children and whose cells are their children (deeper levels
/// roll up into the cell's fill).
class _StructureMap extends StatelessWidget {
  const _StructureMap({required this.idx, required this.showInactive, required this.selected, required this.onSelect});

  final _Index idx;
  final bool showInactive;
  final String? selected;
  final ValueChanged<_Loc> onSelect;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    bool keep(_Loc l) => showInactive || !l.inactive;
    final roots = idx.list.where((r) => r.depth == 0 && keep(r)).toList();
    final zones = roots.where((r) => r.leaf).toList();
    final areas = roots.where((r) => !r.leaf).toList();
    String pct(_Loc r) => r.cap > 0 ? '${(r.util * 100).round()}%' : '—';

    return NxSection(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (zones.isNotEmpty) ...[
            LayoutBuilder(
              builder: (context, box) {
                final perRow = math.max(1, (box.maxWidth + 8) ~/ 158);
                final w = (box.maxWidth - 8 * (math.min(perRow, zones.length) - 1)) / math.min(perRow, zones.length);
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final z in zones)
                      SizedBox(
                        width: w,
                        child: _Cell(
                          loc: z,
                          selected: z.id == selected,
                          onTap: () => onSelect(z),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          child: Row(
                            children: [
                              const Icon(PhosphorIconsDuotone.squaresFour, size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(z.l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                    Text('${z.l.locationType} · ${z.l.code}', style: const TextStyle(fontSize: 11)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtNum(z.units), style: TextStyle(fontSize: 13, fontFeatures: tabular)),
                                  Text(pct(z), style: const TextStyle(fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          if (areas.isNotEmpty)
            LayoutBuilder(
              builder: (context, box) {
                final perRow = math.max(1, (box.maxWidth + 10) ~/ 200);
                final w = (box.maxWidth - 10 * (perRow - 1)) / perRow;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final a in areas)
                      SizedBox(
                        width: w,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: n.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: a.id == selected ? n.accent : Colors.transparent),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              InkWell(
                                onTap: () => onSelect(a),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Expanded(child: Text(a.l.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text))),
                                    Text('${fmtNum(a.units)} · ${pct(a)}', style: TextStyle(fontSize: 11, color: n.n400, fontFeatures: tabular)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              NxBar(fraction: a.util, height: 3),
                              const SizedBox(height: 10),
                              for (final rid in a.kids)
                                if (idx.byId[rid] case final r? when keep(r))
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 46,
                                          child: InkWell(
                                            onTap: () => onSelect(r),
                                            child: Text(
                                              r.l.code,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontFamily: 'monospace', fontSize: 10, color: r.id == selected ? n.a300 : n.n400),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Row(
                                            children: [
                                              for (final c in (r.leaf ? [r] : [for (final k in r.kids) idx.byId[k]!]).where(keep)) ...[
                                                Expanded(
                                                  child: _Cell(
                                                    loc: c,
                                                    selected: c.id == selected,
                                                    onTap: () => onSelect(c),
                                                    height: 36,
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Text(
                                                          c.l.code.split('-').last,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.clip,
                                                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, height: 1.15),
                                                        ),
                                                        Text(pct(c), style: const TextStyle(fontSize: 10, height: 1.15)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                              ],
                                              if (!r.leaf && r.kids.isEmpty) Text('No levels yet', style: TextStyle(fontSize: 11, color: n.n500)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          if (roots.isEmpty) Text('No locations yet.', style: TextStyle(fontSize: 13, color: n.n400)),
          const SizedBox(height: 12),
          DefaultTextStyle.merge(
            style: TextStyle(fontSize: 11, color: n.n400),
            child: Wrap(
              spacing: 14,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Fill '),
                    Container(
                      width: 90,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(colors: [n.n900, n.a500]),
                      ),
                    ),
                    const Text(' 0 → 90%'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: _fillBg(n, 0.95), borderRadius: BorderRadius.circular(3))),
                    const Text(' over 90%'),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), border: Border.all(color: n.divider)),
                      child: CustomPaint(painter: _Hatch(n.n800)),
                    ),
                    const Text(' inactive'),
                  ],
                ),
                const Text('Each row is a child of the area; cells are its levels'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tree ───────────────────────────────────────────────────────────────────

class _StructureTree extends StatelessWidget {
  const _StructureTree({
    required this.idx,
    required this.visible,
    required this.collapsed,
    required this.selected,
    required this.onSelect,
    required this.onToggle,
  });

  final _Index idx;

  /// The rows left after search / filters.
  final Set<String> visible;
  final Set<String> collapsed;
  final String? selected;
  final ValueChanged<_Loc> onSelect;
  final ValueChanged<String> onToggle;

  bool _hidden(_Loc r) {
    for (var p = r.l.parentId; p != null; p = idx.byId[p]?.l.parentId) {
      if (collapsed.contains(p)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final rows = idx.list.where((r) => visible.contains(r.id) && !_hidden(r)).toList();
    return NxSection(
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(34, 4, 8, 6),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: n.n500),
              child: const Row(
                children: [
                  Expanded(child: Text('LOCATION')),
                  SizedBox(width: 60, child: Text('FILL', textAlign: TextAlign.right)),
                  SizedBox(width: 56, child: Text('UNITS', textAlign: TextAlign.right)),
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No locations match.', style: TextStyle(fontSize: 13, color: n.n400)),
            ),
          for (final r in rows)
            () {
              final sel = r.id == selected;
              return Opacity(
                opacity: r.inactive ? 0.5 : 1,
                child: Material(
                  color: sel ? n.a900 : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  child: InkWell(
                    onTap: () => onSelect(r),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: sel ? n.accent : Colors.transparent, width: 2))),
                      padding: EdgeInsets.fromLTRB(6.0 + r.depth * 18, 5, 8, 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: r.leaf
                                ? null
                                : InkWell(
                                    onTap: () => onToggle(r.id),
                                    child: AnimatedRotation(
                                      turns: collapsed.contains(r.id) ? 0 : 0.25,
                                      duration: const Duration(milliseconds: 150),
                                      child: Icon(PhosphorIconsBold.caretRight, size: 10, color: n.n500),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            r.leaf ? PhosphorIconsDuotone.cube : PhosphorIconsDuotone.folderSimple,
                            size: 15,
                            color: sel ? n.a300 : n.n500,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                text: r.l.name,
                                style: TextStyle(fontSize: 13, color: n.text),
                                children: [
                                  TextSpan(text: '  ${r.l.code}', style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: n.n500)),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: n.n900, borderRadius: BorderRadius.circular(4)),
                            child: Text(r.l.locationType, style: TextStyle(fontSize: 9, letterSpacing: 0.5, color: n.n400)),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 52,
                            child: r.cap > 0 ? NxBar(fraction: r.util, height: 4, color: r.util > 0.9 ? n.warn : n.a500) : null,
                          ),
                          SizedBox(
                            width: 56,
                            child: Text(fmtNum(r.units), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: n.n400, fontFeatures: tabular)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}

// ─── Detail ─────────────────────────────────────────────────────────────────

class _Detail extends ConsumerWidget {
  const _Detail({required this.loc, required this.idx, required this.all, required this.warehouseId, required this.balances, required this.onChanged});

  final _Loc loc;
  final _Index idx;
  final List<Location> all;
  final String warehouseId;
  final List<InventoryBalance> balances;
  final VoidCallback onChanged;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    final l = loc.l;
    if (l.isActive) {
      final ok = await showNxConfirm(
        context,
        title: 'Deactivate location?',
        body: 'This marks "${l.name}" inactive. It is NOT deleted, and its child locations are NOT automatically deactivated.',
        confirmLabel: 'Deactivate',
        danger: true,
      );
      if (!ok) return;
    }
    try {
      final api = ref.read(locationsApiProvider);
      l.isActive ? await api.deactivate(l.id) : await api.reactivate(l.id);
      onChanged();
      NxToast.ok('Location ${l.isActive ? 'deactivated' : 'reactivated'}', '${l.name} (${l.code})');
    } on AppError catch (e) {
      NxToast.error('Not changed', e.message);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final user = ref.watch(authProvider).value?.user;
    final canManage = user?.can('warehouse.structure.manage') ?? false;
    final canReceive = user?.can('inventory.receive') ?? false;
    final canCount = user?.can('inventory.count') ?? false;
    final l = loc.l;
    final parent = l.parentId == null ? null : idx.byId[l.parentId];
    final stock = balances.where((b) => b.onHand > 0 || b.reserved > 0).toList()..sort((a, b) => a.product.name.compareTo(b.product.name));
    final facts = [
      ('Code', l.code),
      ('Type', l.locationType),
      ('Parent', parent == null ? '— top level' : '${parent.l.name} (${parent.l.code})'),
      ('Children', fmtNum(loc.kids.length)),
      ('Units', fmtNum(loc.units)),
      ('SKUs', loc.leaf ? fmtNum(loc.skus) : '—'),
    ];
    final buttons = [
      if (canManage) ...[
        NxButton(label: 'Add child', icon: PhosphorIconsRegular.plus, small: true, onPressed: () => showLocationForm(context, warehouseId: warehouseId, parent: l, all: all)),
        NxButton(label: 'Create levels', icon: PhosphorIconsRegular.stackPlus, small: true, onPressed: () => showCreateLevels(context, parent: l, all: all)),
        NxButton(label: 'Edit', icon: PhosphorIconsRegular.pencilSimple, small: true, onPressed: () => showLocationForm(context, warehouseId: warehouseId, location: l, all: all)),
        NxButton(label: 'Move', icon: PhosphorIconsRegular.arrowsOutCardinal, small: true, onPressed: () => showMoveLocation(context, location: l, all: all)),
      ],
      if (loc.leaf && l.isActive && canReceive)
        NxButton(label: 'Receive here', icon: PhosphorIconsRegular.boxArrowDown, small: true, onPressed: () => showReceiveSheet(context, locationId: l.id)),
      if (loc.leaf && l.isActive && canCount)
        NxButton(label: 'Count', icon: PhosphorIconsRegular.listChecks, small: true, onPressed: () => showStartCountDialog(context, locationId: l.id)),
      if (canManage)
        NxButton(
          label: l.isActive ? 'Deactivate' : 'Reactivate',
          icon: l.isActive ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
          small: true,
          color: l.isActive ? n.bad : n.accent,
          onPressed: () => _toggle(context, ref),
        ),
    ];

    return NxSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(l.name, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: n.text))),
                    NxTag(l.isActive ? 'Active' : 'Inactive', tone: l.isActive ? Tone.ok : Tone.neutral),
                  ],
                ),
                const SizedBox(height: 2),
                Text(loc.path.join(' › '), style: TextStyle(fontSize: 12, color: n.n400)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: NxBar(fraction: loc.util, height: 6)),
                    const SizedBox(width: 8),
                    Text(
                      loc.cap > 0 ? '${(loc.util * 100).round()}% of ${fmtNum(loc.cap)}' : 'No capacity',
                      style: TextStyle(fontSize: 11, color: n.n400),
                    ),
                  ],
                ),
                if ((l.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(l.description!, style: TextStyle(fontSize: 12, color: n.n300)),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: n.n900))),
            child: LayoutBuilder(
              builder: (context, box) {
                final w = box.maxWidth / 3;
                return Wrap(
                  children: [
                    for (final f in facts)
                      Container(
                        width: w,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(right: BorderSide(color: n.n900), bottom: BorderSide(color: n.n900)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.$1, style: TextStyle(fontSize: 11, color: n.n500)),
                            Text(f.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text, fontFeatures: tabular)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Wrap(spacing: 6, runSpacing: 6, children: buttons),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
            child: Text('Stock in this location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
          ),
          if (!loc.leaf)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Text('Stock sits on storage slots. Pick a slot to see its products.', style: TextStyle(fontSize: 12, color: n.n400)),
            )
          else if (stock.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
              child: Text('Empty — ready for putaway.', style: TextStyle(fontSize: 12, color: n.n400)),
            )
          else
            for (final b in stock)
              NxHoverRow(
                onTap: () => showProductSheet(context, b.productId),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.product.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                          Text(b.product.sku, style: TextStyle(fontSize: 11, color: n.n500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(fmtNum(b.onHand), style: TextStyle(fontSize: 13, color: n.text, fontFeatures: tabular)),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 80,
                      child: Text(
                        '${fmtNum(b.available)} avail.',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 13, color: n.a300, fontFeatures: tabular),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
