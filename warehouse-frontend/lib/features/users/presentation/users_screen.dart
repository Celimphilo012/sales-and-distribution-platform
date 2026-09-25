import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/compact_row_list.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/simple_grid_view.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../shared/widgets/view_mode_toggle.dart';
import '../data/users_providers.dart';
import '../domain/user.dart';
import 'user_form_dialog.dart';

enum _StatusFilter { all, active, inactive, suspended }

extension on _StatusFilter {
  String get label => switch (this) {
    _StatusFilter.all => 'All statuses',
    _StatusFilter.active => 'Active',
    _StatusFilter.inactive => 'Inactive',
    _StatusFilter.suspended => 'Suspended',
  };

  bool matches(UserStatus status) => switch (this) {
    _StatusFilter.all => true,
    _StatusFilter.active => status == UserStatus.active,
    _StatusFilter.inactive => status == UserStatus.inactive,
    _StatusFilter.suspended => status == UserStatus.suspended,
  };
}

/// STEP 6f — USERS. `GET /users` takes no query params (`UsersController.
/// findAll`), so search/status filtering happens client-side over the one
/// fetched list — fine at this scale, and the exact same pattern the
/// ordering app's own user-management screen can reuse verbatim once
/// re-pointed at its own (structurally identical) `/users` API.
class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});

  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  final _searchController = TextEditingController();
  String _search = '';
  _StatusFilter _statusFilter = _StatusFilter.all;
  ViewMode _view = ViewMode.table;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _deactivate(WarehouseUser user) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Deactivate ${user.fullName}?',
      message: 'They will no longer be able to sign in. This does not delete their history.',
      confirmLabel: 'Deactivate',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(usersApiProvider).deactivate(user.id);
      ref.invalidate(usersListProvider);
    } on AppError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('users.manage') ?? false));
    if (!canManage) {
      return const EmptyStateView(
        title: "You don't have permission to manage users",
        message: 'Ask an administrator for the users.manage permission.',
        icon: Icons.lock_outline,
      );
    }

    final usersAsync = ref.watch(usersListProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Users', style: theme.textTheme.headlineSmall)),
              FilledButton.icon(
                onPressed: () => showUserFormDialog(context),
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('New user'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          usersAsync.maybeWhen(
            data: (users) => _UsersStats(users: users),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      child: AppTextField(
                        label: 'Search',
                        controller: _searchController,
                        hintText: 'Name or email',
                        prefixIcon: Icons.search,
                        onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: AppDropdownField<_StatusFilter>(
                        label: 'Status',
                        value: _statusFilter,
                        items: _StatusFilter.values,
                        itemLabel: (f) => f.label,
                        onChanged: (value) {
                          if (value != null) setState(() => _statusFilter = value);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ViewModeToggle(value: _view, onChanged: (mode) => setState(() => _view = mode)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: usersAsync.when(
              loading: () => const LoadingStateView(message: 'Loading users…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load users.',
                onRetry: () => ref.invalidate(usersListProvider),
              ),
              data: (users) {
                final filtered = users.where((u) {
                  if (!_statusFilter.matches(u.status)) return false;
                  if (_search.isEmpty) return true;
                  return u.fullName.toLowerCase().contains(_search) || u.email.toLowerCase().contains(_search);
                }).toList();

                return switch (_view) {
                  ViewMode.table => _UsersTable(
                      users: filtered,
                      onEdit: (u) => showUserFormDialog(context, user: u),
                      onDeactivate: _deactivate,
                    ),
                  ViewMode.list => CompactRowList<WarehouseUser>(
                      items: filtered,
                      onTap: (u) => showUserFormDialog(context, user: u),
                      emptyTitle: 'No users found',
                      emptyMessage: 'Try adjusting your search or filters.',
                      rowBuilder: (context, u) => Row(
                        children: [
                          Expanded(flex: 2, child: Text(u.fullName, style: theme.textTheme.bodyMedium)),
                          Expanded(
                            flex: 2,
                            child: Text(
                              u.email,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              u.roles.isEmpty ? '—' : u.roles.map((r) => r.name).join(', '),
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          StatusBadge(
                            label: u.status.label,
                            tone: switch (u.status) {
                              UserStatus.active => StatusTone.success,
                              UserStatus.inactive => StatusTone.neutral,
                              UserStatus.suspended => StatusTone.danger,
                            },
                          ),
                        ],
                      ),
                    ),
                  ViewMode.grid => SimpleGridView<WarehouseUser>(
                      items: filtered,
                      onTap: (u) => showUserFormDialog(context, user: u),
                      emptyTitle: 'No users found',
                      emptyMessage: 'Try adjusting your search or filters.',
                      maxCrossAxisExtent: 220,
                      childAspectRatio: 1.4,
                      contentBuilder: (context, u) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                child: Text(
                                  u.fullName.isEmpty ? '?' : u.fullName[0].toUpperCase(),
                                  style: theme.textTheme.labelMedium,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                child: Text(
                                  u.fullName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            u.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            u.roles.isEmpty ? '—' : u.roles.map((r) => r.name).join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          StatusBadge(
                            label: u.status.label,
                            tone: switch (u.status) {
                              UserStatus.active => StatusTone.success,
                              UserStatus.inactive => StatusTone.neutral,
                              UserStatus.suspended => StatusTone.danger,
                            },
                          ),
                        ],
                      ),
                    ),
                };
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _UsersStats extends StatelessWidget {
  const _UsersStats({required this.users});

  final List<WarehouseUser> users;

  @override
  Widget build(BuildContext context) {
    final active = users.where((u) => u.status == UserStatus.active).length;
    final suspended = users.where((u) => u.status == UserStatus.suspended).length;
    final inactive = users.length - active - suspended;

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        StatTile(label: 'users', value: '${users.length}', icon: Icons.people_outline),
        StatTile(label: 'active', value: '$active', tone: StatusTone.success, icon: Icons.check_circle_outline),
        if (suspended > 0)
          StatTile(label: 'suspended', value: '$suspended', tone: StatusTone.danger, icon: Icons.pause_circle_outline),
        if (inactive > 0)
          StatTile(label: 'inactive', value: '$inactive', tone: StatusTone.neutral, icon: Icons.block_outlined),
      ],
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({required this.users, required this.onEdit, required this.onDeactivate});

  final List<WarehouseUser> users;
  final void Function(WarehouseUser) onEdit;
  final void Function(WarehouseUser) onDeactivate;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<WarehouseUser>(
      rows: users,
      emptyTitle: 'No users found',
      emptyMessage: 'Try adjusting your search or filters.',
      columns: [
        AppDataColumn(label: 'Name', cellBuilder: (u) => Text(u.fullName)),
        AppDataColumn(label: 'Email', cellBuilder: (u) => Text(u.email)),
        AppDataColumn(
          label: 'Roles',
          cellBuilder: (u) => Text(u.roles.isEmpty ? '—' : u.roles.map((r) => r.name).join(', ')),
        ),
        AppDataColumn(
          label: 'Status',
          cellBuilder: (u) => StatusBadge(
            label: u.status.label,
            tone: switch (u.status) {
              UserStatus.active => StatusTone.success,
              UserStatus.inactive => StatusTone.neutral,
              UserStatus.suspended => StatusTone.danger,
            },
          ),
        ),
        AppDataColumn(
          label: '',
          cellBuilder: (u) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 18,
                tooltip: 'Edit',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit(u),
              ),
              if (u.status == UserStatus.active)
                IconButton(
                  iconSize: 18,
                  tooltip: 'Deactivate',
                  icon: const Icon(Icons.block),
                  onPressed: () => onDeactivate(u),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
