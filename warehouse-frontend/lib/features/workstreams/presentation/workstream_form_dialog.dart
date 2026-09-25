import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/device_image_picker.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../data/workstreams_providers.dart';
import '../domain/workstream.dart';
import 'widgets/workstream_image_view.dart';

/// Create (pass [initialWarehouseId] to preselect, e.g. from a
/// warehouse-scoped context) or edit (pass [workstream]) — a small form,
/// a dialog is enough (warehouse + name + code + description).
Future<void> showWorkstreamFormDialog(
  BuildContext context, {
  Workstream? workstream,
  String? initialWarehouseId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _WorkstreamFormDialog(workstream: workstream, initialWarehouseId: initialWarehouseId),
  );
}

class _WorkstreamFormDialog extends ConsumerStatefulWidget {
  const _WorkstreamFormDialog({this.workstream, this.initialWarehouseId});

  final Workstream? workstream;
  final String? initialWarehouseId;

  @override
  ConsumerState<_WorkstreamFormDialog> createState() => _WorkstreamFormDialogState();
}

T? _firstOrNull<T>(Iterable<T> iterable) {
  for (final item in iterable) {
    return item;
  }
  return null;
}

class _WorkstreamFormDialogState extends ConsumerState<_WorkstreamFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _imageUrlController;
  late final TextEditingController _contactNameController;
  late final TextEditingController _contactEmailController;
  late final TextEditingController _contactPhoneController;
  String? _warehouseId;
  bool _saving = false;
  bool _uploadingImage = false;
  String? _error;

  /// Tracks image changes made via the upload/remove buttons, which take
  /// effect immediately (unlike every other field, saved only on Save) —
  /// starts as [widget.workstream] and is replaced with each call's response
  /// so the preview reflects the current state without waiting for the
  /// list provider to refresh.
  Workstream? _liveWorkstream;

  bool get _isEditing => widget.workstream != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.workstream?.name ?? '');
    _codeController = TextEditingController(text: widget.workstream?.code ?? '');
    _descriptionController = TextEditingController(text: widget.workstream?.description ?? '');
    _imageUrlController = TextEditingController(text: widget.workstream?.imageUrl ?? '');
    _contactNameController = TextEditingController(text: widget.workstream?.contactName ?? '');
    _contactEmailController = TextEditingController(text: widget.workstream?.contactEmail ?? '');
    _contactPhoneController = TextEditingController(text: widget.workstream?.contactPhone ?? '');
    _warehouseId = widget.workstream?.warehouseId ?? widget.initialWarehouseId;
    _liveWorkstream = widget.workstream;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descriptionController.dispose();
    _imageUrlController.dispose();
    _contactNameController.dispose();
    _contactEmailController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_warehouseId == null) {
      setState(() => _error = 'Choose a warehouse.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(workstreamsApiProvider);
    final description = _descriptionController.text.trim();
    final imageUrl = _imageUrlController.text.trim();
    final contactName = _contactNameController.text.trim();
    final contactEmail = _contactEmailController.text.trim();
    final contactPhone = _contactPhoneController.text.trim();
    try {
      if (_isEditing) {
        await api.update(
          widget.workstream!.id,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          description: description.isEmpty ? null : description,
          imageUrl: imageUrl.isEmpty ? null : imageUrl,
          contactName: contactName.isEmpty ? null : contactName,
          contactEmail: contactEmail.isEmpty ? null : contactEmail,
          contactPhone: contactPhone.isEmpty ? null : contactPhone,
        );
      } else {
        await api.create(
          warehouseId: _warehouseId!,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
          description: description.isEmpty ? null : description,
          imageUrl: imageUrl.isEmpty ? null : imageUrl,
          contactName: contactName.isEmpty ? null : contactName,
          contactEmail: contactEmail.isEmpty ? null : contactEmail,
          contactPhone: contactPhone.isEmpty ? null : contactPhone,
        );
      }
      invalidateWorkstreams(ref);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _uploadImage(Uint8List bytes, String fileName) async {
    setState(() {
      _uploadingImage = true;
      _error = null;
    });
    try {
      final updated = await ref
          .read(workstreamsApiProvider)
          .uploadImage(widget.workstream!.id, bytes: bytes, fileName: fileName);
      _imageUrlController.clear();
      if (mounted) setState(() => _liveWorkstream = updated);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() {
      _uploadingImage = true;
      _error = null;
    });
    try {
      final updated = await ref.read(workstreamsApiProvider).removeImage(widget.workstream!.id);
      if (mounted) setState(() => _liveWorkstream = updated);
      invalidateWorkstreams(ref);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warehousesAsync = ref.watch(warehousesProvider(false));
    final liveWorkstream = _liveWorkstream;

    return AppDialog(
      title: _isEditing ? 'Edit workstream' : 'New workstream',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isEditing)
              warehousesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => const SizedBox.shrink(),
                data: (warehouses) {
                  final warehouse = _firstOrNull(warehouses.where((w) => w.id == _warehouseId));
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: Text(
                      'Warehouse: ${warehouse?.name ?? widget.workstream!.warehouseId}',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  );
                },
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: warehousesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(
                    'Could not load warehouses',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  data: (warehouses) => AppDropdownField<String>(
                    label: 'Warehouse',
                    value: _warehouseId,
                    items: [for (final w in warehouses) w.id],
                    itemLabel: (id) => warehouses.firstWhere((w) => w.id == id).name,
                    onChanged: (value) => setState(() => _warehouseId = value),
                    validator: (v) => v == null ? 'Choose a warehouse' : null,
                  ),
                ),
              ),
            AppTextField(
              label: 'Name',
              controller: _nameController,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Code',
              controller: _codeController,
              helperText: 'Unique within this warehouse',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Description (optional)', controller: _descriptionController, maxLines: 2),
            const SizedBox(height: AppSpacing.md),
            if (_isEditing && (liveWorkstream?.hasImage ?? false)) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                child: SizedBox(width: double.infinity, height: 100, child: WorkstreamImageView(workstream: liveWorkstream!)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _uploadingImage ? null : _removeImage,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove image'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Image URL (optional)',
                    controller: _imageUrlController,
                    hintText: 'https://…',
                  ),
                ),
                if (_isEditing) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: DeviceImagePicker(enabled: !_uploadingImage, onPicked: _uploadImage),
                  ),
                ],
              ],
            ),
            if (!_isEditing)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Uploading from device is available once the workstream is created.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Contact', style: theme.textTheme.labelLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppTextField(label: 'Contact person (optional)', controller: _contactNameController),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Contact email (optional)',
              controller: _contactEmailController,
              hintText: 'name@example.com',
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Contact phone (optional)',
              controller: _contactPhoneController,
              hintText: '+268 7612 3456',
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
