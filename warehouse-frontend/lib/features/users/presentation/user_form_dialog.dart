import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../roles/data/roles_providers.dart';
import '../../roles/domain/role.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/users_providers.dart';
import '../domain/user.dart';

/// Chips that toggle membership of a set (the prototype's "multi" field).
class _Chips extends StatelessWidget {
  const _Chips({required this.options, required this.selected, required this.onChanged});

  final List<(String, String)> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final (id, label) in options)
        NxChipToggle(
          label: label,
          selected: selected.contains(id),
          showCheck: true,
          onTap: () => onChanged(selected.contains(id) ? ({...selected}..remove(id)) : {...selected, id}),
        ),
    ],
  );
}

/// New / edit user (the prototype's user form, 560px): name, email (fixed
/// once created), roles, warehouses (with `warehouse.access.assign`), mobile
/// and notification channel, status — plus a starting password on create
/// and, when editing, the sign-in check with a reset for a lost device.
Future<void> showUserFormDialog(BuildContext context, {WarehouseUser? user}) =>
    showNxDialog<void>(context, width: 560, builder: (_) => _UserForm(user: user));

class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({this.user});

  final WarehouseUser? user;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  late final _name = TextEditingController(text: widget.user?.fullName ?? '');
  late final _email = TextEditingController(text: widget.user?.email ?? '');
  late final _phone = TextEditingController(text: widget.user?.phone ?? '');
  final _password = TextEditingController();
  late UserStatus _status = widget.user?.status ?? UserStatus.active;
  late String _notify = widget.user?.notifyChannel ?? 'EMAIL';
  late Set<String> _roles = {...?widget.user?.roles.map((r) => r.id)};
  late Set<String> _warehouses = {...?widget.user?.warehouses.map((w) => w.id)};
  late String _mfa = widget.user?.mfaMethod ?? 'NONE';
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  bool get _editing => widget.user != null;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit({required bool canAssign}) async {
    final email = _email.text.trim();
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (!_editing && !RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) 'email': 'Enter a valid email',
      if (!_editing && _password.text.length < 8) 'password': 'At least 8 characters',
      if (_roles.isEmpty) 'roles': 'Pick at least one role',
      if (_notify == 'SMS' && _phone.text.trim().isEmpty) 'phone': 'SMS notifications need a mobile number',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    final api = ref.read(usersApiProvider);
    final phone = _phone.text.trim();
    try {
      final WarehouseUser saved;
      if (_editing) {
        saved = await api.update(
          widget.user!.id,
          fullName: _name.text.trim(),
          status: _status,
          phone: phone,
          notifyChannel: _notify,
          roleIds: _roles.toList(),
        );
      } else {
        saved = await api.create(
          email: email,
          password: _password.text,
          fullName: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          notifyChannel: _notify,
          roleIds: _roles.toList(),
        );
      }
      final before = {...?widget.user?.warehouses.map((w) => w.id)};
      final changed = before.length != _warehouses.length || !before.containsAll(_warehouses);
      if (canAssign && changed) await api.setWarehouses(saved.id, _warehouses.toList());
      ref.invalidate(usersListProvider);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok(_editing ? 'User updated' : 'User created', _editing ? saved.fullName : '${saved.fullName} · ${saved.email}');
    } on AppError catch (e) {
      setState(() {
        if (e.message.toLowerCase().contains('email')) {
          _errors['email'] = e.message;
        } else {
          _formError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetMfa() async {
    setState(() => _saving = true);
    try {
      final updated = await ref.read(usersApiProvider).resetMfa(widget.user!.id);
      ref.invalidate(usersListProvider);
      setState(() => _mfa = updated.mfaMethod);
      NxToast.ok('Sign-in check turned off', '${updated.fullName} can set it up again themselves.');
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final canAssign = ref.watch(authProvider.select((s) => s.value?.user?.can('warehouse.access.assign') ?? false));
    final roles = ref.watch(rolesListProvider).value ?? const <Role>[];
    final warehouses = canAssign ? ref.watch(warehousesProvider(true)).value ?? const <Warehouse>[] : const <Warehouse>[];

    return NxDialogFrame(
      title: _editing ? 'Edit user' : 'New user',
      sub: _editing ? widget.user!.email : 'They sign in with this email and the starting password you set.',
      body: NxFormGrid(
        children: [
          NxField(
            label: 'Full name',
            required: true,
            error: _errors['name'],
            child: NxInput(controller: _name, error: _errors['name'] != null, autofocus: !_editing),
          ),
          NxField(
            label: 'Email',
            required: true,
            error: _errors['email'],
            child: NxInput(controller: _email, enabled: !_editing, keyboardType: TextInputType.emailAddress, error: _errors['email'] != null),
          ),
          if (!_editing)
            NxSpan2(
              child: NxField(
                label: 'Starting password',
                required: true,
                error: _errors['password'],
                hint: 'At least 8 characters — share it with them privately',
                child: NxInput(controller: _password, obscure: true, error: _errors['password'] != null),
              ),
            ),
          NxSpan2(
            child: NxField(
              label: 'Roles',
              required: true,
              error: _errors['roles'],
              child: _Chips(options: [for (final r in roles) (r.id, r.name)], selected: _roles, onChanged: (v) => setState(() => _roles = v)),
            ),
          ),
          if (canAssign)
            NxSpan2(
              child: NxField(
                label: 'Warehouses',
                hint: 'They see and work in only these (all-warehouse roles see every one)',
                child: _Chips(
                  options: [for (final w in warehouses) (w.id, '${w.name} · ${w.code}${w.isActive ? '' : ' (inactive)'}')],
                  selected: _warehouses,
                  onChanged: (v) => setState(() => _warehouses = v),
                ),
              ),
            ),
          NxField(
            label: 'Mobile number',
            error: _errors['phone'],
            hint: 'International format — for SMS codes and alerts',
            child: NxInput(controller: _phone, placeholder: '+268 7612 3456', keyboardType: TextInputType.phone, error: _errors['phone'] != null),
          ),
          NxField(
            label: 'Notifications',
            child: NxSelect<String>(
              options: [for (final e in kNotifyChannelLabels.entries) NxOption(e.key, e.value)],
              value: _notify,
              onChanged: (v) => setState(() => _notify = v ?? 'EMAIL'),
            ),
          ),
          if (_editing) ...[
            NxField(
              label: 'Sign-in check',
              hint: 'Each user sets this up themselves in Settings',
              child: Row(
                children: [
                  Expanded(child: Text(kMfaMethodLabels[_mfa] ?? _mfa, style: TextStyle(fontSize: 13, color: n.text))),
                  if (_mfa != 'NONE') NxButton.ghost(label: 'Reset (lost device)', small: true, onPressed: _saving ? null : _resetMfa),
                ],
              ),
            ),
            NxField(
              label: 'Status',
              child: Align(
                alignment: Alignment.centerLeft,
                child: NxSeg<UserStatus>(
                  options: [for (final s in UserStatus.values) (s, s.label, null)],
                  value: _status,
                  onChanged: (v) => setState(() => _status = v),
                ),
              ),
            ),
          ],
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(
          label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Create user'),
          onPressed: _saving ? null : () => _submit(canAssign: canAssign),
        ),
      ],
    );
  }
}

/// An administrator sets a new password for [user] (their old one stops
/// working immediately).
Future<void> showResetPasswordDialog(BuildContext context, WarehouseUser user) =>
    showNxDialog<void>(context, builder: (_) => _ResetPassword(user: user));

class _ResetPassword extends ConsumerStatefulWidget {
  const _ResetPassword({required this.user});

  final WarehouseUser user;

  @override
  ConsumerState<_ResetPassword> createState() => _ResetPasswordState();
}

class _ResetPasswordState extends ConsumerState<_ResetPassword> {
  final _pw = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _pw.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pw.text.length < 8) {
      setState(() => _error = 'At least 8 characters');
      return;
    }
    if (_pw.text != _confirm.text) {
      setState(() => _error = 'The two passwords don’t match');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(usersApiProvider).update(widget.user.id, password: _pw.text);
      if (mounted) Navigator.of(context).pop();
      NxToast.ok('Password reset', '${widget.user.fullName} must use the new password from now on.');
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: 'Reset password for ${widget.user.fullName}?',
      sub: 'Their current password stops working immediately. Share the new one with them privately.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxField(label: 'New password', required: true, child: NxInput(controller: _pw, obscure: true, autofocus: true, error: _error != null)),
          const SizedBox(height: 10),
          NxField(label: 'Repeat it', required: true, child: NxInput(controller: _confirm, obscure: true, error: _error != null, onSubmitted: (_) => _submit())),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)),
          ],
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Saving…' : 'Set password', onPressed: _saving ? null : _submit),
      ],
    );
  }
}
