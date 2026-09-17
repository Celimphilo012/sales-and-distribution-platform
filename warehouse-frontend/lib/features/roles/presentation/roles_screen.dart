import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../data/roles_providers.dart';
import '../domain/role.dart';
import 'role_form_dialog.dart';

/// STEP 6f — ROLES, the core RBAC screen: a role is a bag of permission
/// keys (§F). List + create/edit-name here; the permission checklist itself
/// lives on the role detail route (too much surface for a dialog). Intended
/// as a clean, reusable template — the ordering app's own RBAC will need a
/// near-identical screen against its own (structurally identical) backend.
class RolesScreen extends ConsumerWidget {
  const RolesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      padding: const EdgeInsets.all(AppSpacing.lg),
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
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: rolesAsync.when(
              loading: () => const LoadingStateView(message: 'Loading roles…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load roles.',
                onRetry: () => ref.invalidate(rolesListProvider),
              ),
              data: (roles) => AppDataTable<Role>(
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
