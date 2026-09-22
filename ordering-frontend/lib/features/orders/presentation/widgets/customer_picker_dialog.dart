import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../customers/domain/customer.dart';
import 'customer_picker_field.dart';

/// Opens the customer search in a dialog and resolves with the picked
/// customer, or `null` if dismissed.
Future<Customer?> showCustomerPickerDialog(BuildContext context) {
  return showDialog<Customer>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Choose a customer', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: CustomerSearchField(
                    onSelected: (customer) => Navigator.of(context, rootNavigator: true).pop(customer),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
