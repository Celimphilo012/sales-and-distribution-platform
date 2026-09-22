import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/responsive/breakpoints.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_text_field.dart';

/// Real login form, posting to `/auth/login` via [AuthNotifier.login].
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
                          Text('Warehouse System', style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: AppSpacing.xl),
                          _form(context),
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
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 400), child: _form(context)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
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

/// A square primary tile with the warehouse glyph — the app's logo mark.
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      color: scheme.primary,
      child: PhosphorIcon(PhosphorIconsBold.warehouse, size: 30, color: scheme.onPrimary),
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
            child: Text(
              'Warehouse System',
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, height: 1.1),
            ),
          ),
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
