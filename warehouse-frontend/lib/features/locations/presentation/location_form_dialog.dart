import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';
import '../domain/location_types.dart';

const _customTypeSentinel = 'Custom…';

/// Create or edit a location. Exactly one of the create-mode parameters
/// applies when [location] is null: [parentId] creates a CHILD under that
/// location; [warehouseId] (with [parentId] omitted) creates a
/// warehouse-level ROOT location. Editing never changes the parent — that's
/// the separate move dialog (§G: the real `UpdateLocationDto` deliberately
/// excludes `parentId`).
Future<void> showLocationFormDialog(
  BuildContext context, {
  Location? location,
  String? warehouseId,
  String? parentId,
  String? parentType,
}) {
  assert(location != null || warehouseId != null, 'Creating a location needs a warehouseId');
  return showDialog<void>(
    context: context,
    builder: (context) =>
        _LocationFormDialog(location: location, warehouseId: warehouseId, parentId: parentId, parentType: parentType),
  );
}

class _LocationFormDialog extends ConsumerStatefulWidget {
  const _LocationFormDialog({this.location, this.warehouseId, this.parentId, this.parentType});

  final Location? location;
  final String? warehouseId;
  final String? parentId;

  /// The parent location's own type, when adding a child (null for a root
  /// location or when editing) — narrows the Type dropdown's suggestions;
  /// see [suggestedChildLocationTypes].
  final String? parentType;

  @override
  ConsumerState<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends ConsumerState<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _customTypeController;
  late final List<String> _typeOptions;
  late String _typeSelection;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.location != null;
  bool get _isCustomType => _typeSelection == _customTypeSentinel;

  @override
  void initState() {
    super.initState();
    final l = widget.location;
    _nameController = TextEditingController(text: l?.name ?? '');
    _codeController = TextEditingController(text: l?.code ?? '');
    _descriptionController = TextEditingController(text: l?.description ?? '');

    // Editing never narrows (there's no "parent" being added under here,
    // and an existing location may legitimately carry a type the narrowed
    // list for ITS OWN parent wouldn't suggest) — only a brand-new CHILD's
    // dropdown is narrowed, by the parent's own type.
    _typeOptions = l == null ? suggestedChildLocationTypes(widget.parentType) : kSuggestedLocationTypes;

    final existingType = l?.locationType;
    final isSuggested = existingType != null && kSuggestedLocationTypes.contains(existingType);
    _typeSelection = existingType == null ? _typeOptions.first : (isSuggested ? existingType : _customTypeSentinel);
    _customTypeController = TextEditingController(text: isSuggested ? '' : (existingType ?? ''));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    final locationType = _isCustomType ? _customTypeController.text.trim() : _typeSelection;
    final api = ref.read(locationsApiProvider);
    try {
      if (_isEditing) {
        await api.update(
          widget.location!.id,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          locationType: locationType,
          description: _descriptionController.text.trim(),
        );
        invalidateWarehouseLocations(ref, widget.location!.warehouseId);
      } else if (widget.parentId != null) {
        final child = await api.addChild(
          widget.parentId!,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          locationType: locationType,
          description: _descriptionController.text.trim(),
        );
        invalidateWarehouseLocations(ref, child.warehouseId);
      } else {
        final root = await api.createRoot(
          widget.warehouseId!,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          locationType: locationType,
          description: _descriptionController.text.trim(),
        );
        invalidateWarehouseLocations(ref, root.warehouseId);
      }
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
    return AppDialog(
      title: _isEditing ? 'Edit location' : (widget.parentId != null ? 'Add child location' : 'Add root location'),
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
            AppTextField(
              label: 'Code',
              controller: _codeController,
              helperText: 'Unique within the warehouse',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppDropdownField<String>(
              label: 'Type',
              value: _typeSelection,
              items: [..._typeOptions, _customTypeSentinel],
              itemLabel: (t) => t,
              helperText: _typeOptions.length < kSuggestedLocationTypes.length
                  ? 'Narrowed to likely types under a ${widget.parentType} — pick Custom… for anything else'
                  : 'A label, not a structural limit — pick Custom… for anything else',
              onChanged: (value) => setState(() => _typeSelection = value ?? _typeSelection),
            ),
            if (_isCustomType) ...[
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Custom type',
                controller: _customTypeController,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a type label' : null,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _descriptionController, maxLines: 2),
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
