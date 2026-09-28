import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_multi_select_list.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../roles/data/roles_providers.dart';
import '../../roles/domain/role.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/users_providers.dart';
import '../domain/user.dart';

/// Create (no [user]) or edit (pass [user]) a warehouse user: email is
/// create-only (`CreateUserDto` has no counterpart field on `UpdateUserDto`
/// — the backend never supports changing it), password is required on
/// create and an optional reset field on edit, and role assignment is a
/// FULL REPLACE of the user's role set either way (`roleIds`). Warehouse
/// access (deny by default) is set here too, for admins holding
/// `warehouse.access.assign`; so are the phone number and notification channel.
Future<void> showUserFormDialog(BuildContext context, {WarehouseUser? user}) {
  return showDialog<void>(context: context, builder: (context) => _UserFormDialog(user: user));
}

class _UserFormDialog extends ConsumerStatefulWidget {
  const _UserFormDialog({this.user});

  final WarehouseUser? user;

  @override
  ConsumerState<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _phoneController;
  late UserStatus _status;
  late String _notifyChannel;
  late Set<String> _selectedRoleIds;
  late Set<String> _selectedWarehouseIds;
  late String _mfaMethod;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.user != null;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.user?.email ?? '');
    _fullNameController = TextEditingController(text: widget.user?.fullName ?? '');
    _passwordController = TextEditingController();
    _phoneController = TextEditingController(text: widget.user?.phone ?? '');
    _status = widget.user?.status ?? UserStatus.active;
    _notifyChannel = widget.user?.notifyChannel ?? 'EMAIL';
    _selectedRoleIds = (widget.user?.roles ?? const []).map((r) => r.id).toSet();
    _selectedWarehouseIds = (widget.user?.warehouses ?? const []).map((w) => w.id).toSet();
    _mfaMethod = widget.user?.mfaMethod ?? 'NONE';
  }

  @override
  void dispose() {
    _emailController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(usersApiProvider);
    final fullName = _fullNameController.text.trim();
    final password = _passwordController.text.trim();
    final phone = _phoneController.text.trim();
    final canAssign = ref.read(authProvider).value?.user?.can('warehouse.access.assign') ?? false;
    try {
      final WarehouseUser saved;
      if (_isEditing) {
        saved = await api.update(
          widget.user!.id,
          fullName: fullName,
          password: password.isEmpty ? null : password,
          status: _status,
          phone: phone, // '' clears it
          notifyChannel: _notifyChannel,
          roleIds: _selectedRoleIds.toList(),
        );
      } else {
        saved = await api.create(
          email: _emailController.text.trim(),
          password: password,
          fullName: fullName,
          phone: phone.isEmpty ? null : phone,
          notifyChannel: _notifyChannel,
          roleIds: _selectedRoleIds.toList(),
        );
      }
      final before = (widget.user?.warehouses ?? const []).map((w) => w.id).toSet();
      final changed = before.length != _selectedWarehouseIds.length || !before.containsAll(_selectedWarehouseIds);
      if (canAssign && changed) await api.setWarehouses(saved.id, _selectedWarehouseIds.toList());
      ref.invalidate(usersListProvider);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetMfa() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(usersApiProvider).resetMfa(widget.user!.id);
      ref.invalidate(usersListProvider);
      setState(() => _mfaMethod = updated.mfaMethod);
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rolesAsync = ref.watch(rolesListProvider);
    final canAssign = ref.watch(authProvider.select((s) => s.value?.user?.can('warehouse.access.assign') ?? false));
    // Inactive warehouses too: an assignment to one must stay visible so it can be removed.
    final warehousesAsync = canAssign ? ref.watch(warehousesProvider(true)) : null;

    return AppDialog(
      title: _isEditing ? 'Edit user' : 'New user',
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                label: 'Email',
                controller: _emailController,
                enabled: !_isEditing,
                helperText: _isEditing ? 'Email cannot be changed after creation' : null,
                keyboardType: TextInputType.emailAddress,
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Full name',
                controller: _fullNameController,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: _isEditing ? 'New password (leave blank to keep current)' : 'Password',
                controller: _passwordController,
                obscureText: true,
                validator: (v) {
                  if (_isEditing && (v == null || v.isEmpty)) return null;
                  if (v == null || v.length < 8) return 'At least 8 characters';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Mobile number (optional)',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                hintText: '+268 7612 3456',
                helperText: 'International format — used for SMS codes and SMS notifications',
              ),
              const SizedBox(height: AppSpacing.md),
              AppDropdownField<String>(
                label: 'Notifications',
                value: _notifyChannel,
                items: kNotifyChannelLabels.keys.toList(),
                itemLabel: (c) => kNotifyChannelLabels[c]!,
                onChanged: (value) {
                  if (value != null) setState(() => _notifyChannel = value);
                },
              ),
              if (_isEditing) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sign-in verification: ${kMfaMethodLabels[_mfaMethod] ?? _mfaMethod}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    if (_mfaMethod != 'NONE')
                      TextButton(onPressed: _saving ? null : _resetMfa, child: const Text('Reset (lost device)')),
                  ],
                ),
              ],
              if (_isEditing) ...[
                const SizedBox(height: AppSpacing.md),
                AppDropdownField<UserStatus>(
                  label: 'Status',
                  value: _status,
                  items: UserStatus.values,
                  itemLabel: (s) => s.label,
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Text('Roles', style: theme.textTheme.labelLarge),
              rolesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, stackTrace) => Text(
                  'Could not load roles',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                data: (roles) => AppMultiSelectList<Role>(
                  items: roles,
                  selectedIds: _selectedRoleIds,
                  idOf: (r) => r.id,
                  labelOf: (r) => r.name,
                  subtitleOf: (r) => r.description,
                  onToggle: (role, selected) => setState(() {
                    if (selected) {
                      _selectedRoleIds.add(role.id);
                    } else {
                      _selectedRoleIds.remove(role.id);
                    }
                  }),
                ),
              ),
              if (warehousesAsync != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text('Warehouse access', style: theme.textTheme.labelLarge),
                Text(
                  'Users see and work in only the warehouses ticked here (roles with all-warehouse access see every one).',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                warehousesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (error, stackTrace) => Text(
                    'Could not load warehouses',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  data: (warehouses) => AppMultiSelectList<Warehouse>(
                    items: warehouses,
                    selectedIds: _selectedWarehouseIds,
                    idOf: (w) => w.id,
                    labelOf: (w) => w.name,
                    subtitleOf: (w) => w.isActive ? w.code : '${w.code} · inactive',
                    onToggle: (warehouse, selected) => setState(() {
                      if (selected) {
                        _selectedWarehouseIds.add(warehouse.id);
                      } else {
                        _selectedWarehouseIds.remove(warehouse.id);
                      }
                    }),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
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
