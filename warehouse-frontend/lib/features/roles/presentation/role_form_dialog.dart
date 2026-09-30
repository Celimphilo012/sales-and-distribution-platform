import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/roles_providers.dart';
import '../domain/role.dart';
import 'role_permissions_sheet.dart';

/// New / edit role (name + description). A new role opens its permission
/// sheet next, to choose what it grants.
Future<void> showRoleFormDialog(BuildContext context, {Role? role}) =>
    showNxDialog<void>(context, builder: (_) => _RoleForm(role: role));

class _RoleForm extends ConsumerStatefulWidget {
  const _RoleForm({this.role});

  final Role? role;

  @override
  ConsumerState<_RoleForm> createState() => _RoleFormState();
}

class _RoleFormState extends ConsumerState<_RoleForm> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late final _desc = TextEditingController(text: widget.role?.description ?? '');
  String? _nameErr;
  String? _formError;
  bool _saving = false;

  bool get _editing => widget.role != null;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameErr = 'Required');
      return;
    }
    setState(() {
      _saving = true;
      _nameErr = null;
      _formError = null;
    });
    final api = ref.read(rolesApiProvider);
    try {
      final desc = _desc.text.trim();
      if (_editing) {
        await api.update(widget.role!.id, name: widget.role!.isSystem ? null : _name.text.trim(), description: desc);
        invalidateRoles(ref);
        if (mounted) Navigator.of(context).pop();
        NxToast.ok('Role updated', _name.text.trim());
      } else {
        final created = await api.create(name: _name.text.trim(), description: desc.isEmpty ? null : desc);
        invalidateRoles(ref);
        if (!mounted) return;
        final nav = Navigator.of(context);
        final root = nav.context;
        nav.pop();
        NxToast.ok('Role created', 'Now choose its permissions.');
        if (root.mounted) showRolePermissionsSheet(root, created.id);
      }
    } on AppError catch (e) {
      setState(() {
        if (e.message.toLowerCase().contains('name')) {
          _nameErr = e.message;
        } else {
          _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final system = widget.role?.isSystem ?? false;
    return NxDialogFrame(
      title: _editing ? 'Edit role' : 'New role',
      sub: 'Set permissions on the role’s permission sheet.',
      body: NxFormGrid(
        children: [
          NxSpan2(
            child: NxField(
              label: 'Name',
              required: true,
              error: _nameErr,
              hint: system ? 'System roles cannot be renamed' : null,
              child: NxInput(controller: _name, enabled: !system, error: _nameErr != null, autofocus: !system),
            ),
          ),
          NxSpan2(child: NxField(label: 'Description', child: NxInput(controller: _desc, maxLines: 3, minLines: 2))),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create role'), onPressed: _saving ? null : _submit),
      ],
    );
  }
}
