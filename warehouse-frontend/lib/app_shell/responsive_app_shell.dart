import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../core/auth/app_user.dart';
import '../core/auth/auth_provider.dart';
import '../core/theme/nocturne.dart';
import '../core/theme/theme_mode_provider.dart';
import '../features/scan/scan_lookup.dart';
import '../features/settings/data/account_api.dart';
import '../features/stock_adjustments/data/stock_adjustments_providers.dart';
import '../features/stock_adjustments/domain/stock_adjustment.dart';
import '../features/workstreams/data/workstream_managers_providers.dart';
import '../routing/nav_items.dart';
import '../routing/route_paths.dart';
import '../shared/nx/nx_form.dart';
import '../shared/nx/nx_list_page.dart';
import '../shared/nx/nx_overlays.dart';
import '../shared/nx/nx_primitives.dart';
import 'branding.dart';
import 'console_notifications.dart';
import 'nav_expansion_provider.dart';

/// The Warehouse Console shell (Warehouse Console v2 prototype): a 50px top
/// bar (brand + breadcrumb, product search, theme toggle, notifications,
/// user), then — by width — a 232px grouped sidebar (desktop ≥1024), a 72px
/// rail with pop-out group menus (tablet 600–1023), or a drawer plus a bottom
/// bar (phone <600). Pages scroll themselves (see [NxPageScroll]).
class ResponsiveAppShell extends ConsumerWidget {
  const ResponsiveAppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value?.user;
    final groups = visibleNavGroups(user);
    return _ShellFrame(groups: groups, user: user, currentPath: currentPath, child: child);
  }
}

enum _Mode { phone, tablet, desktop }

_Mode _modeOf(double width) => width < 600
    ? _Mode.phone
    : width < 1024
    ? _Mode.tablet
    : _Mode.desktop;

/// The pending-adjustment count shown as a warn badge on "Stock Adjustments"
/// (and on its group while collapsed) — for anyone who can act on the queue.
final _pendingBadgeProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authProvider).value?.user;
  if (user == null || !user.canAny(const ['inventory.adjust.approve', 'inventory.adjust.request'])) return 0;
  try {
    return (await ref.watch(stockAdjustmentsListProvider(AdjustmentStatus.pending).future)).length;
  } catch (_) {
    return 0;
  }
});

class _ShellFrame extends ConsumerStatefulWidget {
  const _ShellFrame({required this.groups, required this.user, required this.currentPath, required this.child});

  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;
  final Widget child;

  @override
  ConsumerState<_ShellFrame> createState() => _ShellFrameState();
}

class _ShellFrameState extends ConsumerState<_ShellFrame> {
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _revealActiveGroup();
  }

  @override
  void didUpdateWidget(covariant _ShellFrame old) {
    super.didUpdateWidget(old);
    if (old.currentPath != widget.currentPath) _revealActiveGroup();
  }

  void _revealActiveGroup() {
    final group = _groupOf(widget.currentPath);
    if (group != null && !group.flat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(navExpansionProvider.notifier).open(group.id);
      });
    }
  }

  NavGroup? _groupOf(String path) {
    final item = navItemMatching(widget.groups.expand((g) => g.items), path);
    if (item == null) return null;
    return widget.groups.where((g) => g.items.contains(item)).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final mode = _modeOf(MediaQuery.of(context).size.width);
    final item = navItemMatching(widget.groups.expand((g) => g.items), widget.currentPath);
    final group = _groupOf(widget.currentPath);
    final badge = ref.watch(_pendingBadgeProvider).value ?? 0;

    return Scaffold(
      key: _scaffold,
      backgroundColor: n.bg,
      drawer: mode == _Mode.desktop
          ? null
          : _ConsoleDrawer(groups: widget.groups, user: widget.user, currentPath: widget.currentPath, badge: badge),
      drawerScrimColor: n.n900.withValues(alpha: 0.65),
      body: Column(
        children: [
          _TopBar(
            mode: mode,
            user: widget.user,
            crumbGroup: group != null && !group.flat ? group.title : null,
            crumbLabel: item?.label ?? '',
            onMenu: () => _scaffold.currentState?.openDrawer(),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (mode == _Mode.desktop)
                  _Sidebar(groups: widget.groups, user: widget.user, currentPath: widget.currentPath, badge: badge),
                if (mode == _Mode.tablet) _Rail(groups: widget.groups, currentPath: widget.currentPath, badge: badge),
                Expanded(child: widget.child),
              ],
            ),
          ),
          if (mode == _Mode.phone)
            _BottomBar(
              groups: widget.groups,
              currentPath: widget.currentPath,
              onMenu: () => _scaffold.currentState?.openDrawer(),
            ),
        ],
      ),
    );
  }
}

