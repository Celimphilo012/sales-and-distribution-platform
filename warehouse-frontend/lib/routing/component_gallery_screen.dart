import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_spacing.dart';
import '../core/theme/theme_mode_provider.dart';
import '../shared/widgets/app_card.dart';
import '../shared/widgets/app_data_table.dart';
import '../shared/widgets/app_dialog.dart';
import '../shared/widgets/app_dropdown_field.dart';
import '../shared/widgets/app_number_field.dart';
import '../shared/widgets/app_text_field.dart';
import '../shared/widgets/coming_soon_view.dart';
import '../shared/widgets/empty_loading_error_states.dart';
import '../shared/widgets/status_badge.dart';

class _SampleRow {
  const _SampleRow(this.sku, this.name, this.onHand, this.status);
  final String sku;
  final String name;
  final int onHand;
  final StatusTone status;
}

const _sampleRows = [
  _SampleRow('SKU-001', 'Steel Bracket', 240, StatusTone.success),
  _SampleRow('SKU-002', 'Copper Wire 2mm', 12, StatusTone.warning),
  _SampleRow('SKU-003', 'Hex Bolt M6', 0, StatusTone.danger),
];

/// Hidden dev-only route (`/dev/components`) demonstrating every shared
/// widget shell in one place, in both light and dark theme via the toggle
/// in the app bar. Not linked from nav — reachable by URL only.
class ComponentGalleryScreen extends ConsumerWidget {
  const ComponentGalleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Component Gallery'),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            title: 'Status badges',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: const [
                StatusBadge(label: 'Draft', tone: StatusTone.neutral),
                StatusBadge(label: 'Approved', tone: StatusTone.success),
                StatusBadge(label: 'Low stock', tone: StatusTone.warning),
                StatusBadge(label: 'Rejected', tone: StatusTone.danger),
                StatusBadge(label: 'In transit', tone: StatusTone.info),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            title: 'Buttons',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Filled')),
                OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
                TextButton(onPressed: () {}, child: const Text('Text')),
                FilledButton.icon(onPressed: () {}, icon: const Icon(Icons.add), label: const Text('With icon')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            title: 'Form fields',
            child: Column(
              children: [
                const AppTextField(label: 'Product name', hintText: 'e.g. Steel Bracket'),
                const SizedBox(height: AppSpacing.md),
                AppNumberField(label: 'Quantity', allowDecimal: false),
                const SizedBox(height: AppSpacing.md),
                AppDropdownField<String>(
                  label: 'Warehouse',
                  value: 'main',
                  items: const ['main', 'north', 'south'],
                  itemLabel: (v) => v,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            title: 'Data table',
            subtitle: 'Renders as a DataTable on desktop, cards on mobile',
            child: SizedBox(
              height: 260,
              child: AppDataTable<_SampleRow>(
                rows: _sampleRows,
                columns: [
                  AppDataColumn(label: 'SKU', cellBuilder: (r) => Text(r.sku)),
                  AppDataColumn(label: 'Name', cellBuilder: (r) => Text(r.name)),
                  AppDataColumn(label: 'On hand', numeric: true, cellBuilder: (r) => Text('${r.onHand}')),
                  AppDataColumn(
                    label: 'Status',
                    cellBuilder: (r) => StatusBadge(
                      label: switch (r.status) {
                        StatusTone.success => 'In stock',
                        StatusTone.warning => 'Low stock',
                        StatusTone.danger => 'Out of stock',
                        _ => 'Unknown',
                      },
                      tone: r.status,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            title: 'Dialogs',
            child: Wrap(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  onPressed: () => AppDialog.show(
                    context,
                    title: 'Generic dialog',
                    content: const Text('Any content can go here.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
                    ],
                  ),
                  child: const Text('Show dialog'),
                ),
                OutlinedButton(
                  onPressed: () => ConfirmDialog.show(
                    context,
                    title: 'Reject order?',
                    message: 'This cannot be undone.',
                    confirmLabel: 'Reject',
                    isDestructive: true,
                  ),
                  child: const Text('Show confirm'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppCard(
            title: 'Empty / loading / error states',
            child: Column(
              children: [
                SizedBox(height: 140, child: LoadingStateView(message: 'Loading…')),
                Divider(height: AppSpacing.xl),
                SizedBox(
                  height: 160,
                  child: EmptyStateView(title: 'No items yet', message: 'Items you add will show up here.'),
                ),
                Divider(height: AppSpacing.xl),
                SizedBox(height: 160, child: ErrorStateView(message: 'Could not load data.')),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          const AppCard(
            title: 'Coming-soon placeholder',
            child: SizedBox(height: 180, child: ComingSoonView(title: 'Feature name')),
          ),
        ],
      ),
    );
  }
}
