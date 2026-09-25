import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/compact_row_list.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/simple_grid_view.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../data/roles_providers.dart';
import '../domain/role.dart';
import 'role_form_dialog.dart';

/// STEP 6f — ROLES, the core RBAC screen: a role is a bag of permission
/// keys (§F). List + create/edit-name here; the permission checklist itself
/// lives on the role detail route (too much surface for a dialog). Intended
/// as a clean, reusable template — the ordering app's own RBAC will need a
/// near-identical screen against its own (structurally identical) backend.
/// List/table/grid + stats + compact, matching the Products prototype.
class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key});

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  ViewMode _view = ViewMode.table;

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('roles.manage') ?? false));
    if (!canManage) {
      return const EmptyStateView(
        title: "You don't have permission to manage roles",
        message: 'Ask an administrator for the roles.manage permission.',
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final rolesAsync = ref.watch(rolesListProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Roles', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => showRoleFormDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('New role'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          rolesAsync.maybeWhen(data: (roles) => _RolesStats(roles: roles), orElse: () => const SizedBox.shrink()),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: ViewModeToggle(value: _view, onChanged: (mode) => setState(() => _view = mode)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: rolesAsync.when(
              loading: () => const LoadingStateView(message: 'Loading roles…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load roles.',
                onRetry: () => ref.invalidate(rolesListProvider),
              ),
              data: (roles) => switch (_view) {
                ViewMode.table => _RolesTable(roles: roles),
                ViewMode.list => CompactRowList<Role>(
                    items: roles,
                    onTap: (r) => context.go(RoutePaths.roleDetail(r.id)),
                    emptyTitle: 'No roles yet',
                    rowBuilder: (context, r) => Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(child: Text(r.name, overflow: TextOverflow.ellipsis)),
                              if (r.isSystem) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const StatusBadge(label: 'System', tone: StatusTone.info),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            r.description ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        SizedBox(
                          width: 90,
                          child: Text('${r.permissions.length} perms', textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ),
                ViewMode.grid => SimpleGridView<Role>(
                    items: roles,
                    onTap: (r) => context.go(RoutePaths.roleDetail(r.id)),
                    emptyTitle: 'No roles yet',
                    maxCrossAxisExtent: 220,
                    childAspectRatio: 1.3,
                    contentBuilder: (context, r) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.shield_outlined, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              child: Text(
                                r.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          r.description ?? 'No description',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Text('${r.permissions.length} permissions', style: theme.textTheme.bodySmall),
                            if (r.isSystem) ...[
                              const SizedBox(width: AppSpacing.xs),
                              const StatusBadge(label: 'System', tone: StatusTone.info),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RolesStats extends StatelessWidget {
  const _RolesStats({required this.roles});

  final List<Role> roles;

  @override
  Widget build(BuildContext context) {
    final system = roles.where((r) => r.isSystem).length;
    final custom = roles.length - system;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'roles', value: '${roles.length}', icon: Icons.shield_outlined),
        StatTile(label: 'system', value: '$system', tone: StatusTone.info, icon: Icons.verified_outlined),
        if (custom > 0) StatTile(label: 'custom', value: '$custom', icon: Icons.edit_outlined),
      ],
    );
  }
}

class _RolesTable extends StatelessWidget {
  const _RolesTable({required this.roles});

  final List<Role> roles;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<Role>(
      rows: roles,
      emptyTitle: 'No roles yet',
      onRowTap: (role) => context.go(RoutePaths.roleDetail(role.id)),
      columns: [
        AppDataColumn(
          label: 'Name',
          cellBuilder: (r) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.name),
              if (r.isSystem) ...[
                const SizedBox(width: AppSpacing.sm),
                const StatusBadge(label: 'System', tone: StatusTone.info),
              ],
            ],
          ),
        ),
        AppDataColumn(label: 'Description', cellBuilder: (r) => Text(r.description ?? '—')),
        AppDataColumn(
          label: 'Permissions',
          numeric: true,
          cellBuilder: (r) => Text('${r.permissions.length}'),
        ),
      ],
    );
  }
}
