import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';

/// Generic dialog chrome: title, scrollable body, action row. Feature
/// dialogs wrap their content in this instead of building [AlertDialog]
/// from scratch each time, so dialog sizing/padding stays consistent.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.content, this.actions = const [], this.maxWidth = 480});

  final String title;
  final Widget content;
  final List<Widget> actions;

  /// Most dialogs are simple forms and fit the default 480; a content-heavy
  /// one (a product's full detail, say) can ask for more room.
  final double maxWidth;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    List<Widget> actions = const [],
    double maxWidth = 480,
  }) {
    return showDialog<T>(
      context: context,
      builder: (context) => AppDialog(title: title, content: content, actions: actions, maxWidth: maxWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      // `scrollable: true` wraps title+content in a SingleChildScrollView —
      // without it, AlertDialog's content area has no height limit of its
      // own and no scrolling, so a dialog with enough fields (or a small
      // viewport, e.g. a laptop screen with a tall form) silently overflows
      // instead of scrolling. This is shared chrome every dialog in the app
      // goes through, so the fix applies everywhere at once.
      scrollable: true,
      content: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: content),
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
    // AppDialog.show uses showDialog's default useRootNavigator: true, so the
    // dialog route lives on the ROOT Navigator. The caller's `context` here
    // is almost always a descendant of go_router's ShellRoute, which nests
    // its OWN Navigator — plain `Navigator.of(context).pop()` resolves to
    // THAT shell Navigator instead, popping the current page's route (not
    // the dialog) and crashing with go_router's "popped the last page off
    // of the stack" assertion. `rootNavigator: true` targets the same
    // Navigator the dialog actually lives on, regardless of what's nested
    // between this context and the root.
    final result = await AppDialog.show<bool>(
      context,
      title: title,
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(backgroundColor: theme.colorScheme.error, foregroundColor: theme.colorScheme.onError)
              : null,
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
    return result ?? false;
  }
}
