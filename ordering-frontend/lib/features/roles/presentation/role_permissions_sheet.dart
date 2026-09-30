import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../users/data/users_providers.dart';
import '../data/roles_providers.dart';
import '../domain/permission.dart';
import '../domain/role.dart';

/// A role's permissions (the prototype's role sheet): every key in the
/// catalogue grouped by module, ticked when granted; save or discard.
Future<void> showRolePermissionsSheet(BuildContext context, String roleId) =>
    showNxSheet<void>(context, kicker: 'Role permissions', builder: (_) => _PermSheet(roleId: roleId));

class _PermSheet extends ConsumerStatefulWidget {
  const _PermSheet({required this.roleId});

  final String roleId;

  @override
  ConsumerState<_PermSheet> createState() => _PermSheetState();
}

class _PermSheetState extends ConsumerState<_PermSheet> {
  Set<String>? _draft;
  bool _saving = false;
  String? _error;

  Future<void> _save(Role role) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(rolesApiProvider).assignPermissions(role.id, permissionIds: _draft!.toList());
      ref.invalidate(roleDetailProvider(role.id));
      invalidateRoles(ref);
      NxToast.ok('Permissions saved', '${role.name} · ${_draft!.length} permissions');
      setState(() => _draft = null);
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _group(Permission p) {
    final m = p.module;
    if (m != null && m.isNotEmpty) return m;
    final i = p.key.indexOf('.');
    return i < 0 ? p.key : p.key.substring(0, i);
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final roleAsync = ref.watch(roleDetailProvider(widget.roleId));
    final catalog = ref.watch(permissionsCatalogProvider).value ?? const <Permission>[];
    final users = ref.watch(usersListProvider).value;

    return roleAsync.when(
      loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(e is AppError ? e.message : 'Could not load this role.', style: TextStyle(color: n.bad)),
      ),
      data: (role) {
        final saved = {for (final p in role.permissions) p.id};
        final draft = _draft ?? saved;
        final clean = draft.length == saved.length && draft.containsAll(saved);
        final holders = users?.where((u) => u.roles.any((r) => r.id == role.id)).length;
        final groups = <String, List<Permission>>{};
        for (final p in catalog) {
          groups.putIfAbsent(_group(p), () => []).add(p);
        }
        final names = groups.keys.toList()..sort();
        for (final g in groups.values) {
          g.sort((a, b) => a.key.compareTo(b.key));
        }
        return NxSheetBody(
          children: [
            Row(
              children: [
                Flexible(child: Text(role.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: n.text))),
                if (role.isSystem) ...[const SizedBox(width: 8), const NxTag('System', small: true)],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if ((role.description ?? '').isNotEmpty) role.description!,
                '${draft.length} of ${catalog.length} permissions',
                if (holders != null) '$holders user${holders == 1 ? '' : 's'}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: n.n400),
            ),
            const SizedBox(height: 14),
            for (final g in names) ...[
              NxKicker(g.toUpperCase(), color: n.n500),
              const SizedBox(height: 4),
              for (final p in groups[g]!)
                () {
                  final on = draft.contains(p.id);
                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => setState(() => _draft = on ? ({...draft}..remove(p.id)) : {...draft, p.id}),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(on ? PhosphorIconsFill.checkSquare : PhosphorIconsRegular.square, size: 17, color: on ? n.accent : n.n600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.key, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: on ? n.text : n.n400)),
                                if ((p.description ?? '').isNotEmpty) Text(p.description!, style: TextStyle(fontSize: 11, color: n.n500)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[Text(_error!, style: TextStyle(fontSize: 12, color: n.bad)), const SizedBox(height: 8)],
            Row(
              children: [
                NxButton.primary(label: _saving ? 'Saving…' : 'Save permissions', onPressed: clean || _saving ? null : () => _save(role)),
                const SizedBox(width: 8),
                NxButton.ghost(label: 'Discard', color: n.n400, onPressed: clean ? null : () => setState(() => _draft = null)),
              ],
            ),
          ],
        );
      },
    );
  }
}
