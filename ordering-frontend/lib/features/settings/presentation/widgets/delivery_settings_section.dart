import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_semantic_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/date_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../data/delivery_settings_api.dart';

/// Admin (`settings.manage`): where one-time codes and notifications are sent
/// from — the organisation's own SMTP mail server and httpSMS account. Until
/// switched on here, messages are only written to the server log.
class DeliverySettingsSection extends ConsumerWidget {
  const DeliverySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(deliverySettingsProvider);
    return AppCard(
      title: 'Email & SMS delivery',
      subtitle: 'Sign-in codes, confirmation codes and approval notifications are sent with these settings.',
      child: settings.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text(
          e is AppError ? e.message : 'Could not load delivery settings.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
        // Keyed on the saved state so the form re-seeds after a save.
        data: (s) => _DeliveryForm(key: ValueKey(s.updatedAt), settings: s),
      ),
    );
  }
}

class _DeliveryForm extends ConsumerStatefulWidget {
  const _DeliveryForm({super.key, required this.settings});

  final DeliverySettings settings;

  @override
  ConsumerState<_DeliveryForm> createState() => _DeliveryFormState();
}

class _DeliveryFormState extends ConsumerState<_DeliveryForm> {
  late bool _emailEnabled = widget.settings.emailEnabled;
  late bool _secure = widget.settings.secure;
  late bool _smsEnabled = widget.settings.smsEnabled;
  late final _host = TextEditingController(text: widget.settings.host);
  late final _port = TextEditingController(text: '${widget.settings.port}');
  late final _user = TextEditingController(text: widget.settings.user);
  final _password = TextEditingController();
  late final _from = TextEditingController(text: widget.settings.from);
  final _apiKey = TextEditingController();
  late final _smsFrom = TextEditingController(text: widget.settings.smsFrom);
  final _testTo = TextEditingController();

  bool _saving = false;
  bool _testing = false;
  String? _error;
  String? _testMessage;
  bool _testOk = false;

  @override
  void dispose() {
    for (final c in [_host, _port, _user, _password, _from, _apiKey, _smsFrom, _testTo]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(deliverySettingsApiProvider)
          .save(
            emailEnabled: _emailEnabled,
            host: _host.text.trim(),
            port: int.tryParse(_port.text.trim()) ?? 587,
            secure: _secure,
            user: _user.text.trim(),
            password: _password.text,
            from: _from.text.trim(),
            smsEnabled: _smsEnabled,
            apiKey: _apiKey.text.trim(),
            smsFrom: _smsFrom.text.trim(),
          );
      ref.invalidate(deliverySettingsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery settings saved.')));
      }
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test(String channel) async {
    final to = _testTo.text.trim();
    if (to.isEmpty) {
      setState(() => _testMessage = 'Enter an email address or phone number to send the test to.');
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final result = await ref.read(deliverySettingsApiProvider).sendTest(channel: channel, to: to);
      setState(() {
        _testOk = result.ok;
        _testMessage = result.ok
            ? 'Test ${channel == 'SMS' ? 'SMS' : 'email'} sent to $to. '
                  '${(channel == 'SMS' ? widget.settings.smsEnabled : widget.settings.emailEnabled) ? 'Check it arrived.' : 'Real sending is off, so it was only written to the server log.'}'
            : 'Sending failed: ${result.error ?? 'unknown error'}';
      });
    } on AppError catch (e) {
      setState(() {
        _testOk = false;
        _testMessage = e.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final s = widget.settings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Email ----------------------------------------------------------------
        Text('Email (SMTP)', style: theme.textTheme.titleSmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send real emails'),
          subtitle: Text(
            _emailEnabled ? 'Through the mail server below.' : 'Off — emails are only written to the server log.',
          ),
          value: _emailEnabled,
          onChanged: _saving ? null : (v) => setState(() => _emailEnabled = v),
        ),
        AppTextField(
          label: 'SMTP server (host)',
          controller: _host,
          hintText: 'smtp.yourcompany.com',
          enabled: !_saving,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            SizedBox(
              width: 140,
              child: AppTextField(
                label: 'Port',
                controller: _port,
                keyboardType: TextInputType.number,
                enabled: !_saving,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('SSL/TLS from the start'),
                subtitle: Text('On for port 465; off for 587 (STARTTLS).', style: muted),
                value: _secure,
                onChanged: _saving ? null : (v) => setState(() => _secure = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(label: 'Username', controller: _user, enabled: !_saving),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'Password',
          controller: _password,
          obscureText: true,
          enabled: !_saving,
          hintText: s.hasPassword ? 'Saved — leave blank to keep it' : null,
          helperText: s.hasPassword ? 'A password is saved. Type a new one only to change it.' : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'Send from',
          controller: _from,
          hintText: 'Orders <orders@yourcompany.com>',
          enabled: !_saving,
        ),
        const Divider(height: AppSpacing.xl),

        // ---- SMS ------------------------------------------------------------------
        Text('SMS (httpSMS)', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'httpSMS sends texts through an Android phone: install the httpSMS app on it, sign in at httpsms.com, '
          'and copy the API key from its Settings page.',
          style: muted,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Send real SMS'),
          subtitle: Text(
            _smsEnabled ? 'Through the httpSMS phone below.' : 'Off — texts are only written to the server log.',
          ),
          value: _smsEnabled,
          onChanged: _saving ? null : (v) => setState(() => _smsEnabled = v),
        ),
        AppTextField(
          label: 'httpSMS API key',
          controller: _apiKey,
          obscureText: true,
          enabled: !_saving,
          hintText: s.hasApiKey ? 'Saved — leave blank to keep it' : null,
          helperText: s.hasApiKey ? 'An API key is saved. Paste a new one only to change it.' : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(
          label: 'httpSMS phone number',
          controller: _smsFrom,
          keyboardType: TextInputType.phone,
          hintText: '+268 7600 0000',
          helperText: 'The number of the phone running the httpSMS app, with the country code.',
          enabled: !_saving,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save delivery settings'),
            ),
            const SizedBox(width: AppSpacing.md),
            if (s.updatedAt != null)
              Expanded(
                child: Text(
                  'Last saved ${formatDateTime(s.updatedAt!)}${s.updatedByName == null ? '' : ' by ${s.updatedByName}'}',
                  style: muted,
                ),
              ),
          ],
        ),
        const Divider(height: AppSpacing.xl),

        // ---- Test -----------------------------------------------------------------
        Text('Send a test', style: theme.textTheme.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        Text('Uses the SAVED settings — save first.', style: muted),
        const SizedBox(height: AppSpacing.sm),
        AppTextField(label: 'Send the test to', controller: _testTo, hintText: 'you@yourcompany.com or +26876…'),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton(onPressed: _testing ? null : () => _test('EMAIL'), child: const Text('Send test email')),
            OutlinedButton(onPressed: _testing ? null : () => _test('SMS'), child: const Text('Send test SMS')),
          ],
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _testMessage!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _testOk ? context.semanticColors.success : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
