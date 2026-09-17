import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_number_field.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/locations_providers.dart';
import '../domain/location.dart';

/// "Create N levels" (§G): a SHORTCUT that bulk-creates N sibling child
/// locations under [parent] in one call — never a fixed template. There is
/// deliberately no cap on the count field here, matching the real
/// `CreateLevelsDto` (`count` has no upper bound). After this runs, the
/// created locations are perfectly ordinary locations: addable-to,
/// renameable, movable, deactivatable, and you can generate more (or a
/// single one-off child) under the same parent again — nothing about this
/// action locks the structure.
Future<void> showGenerateLevelsDialog(BuildContext context, {required Location parent}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _GenerateLevelsDialog(parent: parent),
  );
}

class _GenerateLevelsDialog extends ConsumerStatefulWidget {
  const _GenerateLevelsDialog({required this.parent});

  final Location parent;

  @override
  ConsumerState<_GenerateLevelsDialog> createState() => _GenerateLevelsDialogState();
}

class _GenerateLevelsDialogState extends ConsumerState<_GenerateLevelsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController(text: '5');
  final _typeController = TextEditingController(text: 'LEVEL');
  final _namePrefixController = TextEditingController(text: 'Level');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _countController.dispose();
    _typeController.dispose();
    _namePrefixController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(locationsApiProvider).generateLevels(
        widget.parent.id,
        count: int.parse(_countController.text.trim()),
        locationType: _typeController.text.trim().isEmpty ? null : _typeController.text.trim(),
        namePrefix: _namePrefixController.text.trim().isEmpty ? null : _namePrefixController.text.trim(),
      );
      invalidateWarehouseLocations(ref, widget.parent.warehouseId);
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } on AppError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppDialog(
      title: 'Create levels under "${widget.parent.name}"',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppNumberField(
              label: 'How many',
              controller: _countController,
              helperText: 'No limit — you can always add more (or fewer) afterwards',
              validator: (v) {
                final n = int.tryParse(v ?? '');
                if (n == null || n < 1) return 'Enter a whole number of 1 or more';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(label: 'Type', controller: _typeController),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Name prefix',
              controller: _namePrefixController,
              helperText: 'Each new location is named "{prefix} {n}"',
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Creating…' : 'Create')),
      ],
    );
  }
}
