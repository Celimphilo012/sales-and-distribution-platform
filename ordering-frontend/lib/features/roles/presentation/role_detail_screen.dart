import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_multi_select_list.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/roles_providers.dart';
import '../domain/permission.dart';
import '../domain/role.dart';
import 'role_form_dialog.dart';

/// A role's permission checklist — the core RBAC editor. Loads the full
/// permission catalog (`GET /permissions`) grouped by module, checks off
/// whichever ones this role currently holds, and on Save sends the FULL set
/// via `PUT /roles/:id/permissions` (a replace, not a diff — matches the
/// real `AssignPermissionsDto`). Changing this immediately changes what every
/// user holding this role can do (§F) — there's nothing else to propagate.
class RoleDetailScreen extends ConsumerWidget {
  const RoleDetailScreen({super.key, required this.roleId});

  final String roleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('roles.manage') ?? false));
    if (!canManage) {
      return const EmptyStateView(
        title: "You don't have permission to manage roles",
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final roleAsync = ref.watch(roleDetailProvider(roleId));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => context.go(RoutePaths.roles),
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Roles',
              ),
              Text('Role', style: theme.textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: roleAsync.when(
              loading: () => const LoadingStateView(message: 'Loading role…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load this role.',
                onRetry: () => ref.invalidate(roleDetailProvider(roleId)),
              ),
              data: (role) => _RoleDetailBody(role: role),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleDetailBody extends ConsumerStatefulWidget {
  const _RoleDetailBody({required this.role});

  final Role role;

  @override
  ConsumerState<_RoleDetailBody> createState() => _RoleDetailBodyState();
}

class _RoleDetailBodyState extends ConsumerState<_RoleDetailBody> {
  late Set<String> _selectedPermissionIds;
  bool _saving = false;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _selectedPermissionIds = widget.role.permissions.map((p) => p.id).toSet();
  }

  @override
  void didUpdateWidget(covariant _RoleDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.role.id != widget.role.id) {
      _selectedPermissionIds = widget.role.permissions.map((p) => p.id).toSet();
    }
  }

  Future<void> _savePermissions() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(rolesApiProvider)
          .assignPermissions(widget.role.id, permissionIds: _selectedPermissionIds.toList());
      ref.invalidate(roleDetailProvider(widget.role.id));
      invalidateRoles(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Permissions saved for ${widget.role.name}')));
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final blockedReason = widget.role.isSystem
        ? 'This is a system role and cannot be deleted.'
        : null;
    if (blockedReason != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blockedReason)));
      return;
    }
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Delete role "${widget.role.name}"?',
      message: 'This permanently removes the role. It is blocked if any user still holds it.',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;

    setState(() => _deleting = true);
    try {
      await ref.read(rolesApiProvider).remove(widget.role.id);
      invalidateRoles(ref);
      if (mounted) context.go(RoutePaths.roles);
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissionsAsync = ref.watch(permissionsCatalogProvider);
    final dirty = !_setEquals(_selectedPermissionIds, widget.role.permissions.map((p) => p.id).toSet());

    return ListView(
      children: [
        AppCard(
          title: widget.role.name,
          subtitle: widget.role.description,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.role.isSystem) const StatusBadge(label: 'System', tone: StatusTone.info),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Edit name/description',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => showRoleFormDialog(context, role: widget.role),
              ),
              IconButton(
                tooltip: 'Delete role',
                icon: _deleting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.delete_outline),
                onPressed: _deleting ? null : _delete,
              ),
            ],
          ),
          child: Text(
            '${widget.role.permissions.length} permission(s) currently assigned',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          title: 'Permissions',
          subtitle: 'A role is a bag of permission keys. Changing this changes what its users can do.',
          child: permissionsAsync.when(
            loading: () => const LoadingStateView(message: 'Loading permission catalog…'),
            error: (error, stackTrace) => Text(
              error is AppError ? error.message : 'Could not load the permission catalog.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            data: (permissions) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppMultiSelectList<Permission>(
                  items: permissions,
                  selectedIds: _selectedPermissionIds,
                  idOf: (p) => p.id,
                  labelOf: (p) => p.key,
                  subtitleOf: (p) => p.description,
                  groupOf: (p) => p.module,
                  onToggle: (permission, selected) => setState(() {
                    if (selected) {
                      _selectedPermissionIds.add(permission.id);
                    } else {
                      _selectedPermissionIds.remove(permission.id);
                    }
                  }),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: (_saving || !dirty) ? null : _savePermissions,
                      icon: _saving
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save permissions'),
                    ),
                    if (dirty) ...[
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'Unsaved changes',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
