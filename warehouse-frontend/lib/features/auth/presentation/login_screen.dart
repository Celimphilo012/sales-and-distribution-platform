import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/branding.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/error/app_error.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/otp_confirm_dialog.dart';

/// Real login form, posting to `/auth/login` via [AuthNotifier.login]. When the
/// account has sign-in verification on, the form is replaced by [_MfaStep].
/// On success, go_router's redirect (reacting to [authProvider]) moves the
/// user off this route on its own — this screen never navigates manually.
///
/// Wide screens get the split "masthead + credentials" layout; narrow ones
/// collapse to a single column with the brand on top.
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
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = constraints.maxWidth >= Breakpoints.tabletMax - 100;
          if (!split) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _BrandMark(),
                          const SizedBox(height: AppSpacing.lg),
                          _BrandName(style: Theme.of(context).textTheme.headlineSmall),
                          const _Tagline(),
                          const SizedBox(height: AppSpacing.xl),
                          _body(context),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Row(
            children: [
              Expanded(flex: 5, child: const _Masthead()),
              Expanded(
                flex: 4,
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: _body(context)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context) {
    final mfa = ref.watch(authProvider).value?.mfa;
    return mfa == null ? _form(context) : _MfaStep(challenge: mfa);
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final authState = ref.watch(authProvider);
    final isLoading = authState.isLoading;
    final error = authState.hasError ? authState.error : null;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'STAFF ACCESS',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.8, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('Warehouse credentials', style: theme.textTheme.headlineMedium),
          const SizedBox(height: AppSpacing.lg),
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
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: isLoading ? null : () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
              label: Text(_obscurePassword ? 'Show password' : 'Hide password'),
            ),
          ),
          if (error != null) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                border: Border(left: BorderSide(color: scheme.error, width: 3)),
              ),
              child: Text(
                error is AppError ? error.message : 'Something went wrong. Please try again.',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.xs),
          FilledButton.icon(
            onPressed: isLoading ? null : _submit,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            icon: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                  )
                : const PhosphorIcon(PhosphorIconsBold.signIn, size: 18),
            label: Text(isLoading ? 'Signing in…' : 'Sign in'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              border: Border(left: BorderSide(color: context.semanticColors.warning, width: 3)),
            ),
            child: Text(
              'Access is restricted to authorised warehouse staff. Sign-ins and every stock movement are recorded.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// Second sign-in step: the code from email/SMS or the authenticator app.
/// Loading and errors are local — a wrong code keeps this step on screen.
class _MfaStep extends ConsumerStatefulWidget {
  const _MfaStep({required this.challenge});

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
        Text(
          'SIGN-IN VERIFICATION',
          style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1.8, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Enter your code', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isApp
              ? 'Open your authenticator app and enter the 6-digit code it shows for this account.'
              : 'We sent a 6-digit code to ${challenge.destination}. It expires in 10 minutes.',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _codeController,
          autofocus: true,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: const InputDecoration(labelText: '6-digit code', counterText: ''),
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
        FilledButton(
          onPressed: _busy ? null : _verify,
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          child: Text(_busy ? 'Checking…' : 'Verify and sign in'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            if (!isApp)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => ref.read(authProvider.notifier).resendMfa(), notice: 'A new code is on its way.'),
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

/// The company logo (Settings → Branding), or the built-in warehouse mark.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) => const BrandMark(size: 56);
}

/// The company name, or the product name while none is set.
class _BrandName extends ConsumerWidget {
  const _BrandName({this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(ref.watch(brandNameProvider), style: style);
}

/// The company tagline (Settings → Branding), in the brand colour; nothing when unset.
class _Tagline extends ConsumerWidget {
  const _Tagline({this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagline = ref.watch(brandTaglineProvider);
    if (tagline == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Text(tagline, style: style ?? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// The left-hand masthead on wide screens.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          const _BrandMark(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'SALES & DISTRIBUTION',
            style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 3, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _BrandName(style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.1)),
          ),
          _Tagline(style: theme.textTheme.titleMedium?.copyWith(color: scheme.primary)),
          const SizedBox(height: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              'The catalogue, the location tree and the stock ledger — receiving, transfers, counts and '
              'approved adjustments, each one recorded.',
              style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const Spacer(),
          Text(
            'Authorised users only. All access is logged.',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
