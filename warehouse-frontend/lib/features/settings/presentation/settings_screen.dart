import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_user.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../users/data/users_providers.dart';
import '../data/api_keys_providers.dart';
import '../domain/api_key.dart';
import 'widgets/account_sections.dart';
import 'widgets/create_api_key_dialog.dart';
import 'widgets/delivery_settings_section.dart';
import 'widgets/raw_api_key_dialog.dart';

/// STEP 6f — SETTINGS: profile+password (any logged-in user) and API-key
/// management (gated `users.manage`, matching `ApiKeysController`).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authProvider.select((s) => s.value?.user));
    final canManageKeys = user?.can('users.manage') ?? false;

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
          if (user != null) ...[
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              // Keyed on the saved values so the form re-seeds after a save/refresh.
              child: ContactSection(key: ValueKey('${user.phone}|${user.notifyChannel}'), user: user),
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: MfaSection(user: user)),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: MyWarehousesSection(user: user)),
          ],
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: const _PasswordSection(),
          ),
          if (user?.can('settings.manage') ?? false) ...[
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: const DeliverySettingsSection()),
          ],
          if (canManageKeys) ...[
            const SizedBox(height: AppSpacing.lg),
            const _ApiKeysSection(),
          ],
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

/// Self-service change-password (`PATCH /users/me/password` — any
/// authenticated user, gated only by proving they know the current
/// password, not a permission). Distinct from the admin reset on the Users
/// screen, which needs `users.manage` and no current-password check.
class _PasswordSection extends ConsumerStatefulWidget {
  const _PasswordSection();

  @override
  ConsumerState<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<_PasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(usersApiProvider)
          .changeOwnPassword(currentPassword: _currentController.text, newPassword: _newController.text);
      _currentController.clear();
      _newController.clear();
      _confirmController.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Password changed.')));
      }
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      title: 'Password',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Current password',
              controller: _currentController,
              obscureText: true,
              enabled: !_saving,
              validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'New password',
              controller: _newController,
              obscureText: true,
              enabled: !_saving,
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter a new password';
                if (v.length < 8) return 'Must be at least 8 characters';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Confirm new password',
              controller: _confirmController,
              obscureText: true,
              enabled: !_saving,
              validator: (v) => v != _newController.text ? 'Passwords do not match' : null,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.lock_outline),
              label: Text(_saving ? 'Saving…' : 'Change password'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ApiKeysSection extends ConsumerWidget {
  const _ApiKeysSection();

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final created = await showCreateApiKeyDialog(context);
    if (created == null) return;
    ref.invalidate(apiKeysListProvider);
    if (context.mounted) await showRawApiKeyDialog(context, created);
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref, ApiKeyRecord key) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'Revoke "${key.name}"?',
      message: 'Any caller still using this key will be rejected immediately.',
      confirmLabel: 'Revoke',
      isDestructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(apiKeysApiProvider).revoke(key.id);
      ref.invalidate(apiKeysListProvider);
    } on AppError catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final keysAsync = ref.watch(apiKeysListProvider);
    final usersAsync = ref.watch(usersListProvider);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: AppCard(
        title: 'API Keys',
        subtitle:
            'Scoped keys the back-office uses to call this warehouse (ARCHITECTURE.md §A2). '
            'The raw key is shown once at creation and never again.',
        trailing: FilledButton.icon(
          onPressed: () => _create(context, ref),
          icon: const Icon(Icons.vpn_key_outlined),
          label: const Text('New key'),
        ),
        child: keysAsync.when(
          loading: () => const LoadingStateView(message: 'Loading API keys…'),
          error: (error, stackTrace) => ErrorStateView(
            message: error is AppError ? error.message : 'Could not load API keys.',
            onRetry: () => ref.invalidate(apiKeysListProvider),
          ),
          data: (keys) {
            if (keys.isEmpty) {
              return Text(
                'No API keys yet.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              );
            }
            final usersById = {for (final u in usersAsync.value ?? const []) u.id: u};
            return Column(
              children: [
                for (final key in keys) ...[
                  _ApiKeyTile(
                    apiKey: key,
                    createdByName: usersById[key.createdBy]?.fullName,
                    onRevoke: key.isActive ? () => _revoke(context, ref, key) : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ApiKeyTile extends StatelessWidget {
  const _ApiKeyTile({required this.apiKey, required this.createdByName, required this.onRevoke});

  final ApiKeyRecord apiKey;
  final String? createdByName;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(apiKey.name, style: theme.textTheme.bodyMedium),
                    const SizedBox(width: AppSpacing.sm),
                    StatusBadge(
                      label: apiKey.isActive ? 'Active' : 'Revoked',
                      tone: apiKey.isActive ? StatusTone.success : StatusTone.neutral,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [for (final scope in apiKey.scopes) StatusBadge(label: scope, tone: StatusTone.info)],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Created ${formatDateTime(apiKey.createdAt)}'
                  '${createdByName != null ? ' by $createdByName' : ''}'
                  ' · Last used: ${apiKey.lastUsedAt != null ? formatDateTime(apiKey.lastUsedAt!) : 'never'}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            IconButton(tooltip: 'Revoke', icon: const Icon(Icons.block), onPressed: onRevoke),
        ],
      ),
    );
  }
}
