import 'package:flutter/material.dart';

import '../../core/theme/nocturne.dart';
import '../nx/nx_overlays.dart';

/// Generic dialog chrome in the console's style (the same look as
/// [NxDialogFrame]): title, scrollable body, action row on a raised surface.
/// Feature dialogs wrap their content in this — whether shown through
/// [AppDialog.show] or a plain `showDialog` — so every dialog matches.
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, required this.title, required this.content, this.actions = const [], this.maxWidth = 480});

  final String title;
  final Widget content;
  final List<Widget> actions;

  /// Most dialogs are simple forms; a content-heavy one can ask for more room.
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
    final n = context.nx;
    return Dialog(
      backgroundColor: n.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(NxRadius.lg)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth + 28),
        child: NxDialogFrame(title: title, body: content, actions: actions),
      ),
    );
  }
}

/// A yes/no confirmation for destructive or hard-to-reverse actions. Returns
/// `true` only if the user picked the confirm action.
class ConfirmDialog {
  const ConfirmDialog._();

  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    bool isDestructive = false,
  }) => showNxConfirm(context, title: title, body: message, confirmLabel: confirmLabel, danger: isDestructive);
}
