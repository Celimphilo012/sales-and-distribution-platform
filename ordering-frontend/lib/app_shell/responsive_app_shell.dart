import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/app_user.dart';
import '../core/auth/auth_provider.dart';
import '../core/responsive/responsive_layout.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/theme_mode_provider.dart';
import '../routing/nav_items.dart';

/// The permission-filtered, responsive shell every routed screen renders
/// inside of: desktop gets a fixed sidebar, tablet a collapsible rail,
/// mobile a bottom nav — all wrapping the same [child] and driven by the
/// same [kNavItems] table.
class ResponsiveAppShell extends ConsumerWidget {
  const ResponsiveAppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value?.user;
    final items = visibleNavItems(user);
    final selectedIndex = navIndexForPath(items, currentPath);

    return ResponsiveLayout(
      mobile: (context) => _MobileShell(items: items, selectedIndex: selectedIndex, child: child),
      tablet: (context) => _TabletShell(items: items, selectedIndex: selectedIndex, child: child),
      desktop: (context) => _DesktopShell(items: items, selectedIndex: selectedIndex, child: child),
    );
  }
}

void _navigateTo(BuildContext context, List<NavItem> items, int index) {
  if (index < 0 || index >= items.length) return;
  context.go(items[index].path);
}

String _titleFor(List<NavItem> items, int selectedIndex) {
  if (selectedIndex < 0) return 'Ordering System';
  return items[selectedIndex].label;
}

class _TopBar extends ConsumerWidget implements PreferredSizeWidget {
  const _TopBar({required this.title, this.leading});

  final String title;
  final Widget? leading;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(authProvider).value?.user;

    return AppBar(
      leading: leading,
      title: Text(title),
      actions: [
        IconButton(
          tooltip: 'Toggle theme',
          onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          icon: Icon(themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
        ),
        const SizedBox(width: AppSpacing.xs),
        _UserMenu(user: user),
        const SizedBox(width: AppSpacing.sm),
      ],
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (user == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (value) {
        if (value == 'logout') {
          ref.read(authProvider.notifier).logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user!.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(user!.email, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'logout', child: Text('Sign out')),
      ],
      child: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          user!.name.isNotEmpty ? user!.name[0].toUpperCase() : '?',
          style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.items, required this.selectedIndex, required this.child});

  final List<NavItem> items;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 260,
            child: Material(
              color: theme.colorScheme.surfaceContainerLow,
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Row(
                      children: [
                        Icon(Icons.storefront_rounded, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Ordering System',
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final selected = index == selectedIndex;
                        return ListTile(
                          leading: Icon(selected ? item.selectedIcon : item.icon),
                          title: Text(item.label),
                          selected: selected,
                          selectedTileColor: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                          onTap: () => _navigateTo(context, items, index),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Scaffold(
              appBar: _TopBar(title: _titleFor(items, selectedIndex)),
              body: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabletShell extends StatelessWidget {
  const _TabletShell({required this.items, required this.selectedIndex, required this.child});

  final List<NavItem> items;
  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _TopBar(title: _titleFor(items, selectedIndex)),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: selectedIndex < 0 ? null : selectedIndex,
            onDestinationSelected: (index) => _navigateTo(context, items, index),
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final item in items)
                NavigationRailDestination(
                  icon: Icon(item.icon),
                  selectedIcon: Icon(item.selectedIcon),
                  label: Text(item.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.items, required this.selectedIndex, required this.child});

  final List<NavItem> items;
  final int selectedIndex;
  final Widget child;

  static const _maxBottomDestinations = 4;

  @override
  Widget build(BuildContext context) {
    final primary = items.take(_maxBottomDestinations).toList();
    final overflow = items.skip(_maxBottomDestinations).toList();
    final hasOverflow = overflow.isNotEmpty;

    final inOverflow = selectedIndex >= _maxBottomDestinations;

    return Scaffold(
      appBar: _TopBar(
        title: _titleFor(items, selectedIndex),
        leading: hasOverflow
            ? Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
      ),
      drawer: hasOverflow
          ? Drawer(
              child: ListView(
                children: [
                  const DrawerHeader(child: Text('More')),
                  for (final item in overflow)
                    ListTile(
                      leading: Icon(item.icon),
                      title: Text(item.label),
                      selected: item.path == (selectedIndex >= 0 ? items[selectedIndex].path : ''),
                      onTap: () {
                        Navigator.of(context).pop();
                        _navigateTo(context, items, items.indexOf(item));
                      },
                    ),
                ],
              ),
            )
          : null,
      body: child,
      bottomNavigationBar: primary.isEmpty
          ? null
          : NavigationBar(
              selectedIndex: inOverflow || selectedIndex < 0
                  ? 0
                  : selectedIndex.clamp(0, primary.length - 1),
              onDestinationSelected: (index) => _navigateTo(context, items, index),
              destinations: [
                for (final item in primary)
                  NavigationDestination(icon: Icon(item.icon), selectedIcon: Icon(item.selectedIcon), label: item.label),
              ],
            ),
    );
  }
}
