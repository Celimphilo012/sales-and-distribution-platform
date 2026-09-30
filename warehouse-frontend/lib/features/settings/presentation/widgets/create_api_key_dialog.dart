import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/theme/nocturne.dart';
import '../../../../shared/nx/nx_form.dart';
import '../../../../shared/nx/nx_overlays.dart';
import '../../../../shared/nx/nx_primitives.dart';
import '../../data/api_keys_providers.dart';
import '../../domain/api_key.dart';

/// Name + scopes. Returns the [ApiKeyCreated] result (with the one-time raw
/// key) so the CALLER reveals it — create and reveal stay two steps.
Future<ApiKeyCreated?> showCreateApiKeyDialog(BuildContext context) =>
    showNxDialog<ApiKeyCreated>(context, builder: (_) => const _CreateApiKey());

class _CreateApiKey extends ConsumerStatefulWidget {
  const _CreateApiKey();

  @override
  ConsumerState<_CreateApiKey> createState() => _CreateApiKeyState();
}

class _CreateApiKeyState extends ConsumerState<_CreateApiKey> {
  final _name = TextEditingController();
  Set<String> _scopes = {'stock:read'};
  final Map<String, String> _errors = {};
  bool _saving = false;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final errors = <String, String>{
      if (_name.text.trim().isEmpty) 'name': 'Required',
      if (_scopes.isEmpty) 'scopes': 'Pick at least one scope',
    };
    setState(() {
      _errors
        ..clear()
        ..addAll(errors);
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _saving = true);
    try {
      final created = await ref.read(apiKeysApiProvider).create(name: _name.text.trim(), scopes: _scopes.toList());
      if (mounted) Navigator.of(context).pop(created);
    } on AppError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxDialogFrame(
      title: 'New API key',
      sub: 'The raw key is shown once, right after creation.',
      body: NxFormGrid(
        children: [
          NxSpan2(
            child: NxField(
              label: 'Name',
              required: true,
              error: _errors['name'],
              child: NxInput(controller: _name, placeholder: 'Back-office ordering', autofocus: true, error: _errors['name'] != null),
            ),
          ),
          NxSpan2(
            child: NxField(
              label: 'Scopes',
              required: true,
              error: _errors['scopes'],
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in kApiKeyScopes)
                    NxChipToggle(
                      label: s,
                      selected: _scopes.contains(s),
                      showCheck: true,
                      onTap: () => setState(() => _scopes = _scopes.contains(s) ? ({..._scopes}..remove(s)) : {..._scopes, s}),
                    ),
                ],
              ),
            ),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Creating…' : 'Create key', onPressed: _saving ? null : _create),
      ],
    );
  }
}
