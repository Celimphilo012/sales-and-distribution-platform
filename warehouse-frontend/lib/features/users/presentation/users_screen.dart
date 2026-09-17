import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_dropdown_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
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
      padding: const EdgeInsets.all(AppSpacing.lg),
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
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 280,
                child: AppTextField(
                  label: 'Search',
                  controller: _searchController,
                  hintText: 'Name or email',
                  prefixIcon: Icons.search,
                  onChanged: (value) => setState(() => _search = value.trim().toLowerCase()),
                ),
              ),
              SizedBox(
                width: 200,
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
          const SizedBox(height: AppSpacing.lg),
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

                return AppDataTable<WarehouseUser>(
                  rows: filtered,
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
                            onPressed: () => showUserFormDialog(context, user: u),
                          ),
                          if (u.status == UserStatus.active)
                            IconButton(
                              iconSize: 18,
                              tooltip: 'Deactivate',
                              icon: const Icon(Icons.block),
                              onPressed: () => _deactivate(u),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