// ─── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.mode, required this.user, required this.crumbGroup, required this.crumbLabel, required this.onMenu});

  final _Mode mode;
  final AppUser? user;
  final String? crumbGroup;
  final String crumbLabel;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final dark = n.isDark;
    final notes = ref.watch(consoleNotificationsProvider).value ?? const <ConsoleNotification>[];
    final seen = ref.watch(seenNotificationsProvider);
    final unread = notes.where((x) => !seen.contains(x.key)).length;
    final roleName = user?.roles.isNotEmpty == true ? user!.roles.first.name : null;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Nocturne.mix(n.surface, n.bg, 0.7), n.bg],
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              if (mode != _Mode.desktop) ...[
                NxIconButton(icon: PhosphorIconsRegular.list, tooltip: 'Menu', iconSize: 20, onPressed: onMenu),
                const SizedBox(width: 10),
              ],
              if (mode != _Mode.phone) ...[
                SizedBox(width: mode == _Mode.desktop ? 212 : 170, child: const _Brand()),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      if (crumbGroup != null) ...[
                        Text(crumbGroup!, style: TextStyle(fontSize: 12, color: n.n400)),
                        const SizedBox(width: 7),
                        Icon(PhosphorIconsRegular.caretRight, size: 10, color: n.n600),
                        const SizedBox(width: 7),
                      ],
                      Flexible(
                        child: Text(
                          crumbLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: n.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else
                Expanded(
                  child: Text(
                    crumbLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: n.text),
                  ),
                ),
              if (mode == _Mode.desktop && (user?.can('catalogue.view') ?? false)) ...[
                const SizedBox(width: 300, child: _GlobalSearch()),
                const SizedBox(width: 10),
              ],
              if (user?.can('catalogue.view') ?? false) ...[
                NxIconButton(
                  icon: PhosphorIconsRegular.qrCode,
                  tooltip: 'Scan a product or location label',
                  iconSize: 19,
                  onPressed: () => scanAndOpen(context, ref),
                ),
                const SizedBox(width: 4),
              ],
              NxIconButton(
                icon: dark ? PhosphorIconsRegular.sun : PhosphorIconsRegular.moon,
                tooltip: dark ? 'Switch to light theme' : 'Switch to dark theme',
                onPressed: () => ref.read(themeModeProvider.notifier).setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
              ),
              const SizedBox(width: 4),
              NxIconButton(
                icon: PhosphorIconsRegular.bell,
                tooltip: 'Notifications',
                iconSize: 19,
                badge: unread,
                onPressed: () => _openNotifications(context, ref, mode),
              ),
              const SizedBox(width: 8),
              NxAvatar(name: user?.name ?? '?', accent: true),
              if (mode == _Mode.desktop) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: n.text, height: 1.2)),
                      if (roleName != null)
                        Text(roleName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: n.n400, height: 1.2)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const Positioned(left: 0, right: 0, bottom: 0, child: NxFadeRule()),
        ],
      ),
    );
  }

  void _openNotifications(BuildContext context, WidgetRef ref, _Mode mode) {
    final phone = mode == _Mode.phone;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close notifications',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (ctx, animation, _) => Stack(
        children: [
          Positioned(
            top: 54,
            left: phone ? 8 : null,
            right: phone ? 8 : 12,
            width: phone ? null : 360,
            child: FadeTransition(opacity: animation, child: const _NotificationsPanel()),
          ),
        ],
      ),
    );
  }
}

