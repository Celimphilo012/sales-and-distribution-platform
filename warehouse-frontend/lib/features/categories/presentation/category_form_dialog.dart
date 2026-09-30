import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../workstreams/data/workstreams_providers.dart';
import '../../workstreams/domain/workstream.dart';
import '../data/categories_providers.dart';
import '../domain/category.dart';

/// New category / sub-category (pass [parentId]) or edit ([category]) — the
/// prototype's category form. A sub-category always belongs to its parent's
/// workstream (backend-enforced), so the workstream is inherited, not chosen,
/// once a parent is set.
Future<void> showCategoryFormDialog(BuildContext context, {Category? category, String? parentId, String? workstreamId}) =>
    showNxDialog<void>(
      context,
      builder: (_) => _CategoryForm(category: category, parentId: parentId, workstreamId: workstreamId),
    );

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({this.category, this.parentId, this.workstreamId});

  final Category? category;
  final String? parentId;
  final String? workstreamId;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String? _parentId = widget.category?.parentId ?? widget.parentId;
  late String? _workstreamId = widget.category?.workstreamId ?? widget.workstreamId;
  late bool _active = widget.category?.isActive ?? true;
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.category != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// This category and everything under it — never offered as its own parent.
  Set<String> _selfAndBelow(List<Category> all) {
    final id = widget.category?.id;
    if (id == null) return const {};
    final out = {id};
    var grew = true;
    while (grew) {
      grew = false;
      for (final c in all) {
        if (c.parentId != null && out.contains(c.parentId) && out.add(c.id)) grew = true;
      }
    }
    return out;
  }

  Future<void> _submit(Map<String, Category> byId) async {
    final ws = _parentId != null ? byId[_parentId]?.workstreamId : _workstreamId;
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (ws == null) 'ws': 'Choose a workstream',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final api = ref.read(categoriesApiProvider);
    try {
      if (_editing) {
        final c = widget.category!;
        await api.update(
          c.id,
          name: _name.text.trim(),
          parentId: _parentId,
          workstreamId: _parentId == null ? ws : null,
          isActive: _active != c.isActive && _active ? true : null,
        );
        if (!_active && c.isActive) await api.deactivate(c.id);
      } else {
        final created = await api.create(name: _name.text.trim(), workstreamId: ws!, parentId: _parentId);
        if (!_active) await api.deactivate(created.id);
      }
      invalidateCategories(ref);
      if (mounted) Navigator.of(context).pop();
      final parent = _parentId == null ? null : byId[_parentId];
      NxToast.ok(_editing ? 'Category updated' : 'Category created', '${_name.text.trim()}${parent == null ? '' : ' under ${parent.name}'}');
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final all = ref.watch(categoriesProvider(true)).value ?? const <Category>[];
    final workstreams = ref.watch(workstreamsProvider(true)).value ?? const <Workstream>[];
    final byId = {for (final c in all) c.id: c};
    final excluded = _selfAndBelow(all);
    String path(Category c) => c.parentId != null && byId[c.parentId] != null ? '${path(byId[c.parentId]!)} › ${c.name}' : c.name;
    final parentOptions = [
      const NxOption<String>('', '— None (top level)'),
      ...[
        for (final c in all.where((c) => !excluded.contains(c.id) && (c.isActive || c.id == _parentId)))
          NxOption(c.id, path(c), sub: c.workstream?.name),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase())),
    ];
    final inherited = _parentId == null ? null : byId[_parentId]?.workstreamId;

    return NxDialogFrame(
      title: _editing ? 'Edit category' : (widget.parentId != null ? 'New sub-category' : 'New category'),
      sub: 'A sub-category always belongs to its parent’s workstream.',
      body: NxFormGrid(
        children: [
          NxSpan2(
            child: NxField(
              label: 'Name',
              required: true,
              error: _errors['name'],
              child: NxInput(controller: _name, error: _errors['name'] != null, autofocus: true),
            ),
          ),
          NxSpan2(
            child: NxField(
              label: 'Parent category',
              child: NxSelect<String>(
                options: parentOptions,
                value: _parentId ?? '',
                searchable: parentOptions.length > 8,
                searchPlaceholder: 'Search categories',
                onChanged: (v) => setState(() => _parentId = (v == null || v.isEmpty) ? null : v),
              ),
            ),
          ),
          NxField(
            label: 'Workstream',
            required: true,
            error: _errors['ws'],
            hint: 'Ignored for sub-categories — inherited from the parent',
            child: NxSelect<String>(
              options: [for (final w in workstreams.where((w) => w.isActive || w.id == _workstreamId || w.id == inherited)) NxOption(w.id, w.name)],
              value: inherited ?? _workstreamId,
              enabled: inherited == null,
              error: _errors['ws'] != null,
              placeholder: 'Choose a workstream',
              onChanged: (v) => setState(() => _workstreamId = v),
            ),
          ),
          NxField(
            label: 'Status',
            child: Align(
              alignment: Alignment.centerLeft,
              child: NxSeg<bool>(
                options: const [(true, 'Active', null), (false, 'Inactive', null)],
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create category'),
          onPressed: _saving ? null : () => _submit(byId),
        ),
      ],
    );
  }
}
