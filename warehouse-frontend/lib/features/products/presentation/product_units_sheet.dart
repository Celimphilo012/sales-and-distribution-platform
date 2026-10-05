import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../inventory/data/inventory_providers.dart';
import '../../inventory/domain/inventory_unit.dart';
import '../domain/product.dart';

Tone _statusTone(InventoryUnitStatus s) => switch (s) {
  InventoryUnitStatus.onHand => Tone.ok,
  InventoryUnitStatus.pending => Tone.neutral,
  InventoryUnitStatus.reserved => Tone.info,
  InventoryUnitStatus.damaged || InventoryUnitStatus.lost || InventoryUnitStatus.expired => Tone.bad,
  InventoryUnitStatus.issued => Tone.accent,
};

/// Every physical unit of a SERIAL-tracked product — its own code, current
/// status and location, server-paginated at 20 a page (matches the rest of
/// the console). Reached from the product sheet's "View units" action.
Future<void> showProductUnitsSheet(BuildContext context, Product product) =>
    showNxSheet<void>(context, kicker: 'Units', wide: true, builder: (_) => _ProductUnitsSheet(product: product));

class _ProductUnitsSheet extends ConsumerStatefulWidget {
  const _ProductUnitsSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_ProductUnitsSheet> createState() => _ProductUnitsSheetState();
}

class _ProductUnitsSheetState extends ConsumerState<_ProductUnitsSheet> {
  String _statusFilter = 'ALL';
  int _page = 1;

  InventoryUnitStatus? get _status => _statusFilter == 'ALL' ? null : InventoryUnitStatus.fromJson(_statusFilter);

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final async = ref.watch(productUnitsPageProvider((productId: widget.product.id, status: _status, page: _page)));

    return NxSheetBody(
      children: [
        Text(
          '${widget.product.sku} · ${widget.product.name} — every physical unit ever printed or scanned in for this '
          'product, each with its own code.',
          style: TextStyle(fontSize: 12, color: n.n400, height: 1.4),
        ),
        const SizedBox(height: 14),
        NxField(
          label: 'Status',
          child: NxSelect<String>(
            options: [
              const NxOption('ALL', 'All statuses'),
              for (final s in InventoryUnitStatus.values) NxOption(s.toJson(), s.label),
            ],
            value: _statusFilter,
            onChanged: (v) => setState(() {
              _statusFilter = v ?? 'ALL';
              _page = 1;
            }),
          ),
        ),
        const SizedBox(height: 14),
        async.when(
          loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: LinearProgressIndicator(minHeight: 2)),
          error: (e, _) => Text(e is AppError ? e.message : 'Could not load units.', style: TextStyle(fontSize: 12, color: n.bad)),
          data: (units) {
            if (units.data.isEmpty) {
              return Text(
                _statusFilter == 'ALL' ? 'No units yet — generate labels or receive some to place it.' : 'No units with this status.',
                style: TextStyle(fontSize: 12, color: n.n400),
              );
            }
            final pages = units.totalPages == 0 ? 1 : units.totalPages;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  decoration: BoxDecoration(color: n.surface, borderRadius: BorderRadius.circular(NxRadius.md)),
                  child: Column(
                    children: [
                      for (final u in units.data)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(u.unitCode, style: TextStyle(fontSize: 12.5, color: n.text, fontFamily: NxText.mono)),
                                    const SizedBox(height: 2),
                                    Text(
                                      [u.source.label, if (u.location != null) '${u.location!.code} · ${u.location!.name}'].join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 11, color: n.n500),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  NxTag(u.status.shortLabel, tone: _statusTone(u.status), small: true),
                                  const SizedBox(height: 4),
                                  Text(fmtDate(u.updatedAt.toLocal()), style: TextStyle(fontSize: 10.5, color: n.n600)),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Page ${units.page} of $pages · ${fmtNum(units.total)} unit${units.total == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: n.n400),
                      ),
                    ),
                    NxIconButton(
                      icon: PhosphorIconsRegular.caretLeft,
                      tooltip: 'Previous page',
                      onPressed: units.page > 1 ? () => setState(() => _page = units.page - 1) : null,
                    ),
                    const SizedBox(width: 4),
                    NxIconButton(
                      icon: PhosphorIconsRegular.caretRight,
                      tooltip: 'Next page',
                      onPressed: units.page < units.totalPages ? () => setState(() => _page = units.page + 1) : null,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
