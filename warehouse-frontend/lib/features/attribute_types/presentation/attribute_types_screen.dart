import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_actions.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../products/domain/product.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/attribute_types_providers.dart';
import '../domain/attribute_type.dart';
import 'attribute_type_form_dialog.dart';

class _Row {
  _Row(this.t, this.used);

  final AttributeType t;

  /// Products carrying a value of this type.
  final int used;

  bool get number => t.dataType == AttributeDataType.number;
  bool get hasUnit => (t.unit ?? '').isNotEmpty;
}

/// Attribute Types (prototype `attributes`) — the admin-managed catalogue
/// behind product attributes.
class AttributeTypesScreen extends ConsumerWidget {
  const AttributeTypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final async = ref.watch(attributeTypesProvider(true));
    final products = ref.watch(productsListProvider).value ?? const <Product>[];

    return NxPageScroll(
      onRefresh: () async => invalidateAttributeTypes(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading attribute types…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load attribute types.',
          onRetry: () => invalidateAttributeTypes(ref),
        ),
        data: (types) {
          final used = <String, int>{};
          for (final p in products) {
            for (final id in {for (final a in p.attributes) a.attributeTypeId}) {
              used[id] = (used[id] ?? 0) + 1;
            }
          }
          final rows = [for (final t in types) _Row(t, used[t.id] ?? 0)];
          NxTag status(_Row r) => NxTag(r.t.isActive ? 'Active' : 'Inactive', tone: r.t.isActive ? Tone.ok : Tone.neutral);
          IconData icon(_Row r) => r.number ? PhosphorIconsDuotone.hash : PhosphorIconsDuotone.textAa;
          void toggle(_Row r) => nxToggleActive(
            context,
            name: r.t.name,
            active: r.t.isActive,
            deactivate: () => ref.read(attributeTypesApiProvider).deactivate(r.t.id),
            reactivate: () => ref.read(attributeTypesApiProvider).reactivate(r.t.id),
            refresh: () => invalidateAttributeTypes(ref),
          );

          return NxListPage<_Row>(
            stateKey: 'attributes',
            title: 'Attribute Types',
            sub: 'The admin-managed catalogue behind product attributes. Values are stored as text; Number types validate input.',
            actions: [
              if (canManage)
                NxButton.primary(label: 'New attribute type', icon: PhosphorIconsRegular.plus, onPressed: () => showAttributeTypeFormDialog(context)),
            ],
            rows: rows,
            search: (r) => '${r.t.name} ${r.t.code}',
            searchPlaceholder: 'Name or code',
            stats: (rs) {
              final unused = rs.where((r) => r.used == 0).length;
              return [
                NxStat('Types', fmtNum(rs.length), sub: '${rs.where((r) => r.t.isActive).length} active'),
                NxStat('Text', fmtNum(rs.where((r) => !r.number).length)),
                NxStat('Number', fmtNum(rs.where((r) => r.number).length), sub: '${rs.where((r) => r.hasUnit).length} with units'),
                NxStat('Values in use', fmtNum(rs.fold<int>(0, (s, r) => s + r.used)), sub: 'across products'),
                NxStat('Unused', fmtNum(unused), color: unused > 0 ? n.warn : null),
              ];
            },
            quick: NxQuick(
              get: (r) => r.number ? 'NUMBER' : 'TEXT',
              options: const [('', 'All'), ('TEXT', 'Text'), ('NUMBER', 'Number')],
            ),
            filters: [
              NxSelectFilter('st', 'Status', options: const [('yes', 'Active'), ('no', 'Inactive')], get: (r) => r.t.isActive ? 'yes' : 'no'),
              NxToggleFilter('unit', 'Unit', text: 'Has a unit', get: (r) => r.hasUnit),
              NxRangeFilter('used', 'Products using', get: (r) => r.used),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(key: 'name', label: 'Name', sort: (r) => r.t.name.toLowerCase(), cell: (r) => NxCellText(r.t.name, weight: FontWeight.w500)),
              NxColumn(key: 'code', label: 'Code', sort: (r) => r.t.code, cell: (r) => NxCellText(r.t.code, mono: true, color: n.n300)),
              NxColumn(
                key: 'type',
                label: 'Data type',
                sort: (r) => r.number ? 1 : 0,
                cell: (r) => Align(
                  alignment: Alignment.centerLeft,
                  child: NxTag(r.number ? 'Number' : 'Text', tone: r.number ? Tone.info : Tone.neutral),
                ),
              ),
              NxColumn(
                key: 'unit',
                label: 'Unit',
                hide: NxHide.md,
                cell: (r) => r.hasUnit ? NxCellText(r.t.unit!) : NxCellText('—', color: n.n500),
              ),
              NxColumn(key: 'used', label: 'Products', align: TextAlign.right, sort: (r) => r.used, cell: (r) => NxCellText(fmtNum(r.used), align: TextAlign.right)),
              NxColumn(key: 'status', label: 'Status', cell: (r) => Align(alignment: Alignment.centerLeft, child: status(r))),
              if (canManage)
                NxColumn(
                  key: 'act',
                  label: '',
                  width: 76,
                  cell: (r) => NxRowActions([
                    NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showAttributeTypeFormDialog(context, attributeType: r.t)),
                    NxRowAction(
                      icon: r.t.isActive ? PhosphorIconsRegular.prohibit : PhosphorIconsRegular.arrowCounterClockwise,
                      label: r.t.isActive ? 'Deactivate' : 'Reactivate',
                      danger: r.t.isActive,
                      onPressed: () => toggle(r),
                    ),
                  ]),
                ),
            ],
            listRow: (r) => NxListRowSpec(
              icon: icon(r),
              iconColor: n.a400,
              title: r.t.name,
              sub: '${r.t.code}${r.hasUnit ? ' · ${r.t.unit}' : ''}',
              right: '${r.used} products',
              tag: status(r),
            ),
            card: (r) => NxCardSpec(
              icon: icon(r),
              title: r.t.name,
              sub: r.t.code,
              metrics: [('Type', r.number ? 'Number' : 'Text', null), ('Unit', r.hasUnit ? r.t.unit! : '—', null), ('Products', fmtNum(r.used), null)],
              tag: status(r),
            ),
            onOpen: canManage ? (r) => showAttributeTypeFormDialog(context, attributeType: r.t) : null,
            emptyTitle: 'No attribute types',
            emptyMessage: 'Adjust filters or add a type.',
          );
        },
      ),
    );
  }
}
