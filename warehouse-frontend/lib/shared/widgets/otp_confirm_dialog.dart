import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/error/error_mapper.dart';
import '../../core/network/otp_interceptor.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/ui/root_navigator_key.dart';
import 'app_dialog.dart';

/// Labels for the one-time-code channels the backend offers.
const Map<String, String> kOtpChannelLabels = {
  'EMAIL': 'Email',
  'SMS': 'SMS',
  'TOTP': 'Authenticator app',
};

/// [OtpPrompt] implementation for [OtpInterceptor]: shows [OtpConfirmDialog]
/// on the root navigator, above whatever screen raised the request.
Future<bool> showOtpPrompt(OtpRequirement requirement, OtpCodeRequester requestCode, OtpAttempt attempt) async {
  final context = rootNavigatorKey.currentContext;
  if (context == null) return false;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => OtpConfirmDialog(requirement: requirement, requestCode: requestCode, attempt: attempt),
  );
  return confirmed ?? false;
}

/// "Confirm with a one-time code": pick a channel (email / SMS / authenticator
/// app), get a code, type it in. The code is checked by re-sending the
/// original request (see [OtpInterceptor]); a wrong code shows inline so the
/// user can retry without starting over.
class OtpConfirmDialog extends StatefulWidget {
  const OtpConfirmDialog({super.key, required this.requirement, required this.requestCode, required this.attempt});

  final OtpRequirement requirement;
  final OtpCodeRequester requestCode;
  final OtpAttempt attempt;

  @override
  State<OtpConfirmDialog> createState() => _OtpConfirmDialogState();
}

class _OtpConfirmDialogState extends State<OtpConfirmDialog> {
  final _codeController = TextEditingController();
  late String _channel = widget.requirement.defaultChannel;
  OtpChallenge? _challenge;
  bool _sending = false;
  bool _confirming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The authenticator app needs nothing sent — open its challenge straight away.
    if (_channel == 'TOTP') _send();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final challenge = await widget.requestCode(_channel);
      if (!mounted) return;
      setState(() => _challenge = challenge);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = ErrorMapper.fromDioException(e).message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _confirm() async {
    final challenge = _challenge;
    final code = _codeController.text.trim();
    if (challenge == null || code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() {
      _confirming = true;
      _error = null;
    });
    final problem = await widget.attempt(challenge.challengeId, code);
    if (!mounted) return;
    if (problem == null) {
      Navigator.of(context, rootNavigator: true).pop(true);
      return;
    }
    setState(() {
      _confirming = false;
      _error = problem;
      _codeController.clear();
    });
  }

  void _switchChannel(String channel) {
    setState(() {
      _channel = channel;
      _challenge = null;
      _error = null;
      _codeController.clear();
    });
    if (channel == 'TOTP') _send();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channels = widget.requirement.availableChannels;
    final busy = _sending || _confirming;
    final challenge = _challenge;

    return AppDialog(
      title: 'Confirm with a one-time code',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.requirement.message, style: theme.textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.md),
          if (channels.length > 1) ...[
            Text('Get the code by', style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<String>(
              segments: [
                for (final c in channels) ButtonSegment(value: c, label: Text(kOtpChannelLabels[c] ?? c)),
              ],
              selected: {_channel},
              onSelectionChanged: busy ? null : (selection) => _switchChannel(selection.first),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_channel != 'TOTP')
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_outlined, size: 18),
                label: Text(challenge == null ? 'Send code' : 'Send a new code'),
              ),
            ),
          if (challenge != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _channel == 'TOTP'
                  ? 'Enter the 6-digit code shown in your authenticator app.'
                  : 'Code sent to ${challenge.destination}. It expires in 10 minutes.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _codeController,
              autofocus: true,
              enabled: !_confirming,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
              decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
              onSubmitted: (_) => _confirm(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _confirming ? null : () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || challenge == null ? null : _confirm,
          child: _confirming
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                )
              : const Text('Confirm'),
        ),
      ],
    );
  }
}
