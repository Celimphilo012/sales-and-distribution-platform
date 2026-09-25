import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../../workstreams/domain/workstream.dart';
import '../data/categories_providers.dart';
import '../domain/category.dart';
import '../domain/category_tree.dart';
import 'category_form_dialog.dart';

/// Category tree, nested under workstreams: Workstream -> Category ->
/// sub-category (the workstream layer is a catalogue-organization concept —
/// see CLAUDE.md — every category belongs to exactly one workstream). Each
/// workstream renders as its own section with its own tree, reusing 6b's
/// client-side tree-building (`buildCategoryTreeForWorkstream`) since
/// `GET /categories` is still a flat list.
///
/// Deliberately NOT a list/table/grid switcher like Products/Workstreams —
/// this data is hierarchical (parent/sub-category), and flattening it into
/// a table or grid would lose the nesting that's the whole point of a
/// category browser. Still adopts the pattern's other two pieces: a stats
/// strip and compact spacing.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final workstreamsAsync = ref.watch(workstreamsProvider(_includeInactive));
    final categoriesAsync = ref.watch(categoriesProvider(_includeInactive));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Categories', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          categoriesAsync.maybeWhen(
            data: (categories) => _CategoriesStats(categories: categories, workstreamCount: workstreamsAsync.value?.length),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterChip(
            label: const Text('Show inactive'),
            selected: _includeInactive,
            onSelected: (value) => setState(() => _includeInactive = value),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: workstreamsAsync.when(
              loading: () => const LoadingStateView(message: 'Loading workstreams…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load workstreams.',
                onRetry: () => invalidateWorkstreams(ref),
              ),
              data: (workstreams) {
                if (workstreams.isEmpty) {
                  return EmptyStateView(
                    title: 'No workstreams yet',
                    message: canManage
                        ? 'Create a workstream first — every category needs one.'
                        : 'Ask an administrator to create a workstream first.',
                    icon: Icons.workspaces_outlined,
                    action: canManage
                        ? FilledButton.icon(
                            onPressed: () => context.go(RoutePaths.workstreams),
                            icon: const Icon(Icons.workspaces_outlined),
                            label: const Text('Go to Workstreams'),
                          )
                        : null,
                  );
                }
                return categoriesAsync.when(
                  loading: () => const LoadingStateView(message: 'Loading categories…'),
                  error: (error, stackTrace) => ErrorStateView(
                    message: error is AppError ? error.message : 'Could not load categories.',
                    onRetry: () => invalidateCategories(ref),
                  ),
                  data: (categories) => ListView(
                    children: [
                      for (final workstream in workstreams)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: _WorkstreamSection(
                            workstream: workstream,
                            tree: buildCategoryTreeForWorkstream(categories, workstream.id),
                            canManage: canManage,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkstreamSection extends StatelessWidget {
  const _WorkstreamSection({required this.workstream, required this.tree, required this.canManage});

  final Workstream workstream;
  final List<CategoryNode> tree;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final flat = flattenCategoryTree(tree);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspaces_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(workstream.name, style: theme.textTheme.titleMedium),
                    Text(
                      workstream.code,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!workstream.isActive) ...[
                const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (canManage)
                TextButton.icon(
                  onPressed: () => showCategoryFormDialog(context, workstreamId: workstream.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Add category'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (flat.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No categories in this workstream yet.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            for (final node in flat) _CategoryTile(node: node, workstream: workstream, canManage: canManage),
        ],
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.node, required this.workstream, required this.canManage});

  final CategoryNode node;
  final Workstream workstream;
  final bool canManage;

  Future<void> _deactivate(BuildContext context, WidgetRef ref) async {
    final category = node.category;
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate category?',
      message:
          'Products stay linked to "${category.name}" historically; it will no longer be '
          'selectable for new products.',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(categoriesApiProvider).deactivate(category.id);
      invalidateCategories(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _reactivate(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(categoriesApiProvider).update(node.category.id, isActive: true);
      invalidateCategories(ref);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final category = node.category;

    return Padding(
      padding: EdgeInsets.only(left: AppSpacing.lg * (node.depth + 1), right: AppSpacing.sm, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(
            node.children.isEmpty ? Icons.label_outline : Icons.folder_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              category.name,
              style: category.isActive
                  ? theme.textTheme.bodyMedium
                  : theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          if (!category.isActive) ...[
            const StatusBadge(label: 'Inactive', tone: StatusTone.neutral),
            const SizedBox(width: AppSpacing.sm),
          ],
          if (canManage) ...[
            IconButton(
              iconSize: 18,
              tooltip: 'Add subcategory',
              icon: const Icon(Icons.add),
              onPressed: () => showCategoryFormDialog(
                context,
                parentId: category.id,
                workstreamId: workstream.id,
              ),
            ),
            IconButton(
              iconSize: 18,
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showCategoryFormDialog(context, category: category),
            ),
            if (category.isActive)
              IconButton(
                iconSize: 18,
                tooltip: 'Deactivate',
                icon: const Icon(Icons.block),
                onPressed: () => _deactivate(context, ref),
              )
            else
              IconButton(
                iconSize: 18,
                tooltip: 'Reactivate',
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => _reactivate(context, ref),
              ),
          ],
        ],
      ),
    );
  }
}

class _CategoriesStats extends StatelessWidget {
  const _CategoriesStats({required this.categories, required this.workstreamCount});

  final List<Category> categories;
  final int? workstreamCount;

  @override
  Widget build(BuildContext context) {
    final active = categories.where((c) => c.isActive).length;
    final inactive = categories.length - active;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'categories', value: '${categories.length}', icon: Icons.category_outlined),
        StatTile(label: 'active', value: '$active', tone: StatusTone.success, icon: Icons.check_circle_outline),
        if (inactive > 0)
          StatTile(label: 'inactive', value: '$inactive', tone: StatusTone.neutral, icon: Icons.block_outlined),
        if (workstreamCount != null)
          StatTile(label: 'workstreams', value: '$workstreamCount', icon: Icons.workspaces_outlined),
      ],
    );
  }
}
