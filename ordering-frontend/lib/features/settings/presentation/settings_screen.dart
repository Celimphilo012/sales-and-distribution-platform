import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/status_badge.dart';

/// STEP R1 — SETTINGS: profile (any logged-in user, from the now-extended
/// `AppUser.roles/status`) and a password section. Ported from the
/// warehouse app's admin template MINUS the API-key section — the ordering
/// system has no such concept (that's a warehouse-specific, external-API
/// mechanism, ARCHITECTURE.md §A2 step 3).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider.select((s) => s.value?.user));

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ListView(
        children: [
          Text('Settings', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.lg),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _ProfileSection(user: user),
          ),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _PasswordSection(),
          ),
        ],
      ),
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.user});

  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (user == null) return const SizedBox.shrink();

    return AppCard(
      title: 'Profile',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ProfileRow(label: 'Name', value: user!.name),
          _ProfileRow(label: 'Email', value: user!.email),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Roles',
                    style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: user!.roles.isEmpty
                      ? Text('—', style: theme.textTheme.bodyMedium)
                      : Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final role in user!.roles)
                              StatusBadge(label: role.name, tone: StatusTone.info),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

/// BACKEND GAP (same as the warehouse system — the two backends share this
/// auth module's origin): there is no self-service "change my own password"
/// endpoint — `PATCH /users/:id` accepts a new `password`, but it is gated
/// `users.manage` and takes no `currentPassword` check, so it's an ADMIN
/// reset capability, not a change-password flow a regular user could use on
/// themself. Reported rather than faked.
class _PasswordSection extends StatelessWidget {
  const _PasswordSection();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      title: 'Password',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Self-service password change is not available yet — the backend has no endpoint '
              'for it. A user with the users.manage permission can reset a password from the '
              'Users screen (including their own), but that is an admin reset, not a '
              'current+new password flow.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
