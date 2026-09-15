import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/categories_providers.dart';
import '../domain/category_tree.dart';
import 'category_form_dialog.dart';

/// Category tree + CRUD. Unlike products, a dialog is enough here — the
/// form is just name + parent — but the tree display itself is its own
/// clear, indented component.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    final treeAsync = ref.watch(categoryTreeProvider(true));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Categories', style: theme.textTheme.headlineSmall)),
              if (canManage)
                FilledButton.icon(
                  onPressed: () => showCategoryFormDialog(context, parentId: null),
                  icon: const Icon(Icons.add),
                  label: const Text('New category'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: treeAsync.when(
              loading: () => const LoadingStateView(message: 'Loading categories…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load categories.',
                onRetry: () => invalidateCategories(ref),
              ),
              data: (tree) {
                final flat = flattenCategoryTree(tree);
                if (flat.isEmpty) {
                  return const EmptyStateView(title: 'No categories yet', icon: Icons.category_outlined);
                }
                return Card(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    children: [for (final node in flat) _CategoryTile(node: node, canManage: canManage)],
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

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.node, required this.canManage});

  final CategoryNode node;
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
      padding: EdgeInsets.only(left: AppSpacing.lg * node.depth, right: AppSpacing.sm, top: 4, bottom: 4),
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
              onPressed: () => showCategoryFormDialog(context, parentId: category.id),
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
