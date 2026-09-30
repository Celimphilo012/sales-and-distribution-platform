import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../users/data/users_providers.dart';
import '../../users/domain/user.dart';
import '../data/roles_providers.dart';
import '../domain/permission.dart';
import '../domain/role.dart';
import 'role_form_dialog.dart';
import 'role_permissions_sheet.dart';

class _Row {
  _Row(this.r, this.users);

  final Role r;

  /// Null when the viewer can't list users.
  final int? users;
  int get n => r.permissions.length;
}

/// Roles (prototype `roles`) — a role is a set of permission keys.
/// `/roles?open=<id>` opens that role's permission sheet.
class RolesScreen extends ConsumerStatefulWidget {
  const RolesScreen({super.key, this.openRoleId});

  final String? openRoleId;

  @override
  ConsumerState<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends ConsumerState<RolesScreen> {
  @override
  void initState() {
    super.initState();
    final id = widget.openRoleId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        GoRouter.of(context).go(RoutePaths.roles);
        showRolePermissionsSheet(context, id);
      });
    }
  }

  Future<void> _delete(Role r) async {
    final ok = await showNxConfirm(
      context,
      title: 'Delete role "${r.name}"?',
      body: 'Nobody holds this role. This cannot be undone.',
      confirmLabel: 'Delete',
      danger: true,
    );
    if (!ok) return;
    try {
      await ref.read(rolesApiProvider).remove(r.id);
      invalidateRoles(ref);
      NxToast.ok('Role deleted', r.name);
    } on AppError catch (e) {
      NxToast.error('Not deleted', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final async = ref.watch(rolesListProvider);
    final catalog = ref.watch(permissionsCatalogProvider).value ?? const <Permission>[];
    final users = ref.watch(usersListProvider).value;
    final total = catalog.isEmpty ? 1 : catalog.length;

    return NxPageScroll(
      onRefresh: () async => invalidateRoles(ref),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading roles…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load roles.',
          onRetry: () => invalidateRoles(ref),
        ),
        data: (roles) {
          int? holders(Role r) => users?.where((u) => u.status != UserStatus.inactive && u.roles.any((x) => x.id == r.id)).length;
          final rows = [for (final r in roles) _Row(r, holders(r))];
          NxTag kind(_Row r) => NxTag(r.r.isSystem ? 'System' : 'Custom', tone: r.r.isSystem ? Tone.info : Tone.neutral);
          List<NxRowAction> acts(_Row r) => [
            NxRowAction(icon: PhosphorIconsRegular.shieldCheck, label: 'Permissions', onPressed: () => showRolePermissionsSheet(context, r.r.id)),
            NxRowAction(icon: PhosphorIconsRegular.pencilSimple, label: 'Edit', onPressed: () => showRoleFormDialog(context, role: r.r)),
            if (!r.r.isSystem && (r.users ?? 1) == 0)
              NxRowAction(icon: PhosphorIconsRegular.trash, label: 'Delete', danger: true, onPressed: () => _delete(r.r)),
          ];
          final keys = [for (final p in catalog) p.key]..sort();

          return NxListPage<_Row>(
            stateKey: 'roles',
            title: 'Roles',
            sub: 'A role is a set of permission keys from the ordering system’s catalogue.',
            actions: [NxButton.primary(label: 'New role', icon: PhosphorIconsRegular.plus, onPressed: () => showRoleFormDialog(context))],
            rows: rows,
            search: (r) => '${r.r.name} ${r.r.description ?? ''}',
            searchPlaceholder: 'Role name',
            stats: (rs) => [
              NxStat('Roles', fmtNum(rs.length)),
              NxStat('System', fmtNum(rs.where((r) => r.r.isSystem).length), color: n.a300),
              NxStat('Custom', fmtNum(rs.where((r) => !r.r.isSystem).length)),
              NxStat('Permission keys', fmtNum(catalog.length)),
              NxStat('Unassigned', users == null ? '—' : fmtNum(rs.where((r) => r.users == 0).length), sub: 'roles with no users'),
            ],
            quick: NxQuick(get: (r) => r.r.isSystem ? 'sys' : 'cus', options: const [('', 'All'), ('sys', 'System'), ('cus', 'Custom')]),
            filters: [
              NxSelectFilter('perm', 'Grants permission', searchable: true, options: [for (final k in keys) (k, k)], get: (r) => r.r.permissions.map((p) => p.key)),
              NxRangeFilter('n', 'Permissions', get: (r) => r.n),
              NxRangeFilter('users', 'Users', get: (r) => r.users),
            ],
            defaultSort: ('name', 1),
            columns: [
              NxColumn(
                key: 'name',
                label: 'Role',
                sort: (r) => r.r.name.toLowerCase(),
                cell: (r) => NxCellText(r.r.name, weight: FontWeight.w500, sub: r.r.isSystem ? 'System role' : 'Custom role'),
              ),
              NxColumn(key: 'desc', label: 'Description', hide: NxHide.md, cell: (r) => NxCellText(r.r.description ?? '—', color: n.n400)),
              NxColumn(
                key: 'n',
                label: 'Permissions',
                width: 160,
                sort: (r) => r.n,
                cell: (r) => NxLabeledBar(label: '${r.n}/${catalog.length}', fraction: r.n / total),
              ),
              NxColumn(
                key: 'users',
                label: 'Users',
                align: TextAlign.right,
                sort: (r) => r.users,
                cell: (r) => NxCellText(r.users == null ? '—' : fmtNum(r.users), align: TextAlign.right),
              ),
              NxColumn(key: 'act', label: '', width: 106, cell: (r) => NxRowActions(acts(r))),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.shield,
              iconColor: n.a400,
              title: r.r.name,
              sub: r.r.description,
              right: '${r.n} perms',
              rightSub: r.users == null ? null : '${r.users} users',
              tag: r.r.isSystem ? kind(r) : null,
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.shield,
              title: r.r.name,
              sub: r.r.description,
              metrics: [('Permissions', '${r.n}/${catalog.length}', null), ('Users', r.users == null ? '—' : fmtNum(r.users), null)],
              tag: kind(r),
              bar: r.n / total,
              barColor: n.a500,
            ),
            onOpen: (r) => showRolePermissionsSheet(context, r.r.id),
            emptyTitle: 'No roles match',
          );
        },
      ),
    );
  }
}
