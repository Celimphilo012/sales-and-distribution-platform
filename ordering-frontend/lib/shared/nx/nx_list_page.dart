import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/nocturne.dart';
import 'nx_form.dart';
import 'nx_primitives.dart';

/// The Warehouse Console's list screen, as one configurable widget — every
/// catalogue, warehousing, stock and admin collection is an [NxListPage]:
///
///   header (title, sub-line, actions) → stats strip → toolbar (search,
///   quick segment, Filters button, view switcher) → filter panel → active
///   filter chips → the rows as a TABLE, a LIST or a GRID → "N records".
///
/// Filtering, sorting and the chosen view are client-side over [rows] and are
/// remembered per [stateKey] (so leaving and coming back keeps them, and the
/// dashboard can open a list pre-filtered — see [NxListStates.preset]).

// ─── Configuration ──────────────────────────────────────────────────────────

/// [map] and [tree] are drawn by the page's own [NxListPage.contentOverride].
enum NxView { map, tree, table, list, grid }

extension NxViewMeta on NxView {
  IconData get icon => switch (this) {
    NxView.map => PhosphorIconsRegular.mapTrifold,
    NxView.tree => PhosphorIconsRegular.treeView,
    NxView.table => PhosphorIconsRegular.table,
    NxView.list => PhosphorIconsRegular.rows,
    NxView.grid => PhosphorIconsRegular.squaresFour,
  };
  String get label => switch (this) {
    NxView.map => 'Map',
    NxView.tree => 'Tree',
    NxView.table => 'Table',
    NxView.list => 'List',
    NxView.grid => 'Grid',
  };
}

/// When a table column is shown: always, not on phones ([md]), or desktop only ([wide]).
enum NxHide { none, md, wide }

class NxColumn<T> {
  const NxColumn({
    required this.key,
    required this.label,
    required this.cell,
    this.sort,
    this.align = TextAlign.left,
    this.width,
    this.hide = NxHide.none,
  });

  final String key;
  final String label;
  final Widget Function(T row) cell;
  /// The sort key; null values sort last.
  final Comparable<dynamic>? Function(T row)? sort;
  final TextAlign align;
  final double? width;
  final NxHide hide;
}

