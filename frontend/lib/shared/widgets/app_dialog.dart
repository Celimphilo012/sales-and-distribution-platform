import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Generic dialog chrome: title, scrollable body, action row. Feature
/// dialogs wrap their content in this instead of building [AlertDialog]
/// from scratch each time, so dialog sizing/padding stays consistent.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.content, this.actions = const []});

  final String title;
  final Widget content;
  final List<Widget> actions;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget> actions = const [],
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AppDialog(title: title, content: content, actions: actions),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: content),
      actionsPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      actions: actions,
    );
  }
}

/// A yes/no confirmation dialog for destructive or hard-to-reverse actions
/// (reject an order, delete a draft, etc). Returns `true` only if the user
/// picked the confirm action.
class ConfirmDialog {
  const ConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) async {
    final theme = Theme.of(context);
    final result = await AppDialog.show<bool>(
      context,
      title: title,
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(cancelLabel)),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
    return result ?? false;
  }
}
