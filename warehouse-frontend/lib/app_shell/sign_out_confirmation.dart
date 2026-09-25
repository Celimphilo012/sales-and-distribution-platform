import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_provider.dart';
import '../shared/widgets/app_dialog.dart';

/// Shared by every "Sign out" control (the sidebar button, and the top
/// bar's avatar menu) so confirming — or not — behaves identically no
/// matter which one was used. A no-op if the user cancels.
Future<void> confirmAndSignOut(BuildContext context, WidgetRef ref) async {
  final confirmed = await ConfirmDialog.show(
    context,
    title: 'Sign out?',
    message: "You'll need to sign in again to keep working.",
    confirmLabel: 'Sign out',
    isDestructive: true,
  );
  if (confirmed) ref.read(authProvider.notifier).logout();
}
