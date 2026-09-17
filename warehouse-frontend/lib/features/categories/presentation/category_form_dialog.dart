import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../data/categories_providers.dart';
import '../domain/category.dart';
import '../domain/category_tree.dart';

/// Create (optionally under [parentId], within [workstreamId]) or edit (pass
/// [category]) a category. A dialog is enough here — the form is just name +
/// workstream + parent, unlike products.
///
/// The workstream picker is LOCKED whenever a [parentId] is supplied while
/// creating (adding a subcategory from a specific workstream's tree section)
/// — a sub-category must belong to the same workstream as its parent
/// (backend-enforced), so there is nothing to choose. It stays editable when
/// creating a root category or editing any existing category; the "Parent
/// category" dropdown is always scoped to the CURRENTLY selected workstream,
/// so an invalid cross-workstream parent is never even offered (same
/// "narrow the choices so the backend never has to reject them" idiom as the
/// leaf-location picker).
Future<void> showCategoryFormDialog(
  BuildContext context, {
  Category? category,
  String? parentId,
  String? workstreamId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _CategoryFormDialog(category: category, parentId: parentId, workstreamId: workstreamId),
  );
}

T? _firstOrNull<T>(Iterable<T> iterable) {
  for (final item in iterable) {
    return item;
  }
  return null;
}

class _CategoryFormDialog extends ConsumerStatefulWidget {
  const _CategoryFormDialog({this.category, this.parentId, this.workstreamId});

  final Category? category;
  final String? parentId;
  final String? workstreamId;

  @override
  ConsumerState<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends ConsumerState<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  String? _parentId;
  String? _workstreamId;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.category != null;

  /// The workstream can't be changed here when adding a subcategory (it's
  /// implied by the parent) — locked in that one case only.
  bool get _workstreamLocked => !_isEditing && widget.parentId != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name ?? '');
    _parentId = widget.category?.parentId ?? widget.parentId;
    _workstreamId = widget.category?.workstreamId ?? widget.workstreamId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_workstreamId == null) {
      setState(() => _error = 'Choose a workstream.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(categoriesApiProvider);
    try {
      if (_isEditing) {
        await api.update(
          widget.category!.id,
          name: _nameController.text.trim(),
          parentId: _parentId,
          workstreamId: _workstreamId,
        );
      } else {
        await api.create(name: _nameController.text.trim(), workstreamId: _workstreamId!, parentId: _parentId);
      }
      invalidateCategories(ref);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workstreamsAsync = ref.watch(workstreamsProvider(false));
    final categoriesAsync = ref.watch(categoriesProvider(false));

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
            workstreamsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => Text(
                'Could not load workstreams',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              data: (workstreams) {
                if (_workstreamLocked) {
                  final workstream = _firstOrNull(workstreams.where((w) => w.id == _workstreamId));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Workstream: ${workstream?.name ?? _workstreamId}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppDropdownField<String>(
                    label: 'Workstream',
                    value: _workstreamId,
                    items: [for (final w in workstreams) w.id],
                    itemLabel: (id) => workstreams.firstWhere((w) => w.id == id).name,
                    onChanged: (value) => setState(() {
                      _workstreamId = value;
                      // A parent from the old workstream is never valid once
                      // the workstream changes — the backend would reject it.
                      _parentId = null;
                    }),
                    validator: (v) => v == null ? 'Choose a workstream' : null,
                  ),
                );
              },
            ),
            categoriesAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, stackTrace) => const SizedBox.shrink(),
              data: (categories) {
                if (_workstreamId == null) return const SizedBox.shrink();
                final tree = buildCategoryTreeForWorkstream(categories, _workstreamId!);
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
          onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
