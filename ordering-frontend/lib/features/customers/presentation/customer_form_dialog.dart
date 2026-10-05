import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../users/data/users_providers.dart';
import '../data/customers_providers.dart';
import '../domain/customer.dart';

/// New / edit customer (name, phone, address, location, notes). Returns the
/// saved customer (null when cancelled) so a caller — the order form — can
/// pick a customer it just created.
Future<Customer?> showCustomerFormDialog(BuildContext context, {Customer? customer}) =>
    showNxDialog<Customer>(context, width: 560, builder: (_) => _CustomerForm(customer: customer));

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({this.customer});

  final Customer? customer;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  late final _name = TextEditingController(text: widget.customer?.name ?? '');
  late final _phone = TextEditingController(text: widget.customer?.phone ?? '');
  late final _address = TextEditingController(text: widget.customer?.address ?? '');
  late final _location = TextEditingController(text: widget.customer?.locationText ?? '');
  late final _notes = TextEditingController(text: widget.customer?.notes ?? '');
  late String? _assignedConsultantId;
  String? _nameErr;
  String? _formError;
  bool _saving = false;

  bool get _editing => widget.customer != null;

  @override
  void initState() {
    super.initState();
    _assignedConsultantId = widget.customer?.assignedConsultantId;
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _location, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameErr = 'Required');
      return;
    }
    setState(() {
      _saving = true;
      _nameErr = null;
      _formError = null;
    });
    final api = ref.read(customersApiProvider);
    try {
      final Customer saved;
      if (_editing) {
        saved = await api.update(
          widget.customer!.id,
          name: name,
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          locationText: _location.text.trim(),
          notes: _notes.text.trim(),
          assignedConsultantId: _assignedConsultantId,
        );
        invalidateCustomer(ref, saved.id);
      } else {
        saved = await api.create(
          name: name,
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          locationText: _location.text.trim(),
          notes: _notes.text.trim(),
          assignedConsultantId: _assignedConsultantId,
        );
        invalidateCustomers(ref);
      }
      if (mounted) Navigator.of(context).pop(saved);
      NxToast.ok(_editing ? 'Customer updated' : 'Customer added', saved.name);
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
      title: _editing ? 'Edit customer' : 'New customer',
      sub: 'Customers live in the ordering system only.',
      body: NxFormGrid(
        children: [
          NxField(label: 'Name', required: true, error: _nameErr, child: NxInput(controller: _name, autofocus: true, error: _nameErr != null)),
          NxField(label: 'Phone', child: NxInput(controller: _phone, placeholder: '+268 7612 3456', keyboardType: TextInputType.phone)),
          NxSpan2(child: NxField(label: 'Address', child: NxInput(controller: _address))),
          NxSpan2(child: NxField(label: 'Location', hint: 'Area, landmark or GPS note — helps delivery', child: NxInput(controller: _location))),
          NxSpan2(child: NxField(label: 'Notes', child: NxInput(controller: _notes, maxLines: 3, minLines: 2))),
          NxSpan2(
            child: NxField(
              label: 'Assigned consultant',
              hint: 'Whose book this customer belongs to — drives eligibility for consultant-restricted sale campaigns',
              child: Consumer(
                builder: (context, ref, _) {
                  final consultants = ref.watch(consultantsListProvider).value ?? const [];
                  return NxSelect<String>(
                    options: [for (final c in consultants) NxOption(c.id, c.fullName)],
                    value: _assignedConsultantId,
                    searchable: consultants.length > 8,
                    emptyLabel: 'None',
                    placeholder: 'No consultant assigned',
                    onChanged: (v) => setState(() => _assignedConsultantId = v),
                  );
                },
              ),
            ),
          ),
          if (_formError != null) NxSpan2(child: Text(_formError!, style: TextStyle(fontSize: 12, color: n.bad))),
        ],
      ),
      actions: [
        NxButton(label: 'Cancel', onPressed: _saving ? null : () => Navigator.of(context).pop()),
        NxButton.primary(label: _saving ? 'Saving…' : (_editing ? 'Save changes' : 'Add customer'), onPressed: _saving ? null : _save),
      ],
    );
  }
}
