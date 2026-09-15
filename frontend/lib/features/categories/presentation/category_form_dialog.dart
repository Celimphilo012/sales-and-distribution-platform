import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/categories_providers.dart';
import '../domain/category.dart';
import '../domain/category_tree.dart';

/// Create (optionally under [parentId]) or edit (pass [category]) a
/// category. A dialog is enough here — categories only ever have a name and
/// a parent, unlike products.
Future<void> showCategoryFormDialog(
  BuildContext context, {
  Category? category,
  String? parentId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CategoryFormDialog(category: category, parentId: parentId),
  );
}

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({this.category, this.parentId});

  final Category? category;
  final String? parentId;

  @override
  ConsumerState<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _parentId;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.category != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _parentId = widget.category?.parentId ?? widget.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(categoriesApiProvider);
    try {
      if (_isEditing) {
        await api.update(widget.category!.id, name: _nameController.text.trim(), parentId: _parentId);
      } else {
        await api.create(name: _nameController.text.trim(), parentId: _parentId);
      }
      invalidateCategories(ref);
      if (mounted) Navigator.of(context).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final treeAsync = ref.watch(categoryTreeProvider(false));

    return AppDialog(
      title: _isEditing ? 'Edit category' : 'New category',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Name',
              controller: _nameController,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            treeAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (tree) {
                final flat = flattenCategoryTree(tree);
                final excluded = _isEditing ? descendantIds(tree, widget.category!.id) : const <String>{};
                final options = flat.where((n) => !excluded.contains(n.category.id)).toList();
                return AppDropdownField<String?>(
                  label: 'Parent category',
                  value: _parentId,
                  items: [null, for (final node in options) node.category.id],
                  itemLabel: (id) {
                    if (id == null) return 'None (top level)';
                    final node = options.firstWhere((n) => n.category.id == id);
                    return '${'    ' * node.depth}${node.category.name}';
                  },
                  onChanged: (value) => setState(() => _parentId = value),
                );
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