class NxStat {
  const NxStat(this.label, this.value, {this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;
}

/// A quick segmented filter (All / Active / Inactive …).
class NxQuick<T> {
  const NxQuick({required this.get, required this.options, this.defaultValue = ''});

  final String Function(T row) get;

  /// (value, label); the value '' means "all".
  final List<(String, String)> options;
  final String defaultValue;
}

sealed class NxFilter<T> {
  const NxFilter(this.key, this.label);

  final String key;
  final String label;
}

/// One value from a list. [get] may return a single value or an Iterable (the
/// row matches when any element equals the chosen value).
class NxSelectFilter<T> extends NxFilter<T> {
  const NxSelectFilter(super.key, super.label, {required this.options, required this.get, this.searchable = false});

  final List<(String, String)> options;
  final Object? Function(T row) get;
  final bool searchable;
}

class NxMultiFilter<T> extends NxFilter<T> {
  const NxMultiFilter(super.key, super.label, {required this.options, required this.get});

  final List<(String, String)> options;
  final String? Function(T row) get;
}

class NxRangeFilter<T> extends NxFilter<T> {
  const NxRangeFilter(super.key, super.label, {required this.get});

  final num? Function(T row) get;
}

class NxToggleFilter<T> extends NxFilter<T> {
  const NxToggleFilter(super.key, super.label, {required this.text, required this.get});

  final String text;
  final bool Function(T row) get;
}

class NxDateFilter<T> extends NxFilter<T> {
  const NxDateFilter(super.key, super.label, {required this.get});

  final DateTime? Function(T row) get;
}

/// An inline row action (icon button; with [text] it also shows its label).
class NxRowAction {
  const NxRowAction({required this.icon, required this.label, required this.onPressed, this.danger = false, this.primary = false, this.text});

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;
  final bool primary;
  final String? text;
}

class NxListRowSpec {
  const NxListRowSpec({
    required this.icon,
    required this.title,
    this.iconColor,
    this.sub,
    this.right,
    this.rightSub,
    this.rightColor,
    this.tag,
    this.actions = const [],
    this.leading,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? sub;
  final String? right;
  final String? rightSub;
  final Color? rightColor;
  final NxTag? tag;
  final List<NxRowAction> actions;

  /// Replaces the icon tile (e.g. a product thumbnail).
  final Widget? leading;
}

class NxCardSpec {
  const NxCardSpec({
    required this.icon,
    required this.title,
    this.iconColor,
    this.sub,
    this.metrics = const [],
    this.tag,
    this.bar,
    this.barColor,
    this.actions = const [],
    this.leading,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? sub;

  /// (label, value, colour?)
  final List<(String, String, Color?)> metrics;
  final NxTag? tag;
  final double? bar;
  final Color? barColor;
  final List<NxRowAction> actions;
  final Widget? leading;
}

// ─── Remembered state ───────────────────────────────────────────────────────

@immutable
class NxListState {
  const NxListState({
    this.query = '',
    this.quick,
    this.filters = const {},
    this.sortKey,
    this.sortDir = 1,
    this.view,
    this.filtersOpen = false,
  });

  final String query;
  final String? quick;

  /// key → String (select) | a set of strings (multi) | (num?, num?) (range) |
  /// bool (toggle) | (DateTime?, DateTime?) (date).
  final Map<String, Object> filters;
  final String? sortKey;
  final int sortDir;
  final NxView? view;
  final bool filtersOpen;

  NxListState copyWith({
    String? query,
    String? Function()? quick,
    Map<String, Object>? filters,
    String? Function()? sortKey,
    int? sortDir,
    NxView? Function()? view,
    bool? filtersOpen,
  }) => NxListState(
    query: query ?? this.query,
    quick: quick != null ? quick() : this.quick,
    filters: filters ?? this.filters,
    sortKey: sortKey != null ? sortKey() : this.sortKey,
    sortDir: sortDir ?? this.sortDir,
    view: view != null ? view() : this.view,
    filtersOpen: filtersOpen ?? this.filtersOpen,
  );
}

/// Every list screen's remembered search/filters/sort/view, by screen key.
class NxListStates extends Notifier<Map<String, NxListState>> {
  @override
  Map<String, NxListState> build() => const {};

  NxListState of(String key) => state[key] ?? const NxListState();

  void update(String key, NxListState Function(NxListState s) change) => state = {...state, key: change(of(key))};

  /// Opens a list pre-filtered (e.g. the dashboard's "Low stock" tile):
  /// replaces its filters/query/quick, keeps its view.
  void preset(String key, {Map<String, Object> filters = const {}, String query = '', String? quick}) =>
      update(key, (s) => s.copyWith(filters: filters, query: query, quick: () => quick));
}

final nxListStatesProvider = NotifierProvider<NxListStates, Map<String, NxListState>>(NxListStates.new);

// ─── The page ───────────────────────────────────────────────────────────────

class NxListPage<T> extends ConsumerStatefulWidget {
  const NxListPage({
    super.key,
    required this.stateKey,
    required this.title,
    this.sub,
    this.actions = const [],
    required this.rows,
    required this.stats,
    required this.columns,
    required this.listRow,
    required this.card,
    this.search,
    this.searchPlaceholder = 'Search',
    this.quick,
    this.filters = const [],
    this.defaultSort,
    this.views = const [NxView.table, NxView.list, NxView.grid],
    this.defaultView,
    this.onOpen,
    this.emptyTitle = 'Nothing here',
    this.emptyMessage = 'Try adjusting your search or filters.',
    this.footNote,
    this.totalCount,
    this.aboveContent,
    this.contentOverride,
  });

  final String stateKey;
  final String title;
  final String? sub;
  final List<Widget> actions;
  final List<T> rows;
  final List<NxStat> Function(List<T> rows) stats;
  final List<NxColumn<T>> columns;
  final NxListRowSpec Function(T row) listRow;
  final NxCardSpec Function(T row) card;
  final String Function(T row)? search;
  final String searchPlaceholder;
  final NxQuick<T>? quick;
  final List<NxFilter<T>> filters;

  /// (column key, direction 1 = ascending / -1 = descending).
  final (String, int)? defaultSort;
  final List<NxView> views;
  final NxView? defaultView;
  final void Function(T row)? onOpen;
  final String emptyTitle;
  final String emptyMessage;
  final String? footNote;

  /// When the rows are a page of a larger server-side set, the full size.
  final int? totalCount;

  /// Extra controls between the chips and the content (the structure screen's warehouse picker).
  final Widget? aboveContent;

  /// Draws the current view itself when it returns non-null (the structure
  /// screen's map/tree), given the filtered rows.
  final Widget? Function(List<T> filtered, NxView view)? contentOverride;

  @override
  ConsumerState<NxListPage<T>> createState() => _NxListPageState<T>();
}

class _NxListPageState<T> extends ConsumerState<NxListPage<T>> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(nxListStatesProvider.notifier).of(widget.stateKey).query);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _set(NxListState Function(NxListState s) change) => ref.read(nxListStatesProvider.notifier).update(widget.stateKey, change);

  bool _isEmptyValue(Object? v) => switch (v) {
    null => true,
    String s => s.isEmpty,
    Set<String> s => s.isEmpty,
    (num?, num?) r => r.$1 == null && r.$2 == null,
    (DateTime?, DateTime?) r => r.$1 == null && r.$2 == null,
    bool b => !b,
    _ => false,
  };

  bool _passes(NxFilter<T> f, Object? v, T row) {
    if (_isEmptyValue(v)) return true;
    switch (f) {
      case NxSelectFilter<T>(:final get):
        final got = get(row);
        if (got is Iterable) return got.map((e) => '$e').contains(v);
        return '$got' == v;
      case NxMultiFilter<T>(:final get):
        return (v as Set<String>).contains(get(row));
      case NxRangeFilter<T>(:final get):
        final r = v as (num?, num?);
        final x = get(row);
        if (x == null) return false;
        return (r.$1 == null || x >= r.$1!) && (r.$2 == null || x <= r.$2!);
      case NxToggleFilter<T>(:final get):
        return get(row);
      case NxDateFilter<T>(:final get):
        final r = v as (DateTime?, DateTime?);
        final d = get(row);
        if (d == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        return (r.$1 == null || !day.isBefore(r.$1!)) && (r.$2 == null || !day.isAfter(r.$2!));
    }
  }

  String _chipText(NxFilter<T> f, Object v) {
    String fmtD(DateTime? d) => d == null ? '…' : '${d.day} ${_months[d.month - 1]}';
    return switch (f) {
      NxSelectFilter<T>(:final options) => '${f.label}: ${options.where((o) => o.$1 == v).firstOrNull?.$2 ?? v}',
      NxMultiFilter<T>(:final options) =>
        '${f.label}: ${(v as Set<String>).map((x) => options.where((o) => o.$1 == x).firstOrNull?.$2 ?? x).join(', ')}',
      NxRangeFilter<T>() => () {
        final r = v as (num?, num?);
        return '${f.label}: ${r.$1 == null ? '≤ ${_num(r.$2!)}' : r.$2 == null ? '≥ ${_num(r.$1!)}' : '${_num(r.$1!)}–${_num(r.$2!)}'}';
      }(),
      NxToggleFilter<T>(:final text) => text,
      NxDateFilter<T>() => '${f.label}: ${fmtD((v as (DateTime?, DateTime?)).$1)} – ${fmtD(v.$2)}',
    };
  }

  static String _num(num x) => x == x.roundToDouble() ? x.toInt().toString() : x.toString();

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final st = ref.watch(nxListStatesProvider.select((m) => m[widget.stateKey])) ?? const NxListState();
    final width = MediaQuery.of(context).size.width;
    final phone = width < 600;
    final desktop = width >= 1024;

    // Filter.
    final q = st.query.trim().toLowerCase();
    final quickV = st.quick ?? widget.quick?.defaultValue ?? '';
    var rows = widget.rows;
    if (q.isNotEmpty && widget.search != null) {
      rows = rows.where((r) => widget.search!(r).toLowerCase().contains(q)).toList();
    }
    if (widget.quick != null && quickV.isNotEmpty) rows = rows.where((r) => widget.quick!.get(r) == quickV).toList();
    rows = rows.where((r) => widget.filters.every((f) => _passes(f, st.filters[f.key], r))).toList();

    // Sort.
    final sortKey = st.sortKey ?? widget.defaultSort?.$1;
    final sortDir = st.sortKey != null ? st.sortDir : (widget.defaultSort?.$2 ?? 1);
    final sortCol = widget.columns.where((c) => c.key == sortKey && c.sort != null).firstOrNull;
    if (sortCol != null) {
      rows = [...rows]..sort((a, b) {
        final x = sortCol.sort!(a);
        final y = sortCol.sort!(b);
        if (x == null && y == null) return 0;
        if (x == null) return sortDir;
        if (y == null) return -sortDir;
        return x.compareTo(y) * sortDir;
      });
    }

    var view = st.view ?? widget.defaultView ?? (phone && widget.views.contains(NxView.list) ? NxView.list : widget.views.first);
    if (!widget.views.contains(view)) view = widget.views.first;
    final activeFilters = widget.filters.where((f) => !_isEmptyValue(st.filters[f.key])).toList();
    final stats = widget.stats(rows);

    bool shown(NxHide h) => switch (h) {
      NxHide.none => true,
      NxHide.md => !phone,
      NxHide.wide => desktop,
    };
    final columns = widget.columns.where((c) => shown(c.hide)).toList();

    final total = widget.totalCount ?? widget.rows.length;
    final countText = rows.length == widget.rows.length
        ? '${_fmt(rows.length)} ${rows.length == 1 ? 'record' : 'records'}${widget.totalCount != null && widget.totalCount! > widget.rows.length ? ' of ${_fmt(total)}' : ''}'
        : '${_fmt(rows.length)} of ${_fmt(widget.rows.length)} records match';

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NxPageHeader(title: widget.title, sub: widget.sub, actions: widget.actions),
            const SizedBox(height: 12),
            if (stats.isNotEmpty) ...[NxStatStrip(stats: stats), const SizedBox(height: 12)],
            _toolbar(context, st, quickV, activeFilters.length, view),
            const SizedBox(height: 10),
            if (st.filtersOpen) ...[_filterPanel(context, st), const SizedBox(height: 10)],
            if (activeFilters.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final f in activeFilters)
                    _Chip(
                      label: _chipText(f, st.filters[f.key]!),
                      onClear: () => _set((s) => s.copyWith(filters: {...s.filters}..remove(f.key))),
                    ),
                  NxButton.ghost(label: 'Clear all', small: true, onPressed: _clearAll),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (widget.aboveContent != null) ...[widget.aboveContent!, const SizedBox(height: 10)],
            if (widget.contentOverride?.call(rows, view) case final custom?)
              custom
            else if (rows.isEmpty)
              NxSection(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.emptyTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: n.text)),
                    const SizedBox(height: 4),
                    Text(widget.emptyMessage, style: TextStyle(fontSize: 12, color: n.n400)),
                    const SizedBox(height: 10),
                    NxButton(label: 'Clear filters', small: true, onPressed: _clearAll),
                  ],
                ),
              )
            else ...[
              switch (view) {
                NxView.table => NxTable<T>(
                  columns: columns,
                  rows: rows,
                  sortKey: sortKey,
                  sortDir: sortDir,
                  onSort: (key) => _set(
                    (s) => s.copyWith(sortKey: () => key, sortDir: key == sortKey ? -sortDir : 1),
                  ),
                  onOpen: widget.onOpen,
                ),
                NxView.list => NxListRows<T>(rows: rows, spec: widget.listRow, onOpen: widget.onOpen),
                NxView.grid || NxView.map || NxView.tree => NxCardGrid<T>(rows: rows, spec: widget.card, onOpen: widget.onOpen),
              },
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: [
                  Text(countText, style: TextStyle(fontSize: 11, color: n.n500)),
                  if (widget.footNote != null) Text('· ${widget.footNote}', style: TextStyle(fontSize: 11, color: n.n500)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _clearAll() {
    _search.clear();
    _set((s) => s.copyWith(filters: const {}, query: '', quick: () => null));
  }

  Widget _toolbar(BuildContext context, NxListState st, String quickV, int filterCount, NxView view) {
    final n = context.nx;
    final open = st.filtersOpen || filterCount > 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.search != null)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 320),
            child: NxInput(
              controller: _search,
              dense: true,
              prefixIcon: PhosphorIconsRegular.magnifyingGlass,
              placeholder: widget.searchPlaceholder,
              onChanged: (v) => _set((s) => s.copyWith(query: v)),
            ),
          ),
        if (widget.quick != null)
          NxSeg<String>(
            options: [for (final o in widget.quick!.options) (o.$1, o.$2, null)],
            value: quickV,
            onChanged: (v) => _set((s) => s.copyWith(quick: () => v)),
          ),
        if (widget.filters.isNotEmpty || widget.columns.any((c) => c.sort != null))
          _FiltersButton(
            active: open,
            count: filterCount,
            onTap: () => _set((s) => s.copyWith(filtersOpen: !s.filtersOpen)),
            n: n,
          ),
        if (widget.views.length > 1)
          NxSeg<NxView>(
            iconOnly: true,
            options: [for (final v in widget.views) (v, v.label, v.icon)],
            value: view,
            onChanged: (v) => _set((s) => s.copyWith(view: () => v)),
          ),
      ],
    );
  }

  Widget _filterPanel(BuildContext context, NxListState st) {
    final phone = MediaQuery.of(context).size.width < 600;
    final sortable = widget.columns.where((c) => c.sort != null && c.label.isNotEmpty).toList();
    void setF(String key, Object? v) => _set((s) {
      final next = {...s.filters};
      if (v == null || _isEmptyValue(v)) {
        next.remove(key);
      } else {
        next[key] = v;
      }
      return s.copyWith(filters: next);
    });

    Widget field(NxFilter<T> f) {
      final v = st.filters[f.key];
      return switch (f) {
        NxSelectFilter<T>(:final options, :final searchable) => NxSelect<String>(
          dense: true,
          searchable: searchable || options.length > 12,
          options: [for (final o in options) NxOption(o.$1, o.$2)],
          value: v as String?,
          emptyLabel: 'Any',
          onChanged: (x) => setF(f.key, x),
        ),
        NxMultiFilter<T>(:final options) => Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in options)
              NxChipToggle(
                label: o.$2,
                selected: (v as Set<String>? ?? const {}).contains(o.$1),
                onTap: () {
                  final set = {...(v ?? const <String>{})};
                  set.contains(o.$1) ? set.remove(o.$1) : set.add(o.$1);
                  setF(f.key, set);
                },
              ),
          ],
        ),
        NxRangeFilter<T>() => _RangeField(
          value: v as (num?, num?)? ?? (null, null),
          onChanged: (r) => setF(f.key, r),
        ),
        NxToggleFilter<T>(:final text) => NxCheckToggle(label: text, value: v == true, onChanged: (b) => setF(f.key, b)),
        NxDateFilter<T>() => _DateRangeField(
          value: v as (DateTime?, DateTime?)? ?? (null, null),
          onChanged: (r) => setF(f.key, r),
        ),
      };
    }

    final sortOptions = [
      for (final c in sortable)
        for (final d in const [1, -1]) NxOption('${c.key}|$d', '${c.label} ${d == 1 ? '↑' : '↓'}'),
    ];

    return NxSection(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              const gap = 12.0;
              final cols = ((box.maxWidth + gap) / (200 + gap)).floor().clamp(1, 12);
              final cell = (box.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final f in widget.filters)
                    SizedBox(
                      width: f is NxMultiFilter<T> && !phone && cols > 1 ? cell * 2 + gap : cell,
                      child: NxField(label: f.label, child: field(f)),
                    ),
                  if (sortOptions.isNotEmpty)
                    SizedBox(
                      width: cell,
                      child: NxField(
                        label: 'Sort by',
                        child: NxSelect<String>(
                          dense: true,
                          options: sortOptions,
                          value: st.sortKey == null ? null : '${st.sortKey}|${st.sortDir}',
                          placeholder: 'Default order',
                          onChanged: (x) {
                            if (x == null) return;
                            final parts = x.split('|');
                            _set((s) => s.copyWith(sortKey: () => parts[0], sortDir: int.parse(parts[1])));
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              NxButton.ghost(label: 'Reset all', small: true, color: context.nx.n400, onPressed: _clearAll),
              const SizedBox(width: 8),
              NxButton(label: 'Done', small: true, onPressed: () => _set((s) => s.copyWith(filtersOpen: false))),
            ],
          ),
        ],
      ),
    );
  }
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _fmt(num n) {
  final s = n.toStringAsFixed(0);
  return s.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

class _FiltersButton extends StatelessWidget {
  const _FiltersButton({required this.active, required this.count, required this.onTap, required this.n});

  final bool active;
  final int count;
  final VoidCallback onTap;
  final Nocturne n;

  @override
  Widget build(BuildContext context) {
    final color = active ? n.a200 : n.n300;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: 'Filters',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(NxRadius.md),
              border: Border.all(color: active ? n.accent : n.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(PhosphorIconsRegular.funnelSimple, size: 14, color: color),
                const SizedBox(width: 6),
                Text('Filters', style: TextStyle(fontSize: 12, color: color)),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(color: n.accent, borderRadius: BorderRadius.circular(8)),
                    alignment: Alignment.center,
                    child: Text('$count', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: n.bg, height: 1)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 3, 4, 3),
      decoration: BoxDecoration(color: n.a900, borderRadius: BorderRadius.circular(14)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: n.a200)),
          const SizedBox(width: 4),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onClear,
              child: Semantics(
                button: true,
                label: 'Remove filter',
                child: SizedBox(width: 18, height: 18, child: Icon(PhosphorIconsRegular.x, size: 11, color: n.a200)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeField extends StatefulWidget {
  const _RangeField({required this.value, required this.onChanged});

  final (num?, num?) value;
  final ValueChanged<(num?, num?)> onChanged;

  @override
  State<_RangeField> createState() => _RangeFieldState();
}

class _RangeFieldState extends State<_RangeField> {
  late final _min = TextEditingController(text: widget.value.$1?.toString() ?? '');
  late final _max = TextEditingController(text: widget.value.$2?.toString() ?? '');

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged((num.tryParse(_min.text), num.tryParse(_max.text)));

  @override
  Widget build(BuildContext context) {
    final fmt = NxInput.decimals();
    return Row(
      children: [
        Expanded(child: NxInput(controller: _min, dense: true, placeholder: 'Min', inputFormatters: fmt, onChanged: (_) => _emit())),
        const SizedBox(width: 6),
        Expanded(child: NxInput(controller: _max, dense: true, placeholder: 'Max', inputFormatters: fmt, onChanged: (_) => _emit())),
      ],
    );
  }
}

class _DateRangeField extends StatelessWidget {
  const _DateRangeField({required this.value, required this.onChanged});

  final (DateTime?, DateTime?) value;
  final ValueChanged<(DateTime?, DateTime?)> onChanged;

  @override
  Widget build(BuildContext context) {
    Future<void> pick(bool from) async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: (from ? value.$1 : value.$2) ?? now,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 1),
      );
      if (picked == null) return;
      onChanged(from ? (picked, value.$2) : (value.$1, picked));
    }

    String label(DateTime? d, String empty) => d == null ? empty : '${d.day} ${_months[d.month - 1]} ${d.year}';
    Widget box(DateTime? d, String empty, bool from) => Expanded(child: _DateBox(text: label(d, empty), set: d != null, onTap: () => pick(from)));
    return Row(children: [box(value.$1, 'From', true), const SizedBox(width: 6), box(value.$2, 'To', false)]);
  }
}

class _DateBox extends StatelessWidget {
  const _DateBox({required this.text, required this.set, required this.onTap});

  final String text;
  final bool set;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: nxInputDecoration(n),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: set ? n.text : n.n500),
                ),
              ),
              Icon(PhosphorIconsRegular.calendarBlank, size: 13, color: n.n500),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header, stats ──────────────────────────────────────────────────────────

