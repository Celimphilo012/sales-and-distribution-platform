import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_form.dart';
import '../../../../shared/nx/nx_format.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../data/delivery_settings_api.dart';
import 'settings_head.dart';

/// Admin (`settings.manage`): where one-time codes and notifications are sent
/// from — the organisation's SMTP mail server and httpSMS account. Until
/// switched on here, messages are only written to the server log.
class DeliverySettingsSection extends ConsumerWidget {
  const DeliverySettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final settings = ref.watch(deliverySettingsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Email & SMS delivery', sub: 'Sign-in codes, confirmation codes and approval alerts are sent with these settings.'),
        settings.when(
          loading: () => const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (e, _) => Text(e is AppError ? e.message : 'Could not load delivery settings.', style: TextStyle(fontSize: 12, color: n.bad)),
          // Keyed on the saved state so the form re-seeds after a save.
          data: (s) => _DeliveryForm(key: ValueKey(s.updatedAt), settings: s),
        ),
      ],
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
      await ref.read(deliverySettingsApiProvider).save(
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
      NxToast.ok('Delivery settings saved');
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test(String channel) async {
    final to = _testTo.text.trim();
    if (to.isEmpty) {
      setState(() {
        _testOk = false;
        _testMessage = 'Enter an email address or phone number to send the test to.';
      });
      return;
    }
    setState(() {
      _testing = true;
      _testMessage = null;
    });
    try {
      final result = await ref.read(deliverySettingsApiProvider).sendTest(channel: channel, to: to);
      final live = channel == 'SMS' ? widget.settings.smsEnabled : widget.settings.emailEnabled;
      setState(() {
        _testOk = result.ok;
        _testMessage = result.ok
            ? 'Test ${channel == 'SMS' ? 'SMS' : 'email'} sent to $to. ${live ? 'Check it arrived.' : 'Real sending is off, so it was only written to the server log.'}'
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

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> onChanged) {
    final n = context.nx;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 13, color: n.text)),
              Text(sub, style: TextStyle(fontSize: 11, color: n.n500)),
            ],
          ),
        ),
        Switch(value: value, onChanged: _saving ? null : onChanged),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final s = widget.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxKicker('EMAIL (SMTP)', color: n.a300),
        const SizedBox(height: 6),
        _switch('Send real emails', _emailEnabled ? 'Through the mail server below.' : 'Off — emails are only written to the server log.', _emailEnabled, (v) => setState(() => _emailEnabled = v)),
        const SizedBox(height: 10),
        NxFormGrid(
          children: [
            NxSpan2(child: NxField(label: 'SMTP server (host)', child: NxInput(controller: _host, placeholder: 'smtp.yourcompany.com', enabled: !_saving))),
            NxField(
              label: 'Port',
              child: NxInput(controller: _port, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], enabled: !_saving),
            ),
            NxField(
              label: 'Encryption',
              hint: 'SSL for port 465; STARTTLS for 587',
              child: Align(
                alignment: Alignment.centerLeft,
                child: NxSeg<bool>(
                  options: const [(true, 'SSL/TLS', null), (false, 'STARTTLS', null)],
                  value: _secure,
                  onChanged: _saving ? null : (v) => setState(() => _secure = v),
                ),
              ),
            ),
            NxField(label: 'Username', child: NxInput(controller: _user, enabled: !_saving)),
            NxField(
              label: 'Password',
              hint: s.hasPassword ? 'Saved — type a new one only to change it' : null,
              child: NxInput(controller: _password, obscure: true, placeholder: s.hasPassword ? '••••••••' : null, enabled: !_saving),
            ),
            NxSpan2(
              child: NxField(label: 'Send from', child: NxInput(controller: _from, placeholder: 'Warehouse <warehouse@yourcompany.com>', enabled: !_saving)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        NxKicker('SMS (HTTPSMS)', color: n.a300),
        const SizedBox(height: 4),
        Text(
          'httpSMS sends texts through an Android phone: install the httpSMS app on it, sign in at httpsms.com, and copy the API key from its Settings page.',
          style: TextStyle(fontSize: 12, color: n.n400),
        ),
        const SizedBox(height: 6),
        _switch('Send real SMS', _smsEnabled ? 'Through the httpSMS phone below.' : 'Off — texts are only written to the server log.', _smsEnabled, (v) => setState(() => _smsEnabled = v)),
        const SizedBox(height: 10),
        NxFormGrid(
          children: [
            NxField(
              label: 'httpSMS API key',
              hint: s.hasApiKey ? 'Saved — paste a new one only to change it' : null,
              child: NxInput(controller: _apiKey, obscure: true, placeholder: s.hasApiKey ? '••••••••' : null, enabled: !_saving),
            ),
            NxField(
              label: 'httpSMS phone number',
              hint: 'The phone running the httpSMS app, with the country code',
              child: NxInput(controller: _smsFrom, placeholder: '+268 7600 0000', keyboardType: TextInputType.phone, enabled: !_saving),
            ),
          ],
        ),
        if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(fontSize: 12, color: n.bad))],
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            NxButton.primary(label: _saving ? 'Saving…' : 'Save delivery settings', onPressed: _saving ? null : _save),
            if (s.updatedAt != null)
              Text(
                'Last saved ${fmtDateTime(s.updatedAt!.toLocal())}${s.updatedByName == null ? '' : ' by ${s.updatedByName}'}',
                style: TextStyle(fontSize: 11, color: n.n500),
              ),
          ],
        ),
        const SizedBox(height: 18),
        NxKicker('SEND A TEST', color: n.a300),
        const SizedBox(height: 4),
        Text('Uses the SAVED settings — save first.', style: TextStyle(fontSize: 12, color: n.n400)),
        const SizedBox(height: 8),
        SettingsNarrow(child: NxInput(controller: _testTo, placeholder: 'you@yourcompany.com or +26876…')),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            NxButton(label: 'Send test email', icon: PhosphorIconsRegular.envelopeSimple, onPressed: _testing ? null : () => _test('EMAIL')),
            NxButton(label: 'Send test SMS', icon: PhosphorIconsRegular.chatText, onPressed: _testing ? null : () => _test('SMS')),
          ],
        ),
        if (_testMessage != null) ...[
          const SizedBox(height: 8),
          Text(_testMessage!, style: TextStyle(fontSize: 12, color: _testOk ? n.ok : n.bad)),
        ],
      ],
    );
  }
}
