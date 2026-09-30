import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../core/auth/app_user.dart';
import '../../../../core/auth/auth_provider.dart';
import '../../../../core/error/app_error.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_form.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../../users/data/users_providers.dart';
import '../../../users/domain/user.dart';
import '../../data/account_api.dart';
import 'settings_head.dart';

/// Contact & alerts: my mobile number and how approval alerts reach me.
class ContactSection extends ConsumerStatefulWidget {
  const ContactSection({super.key, required this.user});

  final AppUser user;

  @override
  ConsumerState<ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends ConsumerState<ContactSection> {
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late String _channel = widget.user.notifyChannel;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_channel == 'SMS' && _phone.text.trim().isEmpty) {
      setState(() => _error = 'SMS alerts need a mobile number.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).updateProfile(phone: _phone.text.trim(), notifyChannel: _channel);
      await ref.read(authProvider.notifier).refreshUser();
      NxToast.ok('Contact details saved', _channel == 'NONE' ? 'Alerts are off.' : 'Alerts go to ${kNotifyChannelLabels[_channel]}.');
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Contact & alerts', sub: 'Where we send approval alerts — requests waiting for you, and the outcome of yours.'),
        SettingsNarrow(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxField(
                label: 'Mobile number',
                hint: 'International format with the country code — needed for SMS codes and alerts',
                child: NxInput(controller: _phone, placeholder: '+268 7612 3456', keyboardType: TextInputType.phone, enabled: !_saving),
              ),
              const SizedBox(height: 12),
              NxField(
                label: 'Send alerts by',
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: NxSeg<String>(
                    options: [for (final e in kNotifyChannelLabels.entries) (e.key, e.value, null)],
                    value: _channel,
                    onChanged: _saving ? null : (v) => setState(() => _channel = v),
                  ),
                ),
              ),
              if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: TextStyle(fontSize: 12, color: n.bad))],
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: NxButton.primary(label: _saving ? 'Saving…' : 'Save', onPressed: _saving ? null : _save)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sign-in check (MFA): off, email code, SMS code or an authenticator app.
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
      final done = await showNxDialog<bool>(
        context,
        dismissible: false,
        builder: (_) => _MfaSetup(start: start, method: method),
      );
      if (done == true) {
        await ref.read(authProvider.notifier).refreshUser();
        NxToast.ok('Sign-in check updated', 'Now: ${kMfaMethodLabels[method]}.');
      }
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final ok = await showNxConfirm(
      context,
      title: 'Turn off the sign-in check?',
      body: 'Signing in will only need your password. Approvals still ask for a one-time code.',
      confirmLabel: 'Turn off',
      danger: true,
    );
    if (!ok) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountApiProvider).disableMfa();
      await ref.read(authProvider.notifier).refreshUser();
      NxToast.ok('Sign-in check turned off');
    } on AppError catch (e) {
      if (e is! ConfirmationRequiredError) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final current = widget.user.mfaMethod;
    final on = current != 'NONE';
    final hasPhone = (widget.user.phone ?? '').isNotEmpty;
    IconData icon(String m) => switch (m) {
      'TOTP' => PhosphorIconsDuotone.deviceMobile,
      'SMS' => PhosphorIconsDuotone.chatText,
      'EMAIL' => PhosphorIconsDuotone.envelopeSimple,
      _ => PhosphorIconsDuotone.shieldSlash,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Sign-in check', sub: 'A second step after your password — a 6-digit code by email, SMS or an authenticator app.'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(NxRadius.md), border: Border.all(color: n.divider)),
          child: Row(
            children: [
              Icon(icon(current), size: 20, color: n.a400),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(on ? kMfaMethodLabels[current] ?? current : 'Not set up', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                    Text(
                      on ? 'Asked for every time you sign in' : 'Only your password is needed to sign in',
                      style: TextStyle(fontSize: 11, color: n.n500),
                    ),
                  ],
                ),
              ),
              NxTag(on ? 'On' : 'Off', tone: on ? Tone.ok : Tone.neutral),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const ['TOTP', 'EMAIL', 'SMS'])
              if (m != current)
                NxButton(
                  label: switch (m) {
                    'TOTP' => on ? 'Switch to an authenticator app' : 'Use an authenticator app',
                    'EMAIL' => on ? 'Switch to email codes' : 'Use email codes',
                    _ => on ? 'Switch to SMS codes' : 'Use SMS codes',
                  },
                  icon: icon(m),
                  onPressed: _busy || (m == 'SMS' && !hasPhone) ? null : () => _setUp(m),
                ),
            if (on) NxButton.ghost(label: 'Turn off', color: n.bad, onPressed: _busy ? null : _turnOff),
          ],
        ),
        if (!hasPhone) ...[
          const SizedBox(height: 8),
          Text('Add a mobile number under Contact & alerts to use SMS codes.', style: TextStyle(fontSize: 12, color: n.n500)),
        ],
        if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: TextStyle(fontSize: 12, color: n.bad))],
      ],
    );
  }
}

