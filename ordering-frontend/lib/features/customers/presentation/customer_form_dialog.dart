import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';

/// Create (no [customer]) or edit (pass [customer]) a customer. A dialog is
/// enough — customers have few fields (§E: name, phone, address, location,
/// notes), same call as the warehouse app's category-management dialog.
/// The backend enforces no phone FORMAT (`CreateCustomerDto.phone` is a
/// plain optional string), so this doesn't fake one either — just presence
/// of `name`.
Future<void> showCustomerFormDialog(BuildContext context, {Customer? customer}) {
  return showDialog<void>(context: context, builder: (context) => _CustomerFormDialog(customer: customer));
}

class _CustomerFormDialog extends ConsumerStatefulWidget {
  const _CustomerFormDialog({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameController = TextEditingController(text: c?.name ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _addressController = TextEditingController(text: c?.address ?? '');
    _locationController = TextEditingController(text: c?.locationText ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final api = ref.read(customersApiProvider);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();
    final location = _locationController.text.trim();
    final notes = _notesController.text.trim();
    try {
      if (_isEditing) {
        await api.update(
          widget.customer!.id,
          name: name,
          phone: phone,
          address: address,
          locationText: location,
          notes: notes,
        );
        invalidateCustomer(ref, widget.customer!.id);
      } else {
        await api.create(name: name, phone: phone, address: address, locationText: location, notes: notes);
        invalidateCustomers(ref);
      }
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
      title: _isEditing ? 'Edit customer' : 'New customer',
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(
                label: 'Name',
                controller: _nameController,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Phone (optional)',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                hintText: '+268 7612 3456',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'Address (optional)', controller: _addressController),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                label: 'Location (optional)',
                controller: _locationController,
                hintText: 'Area, landmark, GPS note…',
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(label: 'Notes (optional)', controller: _notesController, maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
