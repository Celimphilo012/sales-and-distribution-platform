import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../shared/widgets/app_dialog.dart';
import '../../../../shared/widgets/app_multi_select_list.dart';
import '../../../../shared/widgets/app_text_field.dart';
import '../../data/api_keys_providers.dart';
import '../../domain/api_key.dart';

/// Name + scope selection. Returns the [ApiKeyCreated] result (including the
/// one-time raw key) so the CALLER decides how to reveal it — this dialog
/// itself never displays the raw key, keeping "create" and "reveal" as two
/// distinct, single-purpose steps.
Future<ApiKeyCreated?> showCreateApiKeyDialog(BuildContext context) {
  return showDialog<ApiKeyCreated>(context: context, builder: (context) => const _CreateApiKeyDialog());
}

class _CreateApiKeyDialog extends ConsumerStatefulWidget {
  const _CreateApiKeyDialog();

  @override
  ConsumerState<_CreateApiKeyDialog> createState() => _CreateApiKeyDialogState();
}

class _CreateApiKeyDialogState extends ConsumerState<_CreateApiKeyDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final Set<String> _selectedScopes = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_selectedScopes.isEmpty) {
      setState(() => _error = 'Choose at least one scope.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final created = await ref
          .read(apiKeysApiProvider)
          .create(name: _nameController.text.trim(), scopes: _selectedScopes.toList());
      if (mounted) Navigator.of(context, rootNavigator: true).pop(created);
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
      title: 'New API key',
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(
              label: 'Name',
              controller: _nameController,
              hintText: 'Back-office integration',
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Scopes', style: theme.textTheme.labelLarge),
            AppMultiSelectList<String>(
              items: kApiKeyScopes,
              selectedIds: _selectedScopes,
              idOf: (s) => s,
              labelOf: (s) => s,
              onToggle: (scope, selected) => setState(() {
                if (selected) {
                  _selectedScopes.add(scope);
                } else {
                  _selectedScopes.remove(scope);
                }
              }),
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
        FilledButton(onPressed: _saving ? null : _create, child: Text(_saving ? 'Creating…' : 'Create')),
      ],
    );
  }
}