/// Set-up dialog: QR + key for an app, or "code sent to …", then the code
/// that proves it works. Pops `true` once switched on.
class _MfaSetup extends ConsumerStatefulWidget {
  const _MfaSetup({required this.start, required this.method});

  final MfaSetupStart start;
  final String method;

  @override
  ConsumerState<_MfaSetup> createState() => _MfaSetupState();
}

class _MfaSetupState extends ConsumerState<_MfaSetup> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
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
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (e) {
      setState(() {
        _error = e.message;
        _busy = false;
      });
      _code.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final s = widget.start;
    final isApp = s.channel == 'TOTP';
    final body = TextStyle(fontSize: 13, color: n.text.withValues(alpha: 0.85), height: 1.5);
    return NxDialogFrame(
      title: 'Set up ${kMfaMethodLabels[widget.method]}',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isApp && s.otpauthUrl != null) ...[
            Text('1. Scan this with your authenticator app.', style: body),
            const SizedBox(height: 8),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  width: 190,
                  height: 190,
                  child: QrImageView(data: s.otpauthUrl!, size: 190, backgroundColor: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('Can’t scan? Enter this key in the app instead:', style: TextStyle(fontSize: 12, color: n.n400)),
            SelectableText(s.secret ?? '', style: TextStyle(fontFamily: 'monospace', fontSize: 15, letterSpacing: 2, color: n.text)),
            const SizedBox(height: 12),
            Text('2. Enter the 6-digit code the app now shows.', style: body),
          ] else
            Text('We sent a 6-digit code to ${s.destination}. Enter it to switch this on.', style: body),
          const SizedBox(height: 8),
          NxInput(
            controller: _code,
            autofocus: true,
            enabled: !_busy,
            placeholder: '000000',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            error: _error != null,
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null) ...[const SizedBox(height: 6), Text(_error!, style: TextStyle(fontSize: 12, color: n.bad))],
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
        NxButton.primary(label: _busy ? 'Checking…' : 'Turn on', onPressed: _busy ? null : _confirm),
      ],
    );
  }
}

/// Password: self-service change (proves the current one).
class PasswordSection extends ConsumerStatefulWidget {
  const PasswordSection({super.key});

  @override
  ConsumerState<PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends ConsumerState<PasswordSection> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final Map<String, String> _errors = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final errors = <String, String>{
      if (_current.text.isEmpty) 'current': 'Enter your current password',
      if (_next.text.length < 8) 'next': 'At least 8 characters',
      if (_confirm.text != _next.text) 'confirm': 'The passwords don’t match',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(usersApiProvider).changeOwnPassword(currentPassword: _current.text, newPassword: _next.text);
      for (final c in [_current, _next, _confirm]) {
        c.clear();
      }
      NxToast.ok('Password changed');
    } on AppError catch (e) {
      setState(() => _errors['current'] = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsHead('Password'),
        SettingsNarrow(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxField(
                label: 'Current password',
                error: _errors['current'],
                child: NxInput(controller: _current, obscure: true, enabled: !_saving, error: _errors['current'] != null),
              ),
              const SizedBox(height: 12),
              NxField(
                label: 'New password',
                error: _errors['next'],
                hint: 'At least 8 characters.',
                child: NxInput(controller: _next, obscure: true, enabled: !_saving, error: _errors['next'] != null),
              ),
              const SizedBox(height: 12),
              NxField(
                label: 'Confirm new password',
                error: _errors['confirm'],
                child: NxInput(controller: _confirm, obscure: true, enabled: !_saving, error: _errors['confirm'] != null, onSubmitted: (_) => _submit()),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: NxButton.primary(label: _saving ? 'Saving…' : 'Change password', icon: PhosphorIconsRegular.lockSimple, onPressed: _saving ? null : _submit),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