/// The page heading: 22px title, 12px muted sub-line, action buttons right.
class NxPageHeader extends StatelessWidget {
  const NxPageHeader({super.key, required this.title, this.sub, this.actions = const []});

  final String title;
  final String? sub;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.end,
      alignment: WrapAlignment.spaceBetween,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200, maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: n.text, height: 1.15, letterSpacing: -0.3)),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(sub!, style: TextStyle(fontSize: 12, color: n.n400)),
                ),
            ],
          ),
        ),
        if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

/// The stats strip: equal cells (min 140px) separated by hairlines.
class NxStatStrip extends StatelessWidget {
  const NxStatStrip({super.key, required this.stats, this.minCell = 140});

  final List<NxStat> stats;
  final double minCell;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxSection(
      child: LayoutBuilder(
        builder: (context, box) {
          final perRow = (box.maxWidth / minCell).floor().clamp(1, stats.length);
          final w = box.maxWidth / perRow;
          return Wrap(
            children: [
              for (final s in stats)
                Container(
                  width: w,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: n.n800), bottom: BorderSide(color: n.n800)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n400)),
                      Text(
                        s.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.2,
                          color: s.color ?? n.text,
                          fontFeatures: tabular,
                        ),
                      ),
                      Text(s.sub ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n500)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Table / list / grid ────────────────────────────────────────────────────

/// Two-line text cell: [text] (optionally mono / coloured / 500-weight) with a
/// muted 11px [sub] line.
class NxCellText extends StatelessWidget {
  const NxCellText(this.text, {super.key, this.sub, this.color, this.weight, this.mono = false, this.align = TextAlign.left});

  final String text;
  final String? sub;
  final Color? color;
  final FontWeight? weight;
  final bool mono;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Column(
      crossAxisAlignment: align == TextAlign.right ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: mono ? 12 : 13,
            color: color ?? n.text,
            fontWeight: weight,
            fontFamily: mono ? NxText.mono : null,
            fontFeatures: tabular,
          ),
        ),
        if (sub != null && sub!.isNotEmpty)
          Text(sub!, textAlign: align, style: TextStyle(fontSize: 11, color: n.n500)),
      ],
    );
  }
}

