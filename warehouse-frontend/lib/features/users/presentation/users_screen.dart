import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../roles/data/roles_providers.dart';
import '../../roles/domain/role.dart';
import '../../warehouses/data/warehouses_providers.dart';
import '../../warehouses/domain/warehouse.dart';
import '../data/users_providers.dart';
import '../domain/user.dart';
import 'user_form_dialog.dart';

/// Users (prototype `users`) — people who sign in to the warehouse system.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final me = ref.watch(authProvider).value?.user;
    final async = ref.watch(usersListProvider);
    final roles = ref.watch(rolesListProvider).value ?? const <Role>[];
    final warehouses = ref.watch(warehousesProvider(true)).value ?? const <Warehouse>[];

    Future<void> setStatus(WarehouseUser u, bool activate) async {
      if (!activate) {
        final ok = await showNxConfirm(
          context,
          title: 'Deactivate ${u.fullName}?',
          body: 'They will no longer be able to sign in. This does not delete their history.',
          confirmLabel: 'Deactivate',
          danger: true,
        );
        if (!ok) return;
      }
      try {
        final api = ref.read(usersApiProvider);
        activate ? await api.update(u.id, status: UserStatus.active) : await api.deactivate(u.id);
        ref.invalidate(usersListProvider);
        NxToast.ok('${u.fullName} ${activate ? 'reactivated' : 'deactivated'}', activate ? 'They can sign in again.' : 'Signed out everywhere.');
      } on AppError catch (e) {
        NxToast.error('Not changed', e.message);
      }
    }

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(usersListProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading users…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load users.',
          onRetry: () => ref.invalidate(usersListProvider),
        ),
        data: (users) {
          NxTag status(WarehouseUser u) => NxTag(u.status.label, tone: switch (u.status) {
            UserStatus.active => Tone.ok,
            UserStatus.suspended => Tone.bad,
            UserStatus.inactive => Tone.neutral,
          });
          String mfa(WarehouseUser u) => kMfaMethodLabels[u.mfaMethod] ?? u.mfaMethod;
          String whs(WarehouseUser u) => u.warehouses.isEmpty ? '—' : u.warehouses.map((w) => w.code).join(', ');
          String roleNames(WarehouseUser u) => u.roles.isEmpty ? '—' : u.roles.map((r) => r.name).join(', ');
          List<NxRowAction> acts(WarehouseUser u) => [
            NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showUserFormDialog(context, user: u)),
            NxRowAction(icon: PhosphorIconsRegular.key, label: 'Reset password', onPressed: () => showResetPasswordDialog(context, u)),
            if (u.id != me?.id)
              u.status == UserStatus.active
                  ? NxRowAction(icon: PhosphorIconsRegular.prohibit, label: 'Deactivate', danger: true, onPressed: () => setStatus(u, false))
                  : NxRowAction(icon: PhosphorIconsRegular.arrowCounterClockwise, label: 'Reactivate', onPressed: () => setStatus(u, true)),
          ];

          return NxListPage<WarehouseUser>(
            stateKey: 'users',
            title: 'Users',
            sub: 'People who sign in to this warehouse system.',
            actions: [NxButton.primary(label: 'New user', icon: PhosphorIconsRegular.userPlus, onPressed: () => showUserFormDialog(context))],
            rows: users,
            search: (u) => '${u.fullName} ${u.email}',
            searchPlaceholder: 'Name or email',
            stats: (rs) {
              final suspended = rs.where((u) => u.status == UserStatus.suspended).length;
              return [
                NxStat('Users', fmtNum(rs.length)),
                NxStat('Active', fmtNum(rs.where((u) => u.status == UserStatus.active).length), color: n.ok),
                NxStat('Suspended', fmtNum(suspended), color: suspended > 0 ? n.bad : null),
                NxStat('Authenticator app', fmtNum(rs.where((u) => u.mfaMethod == 'TOTP').length), sub: 'stronger sign-in check'),
                NxStat('Multi-warehouse', fmtNum(rs.where((u) => u.warehouses.length > 1).length)),
              ];
            },
            quick: NxQuick(
              get: (u) => u.status.apiValue,
              options: const [('', 'All'), ('ACTIVE', 'Active'), ('SUSPENDED', 'Suspended'), ('INACTIVE', 'Inactive')],
            ),
            filters: [
              NxSelectFilter('role', 'Role', options: [for (final r in roles) (r.id, r.name)], get: (u) => u.roles.map((r) => r.id)),
              NxSelectFilter('wh', 'Warehouse', options: [for (final w in warehouses) (w.id, w.name)], get: (u) => u.warehouses.map((w) => w.id)),
              NxSelectFilter('mfa', 'Sign-in check', options: [for (final e in kMfaMethodLabels.entries) (e.key, e.value)], get: (u) => u.mfaMethod),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(
                key: 'name',
                label: 'User',
                sort: (u) => u.fullName.toLowerCase(),
                cell: (u) => Row(
                  children: [
                    NxAvatar(name: u.fullName),
                    const SizedBox(width: 9),
                    Expanded(child: NxCellText(u.fullName, weight: FontWeight.w500, sub: u.email)),
                  ],
                ),
              ),
              NxColumn(
                key: 'roles',
                label: 'Roles',
                hide: NxHide.md,
                cell: (u) => Wrap(spacing: 4, runSpacing: 4, children: [for (final r in u.roles) NxTag(r.name, small: true, tone: Tone.accent)]),
              ),
              NxColumn(key: 'whs', label: 'Warehouses', hide: NxHide.wide, cell: (u) => NxCellText(whs(u), mono: true, color: n.n300)),
              NxColumn(key: 'mfa', label: 'Sign-in check', hide: NxHide.wide, cell: (u) => NxCellText(mfa(u), color: n.n300)),
              NxColumn(key: 'status', label: 'Status', sort: (u) => u.status.index, cell: (u) => Align(alignment: Alignment.centerLeft, child: status(u))),
              NxColumn(key: 'act', label: '', width: 106, cell: (u) => NxRowActions(acts(u))),
            ],
            listRow: (u) => NxListRowSpec(
              icon: PhosphorIconsDuotone.user,
              leading: NxAvatar(name: u.fullName, size: 32),
              title: u.fullName,
              sub: '${u.email} · ${roleNames(u)}',
              right: whs(u),
              rightSub: mfa(u),
              tag: status(u),
            ),
            card: (u) => NxCardSpec(
              icon: PhosphorIconsDuotone.userCircle,
              title: u.fullName,
              sub: u.email,
              metrics: [('Roles', roleNames(u), null), ('Warehouses', whs(u), null)],
              tag: status(u),
            ),
            onOpen: (u) => showUserFormDialog(context, user: u),
            emptyTitle: 'No users match',
          );
        },
      ),
    );
  }
}