class _Brand extends ConsumerWidget {
  const _Brand();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final name = ref.watch(brandNameProvider);
    // Default product name keeps its two-tone look; a company name shows as-is.
    final span = name == kDefaultBrandName
        ? TextSpan(text: 'Warehouse ', children: [TextSpan(text: 'System', style: TextStyle(color: n.n500, fontWeight: FontWeight.w400))])
        : TextSpan(text: name);
    return Row(
      children: [
        const BrandMark(glow: true),
        const SizedBox(width: 9),
        Flexible(
          child: Text.rich(
            span,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text),
          ),
        ),
      ],
    );
  }
}

/// "Find a product by SKU or name" — Enter opens Products searched for it.
class _GlobalSearch extends ConsumerStatefulWidget {
  const _GlobalSearch();

  @override
  ConsumerState<_GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends ConsumerState<_GlobalSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxInput(
      controller: _controller,
      dense: true,
      prefixIcon: PhosphorIconsRegular.magnifyingGlass,
      placeholder: 'Find a product by SKU or name',
      fill: Nocturne.mix(n.surface, n.bg, 0.7),
      suffix: Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), border: Border.all(color: n.n800)),
        child: Text('Enter', style: TextStyle(fontSize: 10, color: n.n500)),
      ),
      onSubmitted: (q) {
        ref.read(nxListStatesProvider.notifier).preset('products', query: q.trim());
        _controller.clear();
        context.go(RoutePaths.products);
      },
    );
  }
}

class _NotificationsPanel extends ConsumerWidget {
  const _NotificationsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final notesAsync = ref.watch(consoleNotificationsProvider);
    final notes = notesAsync.value ?? const <ConsoleNotification>[];

    void go(ConsoleNotification x) {
      Navigator.of(context).pop();
      final target = x.target.startsWith('product:') ? '${RoutePaths.products}?open=${x.target.substring(8)}' : x.target;
      GoRouter.of(context).go(target);
    }

    return Material(
      color: n.surface,
      borderRadius: BorderRadius.circular(NxRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.lg), boxShadow: n.shadowLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                children: [
                  Expanded(child: Text('Notifications', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: n.text))),
                  NxButton.ghost(
                    label: 'Mark all read',
                    small: true,
                    onPressed: notes.isEmpty ? null : () => ref.read(seenNotificationsProvider.notifier).markAll(notes.map((x) => x.key)),
                  ),
                ],
              ),
            ),
            if (notesAsync.isLoading && notes.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 16),
                child: Text('Checking…', style: TextStyle(fontSize: 12, color: n.n400)),
              )
            else if (notes.isEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n800))),
                child: Text("You're all caught up.", style: TextStyle(fontSize: 12, color: n.n400)),
              )
            else
              for (final x in notes)
                _NoteRow(note: x, unread: !ref.watch(seenNotificationsProvider).contains(x.key), onTap: () => go(x)),
          ],
        ),
      ),
    );
  }
}

class _NoteRow extends StatelessWidget {
  const _NoteRow({required this.note, required this.unread, required this.onTap});

