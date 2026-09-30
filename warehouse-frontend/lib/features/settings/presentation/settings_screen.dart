import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/account_api.dart';
import 'widgets/account_sections.dart';
import 'widgets/api_keys_section.dart';
import 'widgets/branding_section.dart';
import 'widgets/delivery_settings_section.dart';
import 'widgets/settings_head.dart';

typedef _Sec = (String id, String label, IconData icon);

/// Settings (prototype `settings`): a section list beside one panel —
/// profile, appearance, report branding, contact & alerts, sign-in check,
/// password, and (with the permissions) API keys and email & SMS delivery.
/// `/settings?section=<id>` opens a section.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final String? initialSection;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late String _sec = widget.initialSection ?? 'profile';

  @override
  void didUpdateWidget(covariant SettingsScreen old) {
    super.didUpdateWidget(old);
    if (widget.initialSection != null && widget.initialSection != old.initialSection) _sec = widget.initialSection!;
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final phone = MediaQuery.of(context).size.width < 600;
    final secs = <_Sec>[
      ('profile', 'Profile', PhosphorIconsDuotone.user),
      ('appearance', 'Appearance', PhosphorIconsDuotone.palette),
      ('branding', 'Report branding', PhosphorIconsDuotone.image),
      ('contact', 'Contact & alerts', PhosphorIconsDuotone.bellSimple),
      ('mfa', 'Sign-in check', PhosphorIconsDuotone.shieldCheck),
      ('password', 'Password', PhosphorIconsDuotone.password),
      if (user?.can('users.manage') ?? false) ('keys', 'API keys', PhosphorIconsDuotone.key),
      if (user?.can('settings.manage') ?? false) ('delivery', 'Email & SMS delivery', PhosphorIconsDuotone.paperPlaneTilt),
    ];
    final current = secs.any((s) => s.$1 == _sec) ? _sec : 'profile';

    final nav = phone
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [for (final s in secs) _NavItem(sec: s, selected: s.$1 == current, onTap: () => setState(() => _sec = s.$1))]),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final s in secs) _NavItem(sec: s, selected: s.$1 == current, onTap: () => setState(() => _sec = s.$1))],
          );

    final Widget panel = user == null
        ? const SizedBox.shrink()
        : switch (current) {
            'appearance' => const _AppearanceSection(),
            'branding' => BrandingSection(canManage: user.can('settings.manage')),
            // Keyed on the saved values so the form re-seeds after a save.
            'contact' => ContactSection(key: ValueKey('${user.phone}|${user.notifyChannel}'), user: user),
            'mfa' => MfaSection(user: user),
            'password' => const PasswordSection(),
            'keys' => const ApiKeysSection(),
            'delivery' => const DeliverySettingsSection(),
            _ => _ProfileSection(user: user),
          };

    return NxPageScroll(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Settings', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: n.text)),
              const SizedBox(height: 12),
              if (phone) ...[
                nav,
                const SizedBox(height: 12),
                NxSection(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: panel),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 200, child: nav),
                    const SizedBox(width: 14),
                    Expanded(child: NxSection(padding: const EdgeInsets.fromLTRB(16, 14, 16, 16), child: panel)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.sec, required this.selected, required this.onTap});

  final _Sec sec;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2, right: 2),
      child: Material(
        color: selected ? n.a900 : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: selected ? n.accent : Colors.transparent, width: 2))),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(sec.$3, size: 15, color: selected ? n.text : n.n400),
                const SizedBox(width: 8),
                Text(sec.$2, style: TextStyle(fontSize: 13, color: selected ? n.text : n.n400)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSection extends ConsumerWidget {
  const _ProfileSection({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final all = user.can('warehouse.access.all');
    final warehouses = ref.watch(myWarehousesProvider);
    Widget row(String label, Widget value) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 13, color: n.n400))),
          Expanded(child: DefaultTextStyle.merge(style: TextStyle(fontSize: 13, color: n.text), child: value)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Profile'),
        row('Name', Text(user.name)),
        row('Email', Text(user.email)),
        row(
          'Roles',
          user.roles.isEmpty
              ? const Text('—')
              : Wrap(spacing: 4, runSpacing: 4, children: [for (final r in user.roles) NxTag(r.name, tone: Tone.accent)]),
        ),
        row(
          'Warehouses',
          all
              ? const Text('All warehouses — your role gives you access to every one')
              : warehouses.when(
                  loading: () => const Text('…'),
                  error: (e, _) => Text(e is AppError ? e.message : 'Could not load your warehouses.', style: TextStyle(color: n.bad)),
                  data: (list) => list.isEmpty
                      ? Text('None yet — ask an administrator to add you.', style: TextStyle(color: n.warn))
                      : Text(list.map((w) => '${w.name} · ${w.code}').join(', ')),
                ),
        ),
        const SizedBox(height: 6),
        Text('Your name and roles are managed by an administrator.', style: TextStyle(fontSize: 11, color: n.n500)),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Appearance', sub: 'Saved on this device. Also available from the sun/moon button in the top bar.'),
        NxField(
          label: 'Theme',
          child: Align(
            alignment: Alignment.centerLeft,
            child: NxSeg<ThemeMode>(
              small: false,
              options: const [
                (ThemeMode.dark, 'Dark', PhosphorIconsRegular.moon),
                (ThemeMode.light, 'Light', PhosphorIconsRegular.sun),
                (ThemeMode.system, 'System', PhosphorIconsRegular.desktop),
              ],
              value: mode,
              onChanged: (m) => ref.read(themeModeProvider.notifier).setThemeMode(m),
            ),
          ),
        ),
      ],
    );
  }
}
