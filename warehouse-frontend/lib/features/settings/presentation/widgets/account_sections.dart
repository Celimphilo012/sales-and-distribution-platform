import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/auth/app_user.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../../../shared/widgets/status_badge.dart';
import '../../../users/domain/user.dart';
import '../../data/account_api.dart';

/// Phone number + how approval notifications reach me (email / SMS / off).
class ContactSection extends ConsumerStatefulWidget {
  const ContactSection({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends ConsumerState<ContactSection> {
  late final _phoneController = TextEditingController(text: widget.user.phone ?? '');
  late String _channel = widget.user.notifyChannel;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).updateProfile(phone: _phoneController.text.trim(), notifyChannel: _channel);
      await ref.read(authProvider.notifier).refreshUser();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contact details saved.')));
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
      title: 'Contact & notifications',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            label: 'Mobile number',
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            enabled: !_saving,
            prefixIcon: Icons.phone_iphone_outlined,
            hintText: '+268 7612 3456',
            helperText: 'International format with the country code. Needed for SMS codes and SMS notifications.',
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Notify me about approvals by', style: theme.textTheme.labelMedium),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<String>(
            segments: [
              for (final entry in kNotifyChannelLabels.entries) ButtonSegment(value: entry.key, label: Text(entry.value)),
            ],
            selected: {_channel},
            onSelectionChanged: _saving ? null : (s) => setState(() => _channel = s.first),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Adjustment requests waiting for you, and the outcome of your own requests.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}

/// Sign-in verification (MFA): off, email code, SMS code or authenticator app.
class MfaSection extends ConsumerStatefulWidget {
  const MfaSection({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<MfaSection> createState() => _MfaSectionState();
}

class _MfaSectionState extends ConsumerState<MfaSection> {
  bool _busy = false;
  String? _error;

  Future<void> _setUp(String method) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final start = await ref.read(accountApiProvider).startMfaSetup(method);
      if (!mounted) return;
      final done = await AppDialog.show<bool>(
        context,
        title: 'Set up ${kMfaMethodLabels[method]}',
        content: _MfaSetupBody(start: start),
      );
      if (done == true) {
        await ref.read(authProvider.notifier).refreshUser();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sign-in verification is now: ${kMfaMethodLabels[method]}.')),
          );
        }
      }
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).disableMfa();
      await ref.read(authProvider.notifier).refreshUser();
    } on AppError catch (e) {
      if (e is! ConfirmationRequiredError) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;
    final current = user.mfaMethod;
    final hasPhone = (user.phone ?? '').isNotEmpty;

    return AppCard(
      title: 'Sign-in verification',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Currently', style: theme.textTheme.labelMedium),
              const SizedBox(width: AppSpacing.sm),
              StatusBadge(
                label: kMfaMethodLabels[current] ?? current,
                tone: current == 'NONE' ? StatusTone.neutral : StatusTone.success,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'With verification on, signing in also needs a 6-digit code — sent by email or SMS, or shown in an '
            'authenticator app (Google Authenticator, Microsoft Authenticator, Authy…).',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final method in const ['TOTP', 'EMAIL', 'SMS'])
                if (method != current)
                  OutlinedButton(
                    onPressed: _busy || (method == 'SMS' && !hasPhone) ? null : () => _setUp(method),
                    child: Text(switch (method) {
                      'TOTP' => 'Use an authenticator app',
                      'EMAIL' => 'Use email codes',
                      _ => 'Use SMS codes',
                    }),
                  ),
              if (current != 'NONE')
                TextButton(onPressed: _busy ? null : _turnOff, child: const Text('Turn off')),
            ],
          ),
          if (!hasPhone)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Add a mobile number above to use SMS codes.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

/// Body of the set-up dialog: QR + secret for the app, or "code sent to …"
/// for email/SMS, then the code that proves it works. Pops `true` once on.
class _MfaSetupBody extends ConsumerStatefulWidget {
  const _MfaSetupBody({required this.start});

  final MfaSetupStart start;

  @override
  ConsumerState<_MfaSetupBody> createState() => _MfaSetupBodyState();
}

class _MfaSetupBodyState extends ConsumerState<_MfaSetupBody> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).confirmMfaSetup(challengeId: widget.start.challengeId, code: code);
      if (mounted) Navigator.of(context, rootNavigator: true).pop(true);
    } on AppError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
      _codeController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = widget.start;
    final isApp = start.channel == 'TOTP';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isApp && start.otpauthUrl != null) ...[
          Text('1. Scan this with your authenticator app.', style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Container(
              color: context.semanticColors.qrBackground,
              padding: const EdgeInsets.all(AppSpacing.sm),
              // A tight SizedBox answers the dialog's intrinsic-size query itself —
              // QrImageView's inner LayoutBuilder can't, and would throw.
              child: SizedBox(
                width: 200,
                height: 200,
                child: QrImageView(
                  data: start.otpauthUrl!,
                  size: 200,
                  backgroundColor: context.semanticColors.qrBackground,
                  eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: context.semanticColors.qrForeground),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: context.semanticColors.qrForeground,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Can\'t scan? Enter this key in the app instead:', style: theme.textTheme.bodySmall),
          SelectableText(
            start.secret ?? '',
            style: theme.textTheme.titleMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 2),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('2. Enter the 6-digit code the app now shows.', style: theme.textTheme.bodyMedium),
        ] else
          Text('We sent a 6-digit code to ${start.destination}. Enter it to switch this on.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _codeController,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
          onSubmitted: (_) => _confirm(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(onPressed: _busy ? null : _confirm, child: Text(_busy ? 'Checking…' : 'Turn on')),
          ],
        ),
      ],
    );
  }
}

/// The warehouses I can see and work in.
class MyWarehousesSection extends ConsumerWidget {
  const MyWarehousesSection({super.key, required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final all = user.can('warehouse.access.all');
    final warehouses = ref.watch(myWarehousesProvider);

    return AppCard(
      title: 'My warehouses',
      child: all
          ? Text('All warehouses — your role gives you access to every warehouse.', style: theme.textTheme.bodyMedium)
          : warehouses.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(e is AppError ? e.message : 'Could not load your warehouses.', style: muted),
              data: (list) => list.isEmpty
                  ? Text(
                      'You are not assigned to any warehouse yet, so there is nothing for you to see. Ask an administrator to add you.',
                      style: muted,
                    )
                  : Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final w in list) StatusBadge(label: '${w.name} (${w.code})', tone: StatusTone.info),
                      ],
                    ),
            ),
    );
  }
}
