import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/attribute_types_providers.dart';
import '../domain/attribute_type.dart';
import 'attribute_type_form_dialog.dart';

/// Attribute-types management — the admin-managed catalog behind product
/// attributes (colour, size, weight, ...). Purely reference data: create/
/// edit/deactivate here is how the attribute model stays extensible (a new
/// type is a row here, never a schema change or a product-form code edit).
/// Gated the same way as Categories/Workstreams: visible with
/// `catalogue.view`, manage actions need `products.manage`.
class AttributeTypesScreen extends ConsumerStatefulWidget {
  const AttributeTypesScreen({super.key});

  @override
  ConsumerState<AttributeTypesScreen> createState() => _AttributeTypesScreenState();
}

class _AttributeTypesScreenState extends ConsumerState<AttributeTypesScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final attributeTypesAsync = ref.watch(attributeTypesProvider(_includeInactive));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Attribute Types', style: theme.textTheme.headlineSmall)),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showAttributeTypeFormDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New attribute type'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilterChip(
            label: const Text('Show inactive'),
            selected: _includeInactive,
            onSelected: (value) => setState(() => _includeInactive = value),
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: attributeTypesAsync.when(
              loading: () => const LoadingStateView(message: 'Loading attribute types…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load attribute types.',
                onRetry: () => ref.invalidate(attributeTypesProvider(_includeInactive)),
              ),
              data: (attributeTypes) => AppDataTable<AttributeType>(
                rows: attributeTypes,
                emptyTitle: 'No attribute types yet',
                columns: [
                  AppDataColumn(label: 'Name', cellBuilder: (t) => Text(t.name)),
                  AppDataColumn(label: 'Code', cellBuilder: (t) => Text(t.code)),
                  AppDataColumn(
                    label: 'Data type',
                    cellBuilder: (t) => Text(t.dataType == AttributeDataType.number ? 'Number' : 'Text'),
                  ),
                  AppDataColumn(label: 'Unit', cellBuilder: (t) => Text(t.unit?.isNotEmpty == true ? t.unit! : '—')),
                  AppDataColumn(
                    label: 'Status',
                    cellBuilder: (t) => StatusBadge(
                      label: t.isActive ? 'Active' : 'Inactive',
                      tone: t.isActive ? StatusTone.success : StatusTone.neutral,
                    ),
                  ),
                  if (canManage)
                    AppDataColumn(
                      label: '',
                      cellBuilder: (t) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: 'Edit',
                            onPressed: () => showAttributeTypeFormDialog(context, attributeType: t),
                          ),
                          if (t.isActive)
                            IconButton(
                              icon: const Icon(Icons.block),
                              tooltip: 'Deactivate',
                              onPressed: () => _deactivate(context, t),
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline),
                              tooltip: 'Reactivate',
                              onPressed: () => _reactivate(context, t),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, AttributeType attributeType) async {
    try {
      await ref.read(attributeTypesApiProvider).deactivate(attributeType.id);
      invalidateAttributeTypes(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reactivate(BuildContext context, AttributeType attributeType) async {
    try {
      await ref.read(attributeTypesApiProvider).reactivate(attributeType.id);
      invalidateAttributeTypes(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
