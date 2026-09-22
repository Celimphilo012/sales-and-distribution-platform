import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/app_user.dart';
import '../core/auth/auth_provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/theme/app_spacing.dart';
import '../routing/nav_items.dart';
import '../routing/route_paths.dart';
import 'nav_panel.dart';
import 'nav_rail.dart';
import 'shell_top_bar.dart';

/// The permission-filtered, responsive shell every routed screen renders
/// inside of, driven by the grouped [kNavGroups] table:
///
///  * desktop  — dark top bar + a fixed sidebar of collapsible groups;
///  * tablet   — top bar + a rail with one entry per group (menu beside the
///               rail for multi-item groups) + the full drawer on demand;
///  * phone    — top bar + bottom shortcuts + the full grouped drawer.
class ResponsiveAppShell extends ConsumerWidget {
  const ResponsiveAppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value?.user;
    final groups = visibleNavGroups(user);

    Widget frame(_ShellMode mode) => _ShellFrame(
          mode: mode,
          groups: groups,
          user: user,
          currentPath: currentPath,
          child: child,
        );

    return ResponsiveLayout(
      mobile: (_) => frame(_ShellMode.phone),
      tablet: (_) => frame(_ShellMode.tablet),
      desktop: (_) => frame(_ShellMode.desktop),
    );
  }
}

enum _ShellMode { phone, tablet, desktop }

class _ShellFrame extends StatefulWidget {
  const _ShellFrame({
    required this.mode,
    required this.groups,
    required this.user,
    required this.currentPath,
    required this.child,
  });

  final _ShellMode mode;
  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;
  final Widget child;

  @override
  State<_ShellFrame> createState() => _ShellFrameState();
}

class _ShellFrameState extends State<_ShellFrame> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  List<String> get _crumbs {
    final item = navItemMatching(widget.groups.expand((g) => g.items), widget.currentPath);
    if (item == null) return const [];
    final group = navGroupOf(widget.groups, item);
    return [if (group != null && !group.flat) group.title, item.label];
  }

  @override
  Widget build(BuildContext context) {
    final mode = widget.mode;
    final scheme = Theme.of(context).colorScheme;
    final desktop = mode == _ShellMode.desktop;

    return Scaffold(
      key: _scaffoldKey,
      drawer: desktop
          ? null
          : _NavDrawer(groups: widget.groups, user: widget.user, currentPath: widget.currentPath),
      body: Column(
        children: [
          ShellTopBar(
            crumbs: _crumbs,
            compact: mode == _ShellMode.phone,
            onMenu: desktop ? null : () => _scaffoldKey.currentState?.openDrawer(),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop) _Sidebar(groups: widget.groups, user: widget.user, currentPath: widget.currentPath),
                if (mode == _ShellMode.tablet) GroupedNavRail(groups: widget.groups, activePath: widget.currentPath),
                Expanded(child: ColoredBox(color: scheme.surface, child: widget.child)),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: mode == _ShellMode.phone
          ? _BottomBar(
              groups: widget.groups,
              currentPath: widget.currentPath,
              onMenu: () => _scaffoldKey.currentState?.openDrawer(),
            )
          : null,
    );
  }
}

/// The user's roles as one line ("Warehouse Manager, Admin"), or null.
String? _roleLine(AppUser? user) {
  if (user == null || user.roles.isEmpty) return null;
  return user.roles.map((r) => r.name).join(', ');
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.groups, required this.user, required this.currentPath});

  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;

  static const double width = 248;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          _SignedInBlock(user: user),
          Expanded(child: NavPanel(groups: groups, activePath: currentPath)),
          const _SignOutButton(),
        ],
      ),
    );
  }
}

/// "SIGNED IN AS / name / role" — the sidebar's masthead, after the
/// prototype.
class _SignedInBlock extends StatelessWidget {
  const _SignedInBlock({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final role = _roleLine(user);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm + 2),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outlineVariant))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SIGNED IN AS',
            style: textTheme.labelSmall?.copyWith(letterSpacing: 1.6, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Text(
            user?.name ?? '—',
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (role != null)
            Text(
              role,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scheme.primary),
            ),
        ],
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: OutlinedButton.icon(
        onPressed: () => ref.read(authProvider.notifier).logout(),
        icon: PhosphorIcon(PhosphorIconsDuotone.signOut, size: 18, color: scheme.onSurfaceVariant),
        label: Text('Sign out', style: TextStyle(color: scheme.onSurfaceVariant)),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
      ),
    );
  }
}

/// The full grouped navigation as a slide-in drawer (tablet + phone).
class _NavDrawer extends StatelessWidget {
  const _NavDrawer({required this.groups, required this.user, required this.currentPath});

  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final role = _roleLine(user);

    return Drawer(
      width: 288,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              MediaQuery.paddingOf(context).top + AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: scheme.inverseSurface,
              border: Border(bottom: BorderSide(color: scheme.primary, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Warehouse System',
                  style: textTheme.titleMedium?.copyWith(color: scheme.onInverseSurface, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  [if (user != null) user!.name, ?role].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onInverseSurface.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          Expanded(
            child: NavPanel(
              groups: groups,
              activePath: currentPath,
              onNavigate: () => Navigator.of(context).maybePop(),
            ),
          ),
          const _SignOutButton(),
        ],
      ),
    );
  }
}

/// Phone bottom bar: up to four frequent destinations (only those the user
/// may see) plus a Menu button that opens the full grouped drawer.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.groups, required this.currentPath, required this.onMenu});

  final List<NavGroup> groups;
  final String currentPath;
  final VoidCallback onMenu;

  static const _shortcuts = <(String path, String label)>[
    (RoutePaths.dashboard, 'Home'),
    (RoutePaths.products, 'Products'),
    (RoutePaths.inventory, 'Inventory'),
    (RoutePaths.receiving, 'Receive'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = groups.expand((g) => g.items).toList();
    final activePath = navItemMatching(all, currentPath)?.path;

    final entries = <Widget>[
      for (final (path, label) in _shortcuts)
        for (final item in all.where((i) => i.path == path))
          _BottomEntry(
            icon: item.icon,
            label: label,
            selected: activePath == path,
            onTap: () => context.go(path),
          ),
      _BottomEntry(
        icon: PhosphorIconsDuotone.list,
        label: 'Menu',
        selected: activePath != null && !_shortcuts.any((s) => s.$1 == activePath),
        onTap: onMenu,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(top: false, child: Row(children: [for (final e in entries) Expanded(child: e)])),
    );
  }
}

class _BottomEntry extends StatelessWidget {
  const _BottomEntry({required this.icon, required this.label, required this.selected, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(2, 7, 2, 7),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(width: 3, color: selected ? scheme.primary : Colors.transparent)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhosphorIcon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
