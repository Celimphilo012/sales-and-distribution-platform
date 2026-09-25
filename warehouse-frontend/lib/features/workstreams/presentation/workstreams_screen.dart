import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';
import 'widgets/workstream_image_view.dart';
import 'workstream_form_dialog.dart';
import 'workstream_managers_dialog.dart';

/// Workstreams management — a catalogue-organization layer (Warehouse ->
/// Workstream -> Category -> sub-category -> Product), purely reference
/// data: create/edit/deactivate here, never anything operational. Visible
/// with `catalogue.view`; editing the workstream record itself needs
/// `workstreams.manage`; assigning who can manage its CATALOGUE (categories
/// + products, scoped) needs `workstreams.assign` — a separate, narrower
/// permission, since deciding who touches a workstream is more sensitive
/// than doing the catalogue work itself.
class WorkstreamsScreen extends ConsumerStatefulWidget {
  const WorkstreamsScreen({super.key});

  @override
  ConsumerState<WorkstreamsScreen> createState() => _WorkstreamsScreenState();
}

class _WorkstreamsScreenState extends ConsumerState<WorkstreamsScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('workstreams.manage') ?? false));
    final canAssign = ref.watch(authProvider.select((s) => s.value?.user?.can('workstreams.assign') ?? false));
    final workstreamsAsync = ref.watch(workstreamsProvider(_includeInactive));
    final warehousesAsync = ref.watch(warehousesProvider(true));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Workstreams', style: theme.textTheme.headlineSmall)),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showWorkstreamFormDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('New workstream'),
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
            child: workstreamsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading workstreams…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load workstreams.',
                onRetry: () => ref.invalidate(workstreamsProvider(_includeInactive)),
              ),
              data: (workstreams) {
                final warehouseNames = {
                  for (final w in warehousesAsync.value ?? const []) w.id: w.name,
                };
                return AppDataTable<Workstream>(
                  rows: workstreams,
                  emptyTitle: 'No workstreams yet',
                  columns: [
                    AppDataColumn(
                      label: '',
                      cellBuilder: (w) => ClipRRect(
                        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: w.hasImage
                              ? WorkstreamImageView(workstream: w)
                              : ColoredBox(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(Icons.image_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                                ),
                        ),
                      ),
                    ),
                    AppDataColumn(label: 'Name', cellBuilder: (w) => Text(w.name)),
                    AppDataColumn(label: 'Code', cellBuilder: (w) => Text(w.code)),
                    AppDataColumn(
                      label: 'Warehouse',
                      cellBuilder: (w) => Text(warehouseNames[w.warehouseId] ?? w.warehouseId),
                    ),
                    AppDataColumn(label: 'Contact', cellBuilder: (w) => _ContactCell(workstream: w)),
                    AppDataColumn(
                      label: 'Status',
                      cellBuilder: (w) => StatusBadge(
                        label: w.isActive ? 'Active' : 'Inactive',
                        tone: w.isActive ? StatusTone.success : StatusTone.neutral,
                      ),
                    ),
                    if (canManage || canAssign)
                      AppDataColumn(
                        label: '',
                        cellBuilder: (w) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (canAssign)
                              IconButton(
                                icon: const Icon(Icons.people_outline),
                                tooltip: 'Managers',
                                onPressed: () => showWorkstreamManagersDialog(context, w),
                              ),
                            if (canManage) ...[
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => showWorkstreamFormDialog(context, workstream: w),
                              ),
                              if (w.isActive)
                                IconButton(
                                  icon: const Icon(Icons.block),
                                  tooltip: 'Deactivate',
                                  onPressed: () => _deactivate(context, w),
                                )
                              else
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline),
                                  tooltip: 'Reactivate',
                                  onPressed: () => _reactivate(context, w),
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deactivate(BuildContext context, Workstream workstream) async {
    try {
      await ref.read(workstreamsApiProvider).deactivate(workstream.id);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reactivate(BuildContext context, Workstream workstream) async {
    try {
      await ref.read(workstreamsApiProvider).reactivate(workstream.id);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

/// Compact contact-info cell — contact person's name on top (if given),
/// email + phone combined onto ONE line below it (not two): the table's
/// rows are height-capped for compactness, and a 3-line cell overflowed it.
/// "—" when there's no contact info at all.
class _ContactCell extends StatelessWidget {
  const _ContactCell({required this.workstream});

  final Workstream workstream;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!workstream.hasContactInfo) {
      return Text('—', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }

    final emailAndPhone = [
      ?workstream.contactEmail,
      ?workstream.contactPhone,
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (workstream.contactName != null)
          Text(workstream.contactName!, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        if (emailAndPhone.isNotEmpty)
          Text(
            emailAndPhone,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}