  final ConsoleNotification note;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final (fg, bg) = n.tone(note.tone);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n800))),
      child: NxHoverRow(
        topRule: false,
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NxIconTile(icon: note.icon, size: 30, iconSize: 15, fg: fg, bg: bg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                  Text(note.message, style: TextStyle(fontSize: 12, color: n.n400)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(note.time, style: TextStyle(fontSize: 11, color: n.n500)),
                if (unread) ...[
                  const SizedBox(height: 4),
                  Container(width: 7, height: 7, decoration: BoxDecoration(color: n.accent, shape: BoxShape.circle)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sidebar (desktop) ──────────────────────────────────────────────────────

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.groups, required this.user, required this.currentPath, required this.badge});

  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;
  final int badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    return Container(
      width: 232,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: n.n900)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.7],
          colors: [Nocturne.mix(n.surface, n.bg, 0.4), n.bg],
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: [_NavTree(groups: groups, currentPath: currentPath, badge: badge)],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
            child: Row(
              children: [
                Expanded(child: _SignedInAs(user: user)),
                NxIconButton(
                  icon: PhosphorIconsRegular.signOut,
                  tooltip: 'Sign out',
                  size: 30,
                  iconSize: 15,
                  bordered: true,
                  color: n.n400,
                  onPressed: () => confirmSignOut(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Signed in as" — name, then role · warehouse codes (and a scoped
/// manager's workstreams).
class _SignedInAs extends ConsumerWidget {
  const _SignedInAs({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final role = user?.roles.map((r) => r.name).join(', ') ?? '';
    final all = user?.can('warehouse.access.all') ?? false;
    final whs = all ? null : ref.watch(myWarehousesProvider).value;
    final where = all ? 'All warehouses' : (whs == null || whs.isEmpty ? null : whs.map((w) => w.code).join(', '));
    final ws = ref.watch(myWorkstreamAssignmentsProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        NxKicker('Signed in as', color: n.n500),
        Text(user?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: n.text)),
        Text(
          [role, ?where].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: n.a300),
        ),
        if (ws.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 4, runSpacing: 4, children: [for (final a in ws) NxTag(a.workstreamName, tone: Tone.info, small: true)]),
          ),
      ],
    );
  }
}

Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final ok = await showNxConfirm(
    context,
    title: 'Sign out?',
    body: "You'll need to sign in again to keep working.",
    confirmLabel: 'Sign out',
    danger: true,
  );
  if (ok) ref.read(authProvider.notifier).logout();
}

/// The grouped nav (sidebar and drawer). [large] is the drawer's roomier size.
class _NavTree extends ConsumerWidget {
  const _NavTree({required this.groups, required this.currentPath, required this.badge, this.large = false, this.onNavigate});

  final List<NavGroup> groups;
  final String currentPath;
  final int badge;
  final bool large;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(navExpansionProvider);
    final active = navItemMatching(groups.expand((g) => g.items), currentPath);
    int badgeOf(NavItem i) => i.path == RoutePaths.stockAdjustments ? badge : 0;

    void go(NavItem item) {
      onNavigate?.call();
      context.go(item.path);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in groups)
          if (g.flat)
            _NavItemButton(item: g.items.first, active: g.items.first == active, large: large, indent: false, onTap: () => go(g.items.first))
          else
            Padding(
              padding: EdgeInsets.only(top: large ? 6 : 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _GroupHeader(
                    group: g,
                    open: expanded.contains(g.id),
                    containsActive: g.items.contains(active),
                    badge: g.items.fold(0, (s, i) => s + badgeOf(i)),
                    large: large,
                    onTap: () => ref.read(navExpansionProvider.notifier).toggle(g.id),
                  ),
                  if (expanded.contains(g.id))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final it in g.items)
                            _NavItemButton(item: it, active: it == active, large: large, badge: badgeOf(it), onTap: () => go(it)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

class _GroupHeader extends StatefulWidget {
  const _GroupHeader({required this.group, required this.open, required this.containsActive, required this.badge, required this.large, required this.onTap});

  final NavGroup group;
  final bool open;
  final bool containsActive;
  final int badge;
  final bool large;
  final VoidCallback onTap;

  @override
  State<_GroupHeader> createState() => _GroupHeaderState();
}

class _GroupHeaderState extends State<_GroupHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final cue = !widget.open && widget.containsActive;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          expanded: widget.open,
          label: widget.group.title,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: widget.large ? 9 : 5),
            decoration: BoxDecoration(
              color: _hover ? n.textAlpha(0.04) : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: cue ? n.accent : Colors.transparent, width: 2)),
            ),
            child: Row(
              children: [
                PhosphorIcon(widget.group.icon, size: widget.large ? 16 : 15, color: cue ? n.a300 : n.n500),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.group.title.toUpperCase(),
                    style: TextStyle(fontSize: 11, letterSpacing: 0.77, color: _hover ? n.text : n.n400),
                  ),
                ),
                if (!widget.open && widget.badge > 0) ...[NxCountBadge(widget.badge), const SizedBox(width: 6)],
                AnimatedRotation(
                  turns: widget.open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 160),
                  child: Icon(PhosphorIconsBold.caretDown, size: 10, color: n.n400),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItemButton extends StatefulWidget {
  const _NavItemButton({required this.item, required this.active, required this.onTap, this.badge = 0, this.large = false, this.indent = true});

  final NavItem item;
  final bool active;
  final VoidCallback onTap;
  final int badge;
  final bool large;
  final bool indent;

  @override
  State<_NavItemButton> createState() => _NavItemButtonState();
}

class _NavItemButtonState extends State<_NavItemButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final a = widget.active;
    final large = widget.large;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: a,
          label: widget.item.label,
          child: Container(
            margin: const EdgeInsets.only(bottom: 1),
            padding: EdgeInsets.fromLTRB(widget.indent ? (large ? 18 : 16) : 10, large ? 10 : 6, 10, large ? 10 : 6),
            decoration: BoxDecoration(
              color: a ? n.a900 : (_hover ? n.textAlpha(0.04) : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: a ? n.accent : Colors.transparent, width: 2)),
            ),
            child: Row(
              children: [
                PhosphorIcon(widget.item.icon, size: large ? 17 : (widget.indent ? 15 : 17), color: a ? n.a300 : n.n500),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: large ? 14 : 13,
                      color: a ? n.text : n.n300,
                      fontWeight: a ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ),
                if (widget.badge > 0) NxCountBadge(widget.badge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Rail (tablet) ──────────────────────────────────────────────────────────

class _Rail extends ConsumerWidget {
  const _Rail({required this.groups, required this.currentPath, required this.badge});

  final List<NavGroup> groups;
  final String currentPath;
  final int badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final active = navItemMatching(groups.expand((g) => g.items), currentPath);
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: n.n900))),
      child: ListView(
        children: [
          for (final g in groups)
            Builder(
              builder: (btnContext) {
                final on = g.items.contains(active);
                final hasBadge = badge > 0 && g.items.any((i) => i.path == RoutePaths.stockAdjustments);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _RailButton(
                    icon: g.icon,
                    label: g.shortLabel,
                    selected: on,
                    dot: hasBadge,
                    onTap: () {
                      if (g.flat) {
                        context.go(g.items.first.path);
                      } else {
                        _flyout(btnContext, g, active, badge);
                      }
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _flyout(BuildContext btnContext, NavGroup g, NavItem? active, int badge) {
    final box = btnContext.findRenderObject() as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    showGeneralDialog<void>(
      context: btnContext,
      barrierDismissible: true,
      barrierLabel: 'Close menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, animation, _) {
        final n = ctx.nx;
        return Stack(
          children: [
            Positioned(
              left: 78,
              top: top,
              width: 230,
              child: FadeTransition(
                opacity: animation,
                child: Material(
                  color: n.surface,
                  borderRadius: BorderRadius.circular(NxRadius.md),
                  child: DecoratedBox(
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.md), boxShadow: n.shadowMd),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(padding: const EdgeInsets.fromLTRB(8, 6, 8, 6), child: NxKicker(g.title, size: 11, color: n.n400)),
                          for (final it in g.items)
                            _NavItemButton(
                              item: it,
                              active: it == active,
                              indent: false,
                              badge: it.path == RoutePaths.stockAdjustments ? badge : 0,
                              onTap: () {
                                Navigator.of(ctx).pop();
                                GoRouter.of(btnContext).go(it.path);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({required this.icon, required this.label, required this.selected, required this.dot, required this.onTap});

  final IconData icon;
  final String label;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final color = widget.selected ? n.a200 : n.n400;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.label,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            decoration: BoxDecoration(
              color: widget.selected ? n.a900 : (_hover ? n.textAlpha(0.06) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Column(
                    children: [
                      PhosphorIcon(widget.icon, size: 21, color: color),
                      const SizedBox(height: 3),
                      Text(widget.label, style: TextStyle(fontSize: 10, color: color)),
                    ],
                  ),
                ),
                if (widget.dot)
                  Positioned(
                    top: 0,
                    right: 12,
                    child: Container(width: 7, height: 7, decoration: BoxDecoration(color: n.warn, shape: BoxShape.circle)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Drawer + bottom bar (phone / tablet) ───────────────────────────────────

class _ConsoleDrawer extends ConsumerWidget {
  const _ConsoleDrawer({required this.groups, required this.user, required this.currentPath, required this.badge});

  final List<NavGroup> groups;
  final AppUser? user;
  final String currentPath;
  final int badge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final role = user?.roles.isNotEmpty == true ? user!.roles.first.name : '';
    return Drawer(
      width: 284,
      backgroundColor: n.bg,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: n.n900))),
              child: Row(
                children: [
                  const BrandMark(size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ref.watch(brandNameProvider),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text),
                        ),
                        Text(
                          [user?.name ?? '', role].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: n.n400),
                        ),
                      ],
                    ),
                  ),
                  NxIconButton(
                    icon: PhosphorIconsRegular.x,
                    tooltip: 'Close menu',
                    size: 30,
                    color: n.n400,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  _NavTree(
                    groups: groups,
                    currentPath: currentPath,
                    badge: badge,
                    large: true,
                    onNavigate: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: n.n900))),
              child: NxButton(
                label: 'Sign out',
                icon: PhosphorIconsRegular.signOut,
                expand: true,
                color: n.n300,
                onPressed: () {
                  Navigator.of(context).pop();
                  confirmSignOut(context, ref);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.groups, required this.currentPath, required this.onMenu});

  final List<NavGroup> groups;
  final String currentPath;
  final VoidCallback onMenu;

  static const _slots = [
    (RoutePaths.dashboard, 'Home', PhosphorIconsDuotone.gauge),
    (RoutePaths.products, 'Products', PhosphorIconsDuotone.package),
    (RoutePaths.inventory, 'Inventory', PhosphorIconsDuotone.cube),
    (RoutePaths.receiving, 'Receive', PhosphorIconsDuotone.boxArrowDown),
  ];

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final all = groups.expand((g) => g.items).toList();
    final visible = {for (final i in all) i.path};
    final activePath = navItemMatching(all, currentPath)?.path;
    final slots = _slots.where((s) => visible.contains(s.$1)).toList();
    final inBar = slots.any((s) => s.$1 == activePath);

    Widget slot(String label, IconData icon, bool on, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: on ? n.accent : Colors.transparent, width: 2))),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PhosphorIcon(icon, size: 21, color: on ? n.a300 : n.n400),
                const SizedBox(height: 2),
                Text(label, style: TextStyle(fontSize: 10, color: on ? n.a300 : n.n400)),
              ],
            ),
          ),
        ),
      ),
    );

    return SafeArea(
      top: false,
      child: Container(
        height: 58,
        decoration: BoxDecoration(color: n.bg, border: Border(top: BorderSide(color: n.n900))),
        child: Row(
          children: [
            for (final s in slots) slot(s.$2, s.$3, s.$1 == activePath, () => context.go(s.$1)),
            slot('Menu', PhosphorIconsRegular.list, !inBar, onMenu),
          ],
        ),
      ),
    );
  }
}

/// The scrolling page area every console screen lives in: the prototype's
/// padding (16/20/28, or 12/12/20 on a phone) and a pull-to-refresh hook.
class NxPageScroll extends StatelessWidget {
  const NxPageScroll({super.key, required this.child, this.onRefresh});

  final Widget child;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final phone = MediaQuery.of(context).size.width < 600;
    final scroll = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: phone ? const EdgeInsets.fromLTRB(12, 12, 12, 20) : const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: child,
    );
    if (onRefresh == null) return scroll;
    return RefreshIndicator(onRefresh: onRefresh!, color: context.nx.accent, child: scroll);
  }
}
