import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_dialog.dart';

/// Prompts for a review note before approving/rejecting an adjustment.
/// Returns the trimmed note, or `null` if the user cancelled. When
/// [required] is true (rejects — `RejectAdjustmentDto.reviewNote` is
/// mandatory on the backend) an empty note shows an inline error instead of
/// closing the dialog; approvals leave it optional, matching
/// `ApproveAdjustmentDto.reviewNote`.
Future<String?> showReviewNoteDialog(
  BuildContext context, {
  required String title,
  required String actionLabel,
  required bool required,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ReviewNoteDialog(title: title, actionLabel: actionLabel, required: required),
  );
}

class _ReviewNoteDialog extends StatefulWidget {
  const _ReviewNoteDialog({required this.title, required this.actionLabel, required this.required});

  final String title;
  final String actionLabel;
  final bool required;

  @override
  State<_ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<_ReviewNoteDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _controller.text.trim();
    if (widget.required && text.isEmpty) {
      setState(() => _error = 'A review note is required.');
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: widget.title,
      content: TextField(
        controller: _controller,
        maxLines: 3,
        autofocus: true,
        decoration: InputDecoration(
          labelText: widget.required ? 'Review note (required)' : 'Review note (optional)',
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context, rootNavigator: true).pop(), child: const Text('Cancel')),
        const SizedBox(width: AppSpacing.xs),
        FilledButton(onPressed: _confirm, child: Text(widget.actionLabel)),
      ],
    );
  }
}
