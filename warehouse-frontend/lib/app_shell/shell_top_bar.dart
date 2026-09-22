import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/app_user.dart';
import '../core/auth/auth_provider.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/theme_mode_provider.dart';

/// The dark application bar with the cyan rule beneath it (Broadsheet's
/// "front-page furniture"). Shows the brand, a breadcrumb on wider screens
/// (or just the page title on phones), the theme toggle and the account
/// menu. [onMenu] is non-null on layouts that hide the sidebar.
class ShellTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const ShellTopBar({super.key, required this.crumbs, required this.compact, this.onMenu});

  /// Breadcrumb trail, e.g. `['Stock', 'Inventory']`. May be empty.
  final List<String> crumbs;

  /// Phone layout: drop the brand + breadcrumb for a single page title.
  final bool compact;
  final VoidCallback? onMenu;

  static const double height = 52;

  @override
  Size get preferredSize => const Size.fromHeight(height + 3);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final user = ref.watch(authProvider).value?.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onBar = scheme.onInverseSurface;
    final muted = onBar.withValues(alpha: 0.62);

    return Container(
      height: height + 3,
      padding: const EdgeInsets.only(left: AppSpacing.xs, right: AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        border: Border(bottom: BorderSide(color: scheme.primary, width: 3)),
      ),
      child: IconTheme(
        data: IconThemeData(color: onBar),
        child: Row(
          children: [
            if (onMenu != null)
              IconButton(
                tooltip: 'Menu',
                onPressed: onMenu,
                icon: const PhosphorIcon(PhosphorIconsDuotone.list, size: 24),
              )
            else
              const SizedBox(width: AppSpacing.md - AppSpacing.xs),
            if (compact)
              Expanded(
                child: Text(
                  crumbs.isEmpty ? 'Warehouse System' : crumbs.last,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(color: onBar, fontWeight: FontWeight.w700),
                ),
              )
            else ...[
              Text(
                'Warehouse System',
                style: textTheme.titleMedium?.copyWith(color: onBar, fontWeight: FontWeight.w700, letterSpacing: 0.2),
              ),
              if (crumbs.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.md),
                Container(width: 1, height: 20, color: onBar.withValues(alpha: 0.25)),
                const SizedBox(width: AppSpacing.md),
                // Expanded (not Flexible + Spacer) so the breadcrumb takes all
                // the free width and the actions stay pinned to the right edge.
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _Breadcrumb(crumbs: crumbs, onBar: onBar, muted: muted),
                  ),
                ),
              ] else
                const Spacer(),
            ],
            IconButton(
              tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
              icon: PhosphorIcon(isDark ? PhosphorIconsDuotone.sun : PhosphorIconsDuotone.moon, size: 22),
            ),
            if (user != null) _AccountMenu(user: user, showName: !compact),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs, required this.onBar, required this.muted});

  final List<String> crumbs;
  final Color onBar;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.2);
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final last = i == crumbs.length - 1;
      if (i > 0) {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: PhosphorIcon(PhosphorIconsBold.caretRight, size: 11, color: muted),
        ));
      }
      children.add(Flexible(
        child: Text(
          crumbs[i].toUpperCase(),
          overflow: TextOverflow.ellipsis,
          style: style?.copyWith(color: last ? onBar : muted, fontWeight: last ? FontWeight.w600 : FontWeight.w400),
        ),
      ));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.user, required this.showName});

  final AppUser user;
  final bool showName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final onBar = scheme.onInverseSurface;
    final role = user.roles.isEmpty ? null : user.roles.map((r) => r.name).join(', ');

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, ShellTopBar.height - 8),
      onSelected: (value) {
        if (value == 'logout') ref.read(authProvider.notifier).logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user.name, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
              Text(user.email, style: textTheme.bodySmall),
              if (role != null) Text(role, style: textTheme.bodySmall?.copyWith(color: scheme.primary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: Row(
            children: [
              PhosphorIcon(PhosphorIconsDuotone.signOut, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: AppSpacing.sm),
              const Text('Sign out'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              color: scheme.primary,
              child: Text(
                _initials(user.name),
                style: textTheme.labelLarge?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700),
              ),
            ),
            if (showName) ...[
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      user.name,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(color: onBar, fontWeight: FontWeight.w600),
                    ),
                    if (role != null)
                      Text(
                        role,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(color: onBar.withValues(alpha: 0.62)),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