/// Inline action buttons (the table's last column; list-row/card buttons).
class NxRowActions extends StatelessWidget {
  const NxRowActions(this.actions, {super.key, this.withText = false});

  final List<NxRowAction> actions;
  final bool withText;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: withText ? 6 : 2,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [for (final a in actions) _ActionButton(a, showText: withText || a.text != null)],
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton(this.a, {required this.showText});

  final NxRowAction a;
  final bool showText;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final a = widget.a;
    final color = a.danger ? n.bad : (a.primary ? n.accent : n.n300);
    final border = a.primary ? n.accent : (a.danger && widget.showText ? n.bad.withValues(alpha: 0.5) : n.divider);
    return Tooltip(
      message: a.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: a.onPressed,
          child: Semantics(
            button: true,
            label: a.label,
            child: Container(
              height: 28,
              constraints: const BoxConstraints(minWidth: 28),
              padding: EdgeInsets.symmetric(horizontal: widget.showText ? 10 : 6.5),
              decoration: BoxDecoration(
                color: _hover ? n.textAlpha(0.08) : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: widget.showText || a.primary ? border : Colors.transparent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.icon, size: widget.showText ? 14 : 15, color: color),
                  if (widget.showText) ...[const SizedBox(width: 5), Text(a.text ?? a.label, style: TextStyle(fontSize: 12, color: color))],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NxTable<T> extends StatefulWidget {
  const NxTable({super.key, required this.columns, required this.rows, this.sortKey, this.sortDir = 1, this.onSort, this.onOpen});

  final List<NxColumn<T>> columns;
  final List<T> rows;
  final String? sortKey;
  final int sortDir;
  final ValueChanged<String>? onSort;
  final void Function(T row)? onOpen;

  @override
  State<NxTable<T>> createState() => _NxTableState<T>();
}

class _NxTableState<T> extends State<NxTable<T>> {
  final _hovered = ValueNotifier<int?>(null);
  final _hScroll = ScrollController();

  @override
  void dispose() {
    _hovered.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final rule = BorderSide(color: n.textAlpha(0.08));

    Widget headerCell(NxColumn<T> c) {
      final active = c.key == widget.sortKey;
      final child = Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: c.align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                c.label.toUpperCase(),
                maxLines: 1,
                style: TextStyle(fontSize: 11, letterSpacing: 0.88, color: n.textAlpha(0.6)),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 3),
              Icon(widget.sortDir > 0 ? PhosphorIconsBold.caretUp : PhosphorIconsBold.caretDown, size: 10, color: n.textAlpha(0.6)),
            ],
          ],
        ),
      );
      if (c.sort == null || widget.onSort == null) return child;
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(onTap: () => widget.onSort!(c.key), child: child),
      );
    }

    Widget bodyCell(int i, NxColumn<T> c, T row) => ValueListenableBuilder<int?>(
      valueListenable: _hovered,
      builder: (context, h, child) => ColoredBox(color: h == i ? n.textAlpha(0.04) : Colors.transparent, child: child),
      child: MouseRegion(
        cursor: widget.onOpen != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => _hovered.value = i,
        onExit: (_) {
          if (_hovered.value == i) _hovered.value = null;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpen == null ? null : () => widget.onOpen!(row),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Align(
              alignment: c.align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft,
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, color: n.text),
                textAlign: c.align,
                child: c.cell(row),
              ),
            ),
          ),
        ),
      ),
    );

    final widths = <int, TableColumnWidth>{
      for (var i = 0; i < widget.columns.length; i++)
        i: widget.columns[i].width != null ? FixedColumnWidth(widget.columns[i].width!) : const IntrinsicColumnWidth(flex: 1),
    };

    return NxSection(
      child: LayoutBuilder(
        builder: (context, box) => Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Table(
                columnWidths: widths,
                // Every cell takes the row's full height (so the whole row is clickable
                // and hover-tinted). `fill` alone would size body rows to zero.
                defaultVerticalAlignment: TableCellVerticalAlignment.intrinsicHeight,
                children: [
                  TableRow(
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.divider))),
                    children: [
                      for (final c in widget.columns)
                        TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: headerCell(c)),
                    ],
                  ),
                  for (var i = 0; i < widget.rows.length; i++)
                    TableRow(
                      decoration: BoxDecoration(border: Border(bottom: rule)),
                      children: [for (final c in widget.columns) bodyCell(i, c, widget.rows[i])],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class NxListRows<T> extends StatelessWidget {
  const NxListRows({super.key, required this.rows, required this.spec, this.onOpen});

  final List<T> rows;
  final NxListRowSpec Function(T row) spec;
  final void Function(T row)? onOpen;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxSection(
      child: Column(
        children: [
          for (final r in rows)
            Builder(
              builder: (context) {
                final s = spec(r);
                return NxHoverRow(
                  topRule: false,
                  bottomRule: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  onTap: onOpen == null ? null : () => onOpen!(r),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      s.leading ?? NxIconTile(icon: s.icon, fg: s.iconColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text),
                            ),
                            if (s.sub != null)
                              Text(s.sub!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n500)),
                            if (s.actions.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Align(alignment: Alignment.centerLeft, child: NxRowActions(s.actions, withText: true)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (s.right != null)
                            Text(s.right!, style: TextStyle(fontSize: 13, color: s.rightColor ?? n.text, fontFeatures: tabular)),
                          if (s.rightSub != null) Text(s.rightSub!, style: TextStyle(fontSize: 11, color: n.n500)),
                          if (s.tag != null) ...[const SizedBox(height: 3), s.tag!],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class NxCardGrid<T> extends StatelessWidget {
  const NxCardGrid({super.key, required this.rows, required this.spec, this.onOpen});

  final List<T> rows;
  final NxCardSpec Function(T row) spec;
  final void Function(T row)? onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 10.0;
        final cols = ((box.maxWidth + gap) / (210 + gap)).floor().clamp(1, 12);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final r in rows) SizedBox(width: w, child: _GridCard(spec: spec(r), onTap: onOpen == null ? null : () => onOpen!(r))),
          ],
        );
      },
    );
  }
}

class _GridCard extends StatefulWidget {
  const _GridCard({required this.spec, this.onTap});

  final NxCardSpec spec;
  final VoidCallback? onTap;

  @override
  State<_GridCard> createState() => _GridCardState();
}

class _GridCardState extends State<_GridCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final s = widget.spec;
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: n.surface,
            borderRadius: BorderRadius.circular(NxRadius.md),
            boxShadow: _hover ? n.shadowMd : n.shadowSm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  s.leading ?? NxIconTile(icon: s.icon, size: 34, iconSize: 18, radius: 9, bg: n.a900, fg: s.iconColor ?? n.a400),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                        if (s.sub != null) Text(s.sub!, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n500)),
                      ],
                    ),
                  ),
                  if (s.tag != null) ...[const SizedBox(width: 6), s.tag!],
                ],
              ),
              if (s.metrics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final m in s.metrics)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            NxKicker(m.$1),
                            Text(
                              m.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: m.$3 ?? n.text, fontFeatures: tabular),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              if (s.bar != null) ...[const SizedBox(height: 10), NxBar(fraction: s.bar!, height: 4, color: s.barColor)],
              if (s.actions.isNotEmpty) ...[const SizedBox(height: 10), Align(alignment: Alignment.centerLeft, child: NxRowActions(s.actions, withText: true))],
            ],
          ),
        ),
      ),
    );
  }
}

/// Loading / error wrappers used by every page.
class NxLoading extends StatelessWidget {
  const NxLoading({super.key, this.message = 'Loading…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: n.accent)),
            const SizedBox(height: 12),
            Text(message, style: TextStyle(fontSize: 12, color: n.n400)),
          ],
        ),
      ),
    );
  }
}

class NxError extends StatelessWidget {
  const NxError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxSection(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsFill.warningCircle, size: 18, color: n.bad),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: n.text))),
          if (onRetry != null) ...[const SizedBox(width: 10), NxButton(label: 'Retry', small: true, icon: PhosphorIconsRegular.arrowsClockwise, onPressed: onRetry)],
        ],
      ),
    );
  }
}
