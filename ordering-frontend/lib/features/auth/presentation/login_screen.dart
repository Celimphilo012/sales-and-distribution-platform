import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_shell/branding.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/otp_confirm_dialog.dart';

/// Real login form, posting to `/auth/login` via [AuthNotifier.login]. When the
/// account has sign-in verification on, the form is replaced by [_MfaStep].
/// On success, go_router's redirect (reacting to [authProvider]) moves the
/// user off this route on its own — this screen never navigates manually.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await ref
        .read(authProvider.notifier)
        .login(email: _emailController.text.trim(), password: _passwordController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;
    final error = authState.hasError ? authState.error : null;
    final mfa = authState.value?.mfa;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The company's logo, name and tagline (Settings → Branding).
                  const BrandMark(size: 56, glow: true),
                  const SizedBox(height: AppSpacing.md),
                  Text(ref.watch(brandNameProvider), textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ref.watch(brandTaglineProvider) ?? 'Back Office',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ref.watch(brandTaglineProvider) == null ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: mfa != null
                          ? _MfaStep(key: ValueKey(mfa.challengeId), challenge: mfa)
                          : Column(
                              children: [
                                AppTextField(
                                  label: 'Email',
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  enabled: !isLoading,
                                  prefixIcon: Icons.email_outlined,
                                  validator: (value) {
                                    final email = value?.trim() ?? '';
                                    if (email.isEmpty) return 'Enter your email';
                                    if (!email.contains('@')) return 'Enter a valid email';
                                    return null;
                                  },
                                ),
                                const SizedBox(height: AppSpacing.md),
                                AppTextField(
                                  label: 'Password',
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  enabled: !isLoading,
                                  prefixIcon: Icons.lock_outline,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) return 'Enter your password';
                                    return null;
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton.icon(
                                    onPressed: isLoading
                                        ? null
                                        : () => setState(() => _obscurePassword = !_obscurePassword),
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    ),
                                    label: Text(_obscurePassword ? 'Show password' : 'Hide password'),
                                  ),
                                ),
                                if (error != null) ...[
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(AppSpacing.sm),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                                    ),
                                    child: Text(
                                      error is AppError ? error.message : 'Something went wrong. Please try again.',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                ],
                                const SizedBox(height: AppSpacing.sm),
                                FilledButton.icon(
                                  onPressed: isLoading ? null : _submit,
                                  icon: isLoading
                                      ? SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: theme.colorScheme.onPrimary,
                                          ),
                                        )
                                      : const Icon(Icons.login),
                                  label: Text(isLoading ? 'Signing in…' : 'Sign in'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The second sign-in step: the code from email/SMS or the authenticator app.
class _MfaStep extends ConsumerStatefulWidget {
  const _MfaStep({super.key, required this.challenge});

  final MfaChallenge challenge;

  @override
  ConsumerState<_MfaStep> createState() => _MfaStepState();
}

class _MfaStepState extends ConsumerState<_MfaStep> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? notice}) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
      if (mounted && notice != null) setState(() => _notice = notice);
    } on AppError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    await _run(() => ref.read(authProvider.notifier).verifyMfa(code));
    if (mounted && _error != null) _codeController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final challenge = widget.challenge;
    final isApp = challenge.channel == 'TOTP';
    final others = challenge.availableChannels.where((c) => c != challenge.channel && c != 'TOTP').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Enter your sign-in code', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isApp
              ? 'Open your authenticator app and enter the 6-digit code it shows for this account.'
              : 'We sent a 6-digit code to ${challenge.destination}. It expires in 10 minutes.',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _codeController,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: '6-digit code', counterText: '', border: OutlineInputBorder()),
          onSubmitted: (_) => _verify(),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
        if (_notice != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(_notice!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: _busy ? null : _verify,
          icon: const Icon(Icons.verified_user_outlined),
          label: Text(_busy ? 'Checking…' : 'Verify and sign in'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          children: [
            if (!isApp)
              TextButton(
                onPressed: _busy
                    ? null
                    : () =>
                          _run(() => ref.read(authProvider.notifier).resendMfa(), notice: 'A new code is on its way.'),
                child: const Text('Send a new code'),
              ),
            for (final channel in others)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(
                        () => ref.read(authProvider.notifier).resendMfa(channel: channel),
                        notice: 'Code sent by ${kOtpChannelLabels[channel] ?? channel}.',
                      ),
                child: Text('Send it by ${kOtpChannelLabels[channel] ?? channel} instead'),
              ),
            TextButton(
              onPressed: _busy ? null : () => ref.read(authProvider.notifier).cancelMfa(),
              child: const Text('Back'),
            ),
          ],
        ),
      ],
    );
  }
}
