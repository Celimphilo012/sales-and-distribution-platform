import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/roles_providers.dart';
import '../domain/role.dart';

/// Create (no [role]) or edit (pass [role]) a role's name/description.
/// Permission assignment lives on [RoleDetailScreen] instead — too much
/// surface for a dialog, same split as products (dialog for the small stuff,
/// a routed screen for the rest).
Future<void> showRoleFormDialog(BuildContext context, {Role? role}) {
  return showDialog<void>(context: context, builder: (context) => _RoleFormDialog(role: role));
}

class _RoleFormDialog extends ConsumerStatefulWidget {
  const _RoleFormDialog({this.role});

  final Role? role;

  @override
  ConsumerState<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends ConsumerState<_RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.role != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.role?.name ?? '');
    _descriptionController = TextEditingController(text: widget.role?.description ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(rolesApiProvider);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    try {
      if (_isEditing) {
        await api.update(widget.role!.id, name: name, description: description);
      } else {
        await api.create(name: name, description: description.isEmpty ? null : description);
      }
      invalidateRoles(ref);
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
    final isSystem = widget.role?.isSystem ?? false;

    return AppDialog(
      title: _isEditing ? 'Edit role' : 'New role',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(
              label: 'Name',
              controller: _nameController,
              enabled: !isSystem,
              helperText: isSystem ? 'System roles cannot be renamed' : null,
              validator: (v) => (v == null || v.trim().length < 2) ? 'At least 2 characters' : null,
            ),
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
