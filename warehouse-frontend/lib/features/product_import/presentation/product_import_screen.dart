import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_semantic_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/browser_download.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/product_import_providers.dart';
import '../domain/import_models.dart';

const _templateMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

enum _ImportStep { upload, preview, result }

enum _PreviewTab { create, update, reject }

/// Bulk product import — a 3-step wizard (upload → preview → result) reached
/// from the Products screen's "Import products" action. Supplements the
/// existing "New product" form; it doesn't replace it.
class ProductImportScreen extends ConsumerStatefulWidget {
  const ProductImportScreen({super.key});

  @override
  ConsumerState<ProductImportScreen> createState() => _ProductImportScreenState();
}

class _ProductImportScreenState extends ConsumerState<ProductImportScreen> {
  _ImportStep _step = _ImportStep.upload;

  bool _downloadingTemplate = false;

  Uint8List? _pickedBytes;
  String? _pickedFileName;
  bool _uploading = false;
  String? _uploadError;

  ImportPreviewResult? _previewResult;
  _PreviewTab _previewTab = _PreviewTab.create;
  bool _confirming = false;
  String? _confirmError;

  ImportConfirmResult? _confirmResult;

  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);
    try {
      final bytes = await ref.read(productImportApiProvider).downloadTemplate();
      triggerBrowserDownload(bytes, 'product-import-template.xlsx', mimeType: _templateMimeType);
    } on AppError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not download template: ${e.message}')));
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (file == null) return; // user cancelled
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedBytes = bytes;
      _pickedFileName = file.name;
      _uploadError = null;
    });
  }

  Future<void> _uploadAndPreview() async {
    final bytes = _pickedBytes;
    final name = _pickedFileName;
    if (bytes == null || name == null) return;

    setState(() {
      _uploading = true;
      _uploadError = null;
    });
    try {
      final result = await ref.read(productImportApiProvider).preview(bytes, name);
      if (!mounted) return;
      setState(() {
        _previewResult = result;
        _previewTab = result.toCreate.isNotEmpty
            ? _PreviewTab.create
            : (result.toUpdate.isNotEmpty ? _PreviewTab.update : _PreviewTab.reject);
        _step = _ImportStep.preview;
      });
    } on AppError catch (e) {
      setState(() => _uploadError = e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _cancelPreview() {
    // No discard endpoint is exposed — the staged session simply expires
    // server-side after its TTL if never confirmed. Abandoning it here is
    // enough; nothing has been written yet (preview never touches balances
    // or the product table).
    setState(() {
      _previewResult = null;
      _pickedBytes = null;
      _pickedFileName = null;
      _step = _ImportStep.upload;
    });
  }

  Future<void> _confirmImport() async {
    final sessionId = _previewResult?.importSessionId;
    if (sessionId == null) return;

    setState(() {
      _confirming = true;
      _confirmError = null;
    });
    try {
      final result = await ref.read(productImportApiProvider).confirm(sessionId);
      if (!mounted) return;
      // The product list may now be stale (created/updated rows) — refresh
      // it in the background so it's current by the time "Done" returns there.
      ref.invalidate(productsListProvider);
      setState(() {
        _confirmResult = result;
        _step = _ImportStep.result;
      });
    } on AppError catch (e) {
      setState(() => _confirmError = e.message);
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _startOver() {
    setState(() {
      _step = _ImportStep.upload;
      _pickedBytes = null;
      _pickedFileName = null;
      _uploadError = null;
      _previewResult = null;
      _confirmError = null;
      _confirmResult = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    if (!canManage) {
      return const EmptyStateView(
        title: "You don't have permission to manage products",
        message: 'Ask an administrator for the products.manage permission.',
        icon: Icons.lock_outline,
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back',
              onPressed: () => context.go(RoutePaths.products),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text('Import products', style: theme.textTheme.headlineSmall),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: switch (_step) {
            _ImportStep.upload => _UploadStep(
              downloadingTemplate: _downloadingTemplate,
              onDownloadTemplate: _downloadTemplate,
              pickedFileName: _pickedFileName,
              onPickFile: _pickFile,
              uploading: _uploading,
              uploadError: _uploadError,
              canUpload: _pickedBytes != null,
              onUpload: _uploadAndPreview,
            ),
            _ImportStep.preview => _PreviewStep(
              result: _previewResult!,
              tab: _previewTab,
              onTabChanged: (tab) => setState(() => _previewTab = tab),
              confirming: _confirming,
              confirmError: _confirmError,
              onCancel: _cancelPreview,
              onConfirm: _confirmImport,
            ),
            _ImportStep.result => _ResultStep(
              result: _confirmResult!,
              fileName: _previewResult?.fileName ?? '',
              onDone: () => context.go(RoutePaths.products),
              onImportAnother: _startOver,
            ),
          },
        ),
      ],
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.step, required this.title});

  final int step;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text('Step $step of 3 — $title', style: theme.textTheme.titleMedium);
  }
}

class _UploadStep extends StatelessWidget {
  const _UploadStep({
    required this.downloadingTemplate,
    required this.onDownloadTemplate,
    required this.pickedFileName,
    required this.onPickFile,
    required this.uploading,
    required this.uploadError,
    required this.canUpload,
    required this.onUpload,
  });

  final bool downloadingTemplate;
  final VoidCallback onDownloadTemplate;
  final String? pickedFileName;
  final VoidCallback onPickFile;
  final bool uploading;
  final String? uploadError;
  final bool canUpload;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepLabel(step: 1, title: 'Upload a file'),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Download the template to see the exact columns expected, fill it in, then upload it here. '
            'Rows with a SKU that already exists will UPDATE that product; new SKUs will be created.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: downloadingTemplate ? null : onDownloadTemplate,
            icon: downloadingTemplate
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            label: Text(downloadingTemplate ? 'Downloading…' : 'Download template (.xlsx)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.attach_file),
                label: const Text('Choose file'),
              ),
              const SizedBox(width: AppSpacing.md),
              if (pickedFileName != null)
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.description_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: Text(pickedFileName!, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                )
              else
                Text(
                  'No file chosen — .xlsx or .csv',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          if (uploadError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(uploadError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: (canUpload && !uploading) ? onUpload : null,
            icon: uploading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                  )
                : const Icon(Icons.upload_outlined),
            label: Text(uploading ? 'Validating…' : 'Upload & preview'),
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.count, required this.tone});

  final String label;
  final int count;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$count', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 2),
          StatusBadge(label: label, tone: tone),
        ],
      ),
    );
  }
}

class _PreviewStep extends StatelessWidget {
  const _PreviewStep({
    required this.result,
    required this.tab,
    required this.onTabChanged,
    required this.confirming,
    required this.confirmError,
    required this.onCancel,
    required this.onConfirm,
  });

  final ImportPreviewResult result;
  final _PreviewTab tab;
  final ValueChanged<_PreviewTab> onTabChanged;
  final bool confirming;
  final String? confirmError;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canConfirm = result.toCreate.isNotEmpty || result.toUpdate.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepLabel(step: 2, title: 'Review changes'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${result.fileName} — ${result.summary.totalRows} row${result.summary.totalRows == 1 ? '' : 's'} read.'
            ' Nothing has been saved yet.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              _SummaryChip(label: 'To create', count: result.summary.createCount, tone: StatusTone.success),
              _SummaryChip(label: 'To update', count: result.summary.updateCount, tone: StatusTone.info),
              _SummaryChip(label: 'Rejected', count: result.summary.rejectCount, tone: StatusTone.danger),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<_PreviewTab>(
            segments: [
              ButtonSegment(
                value: _PreviewTab.create,
                label: Text('To create (${result.toCreate.length})'),
                icon: const Icon(Icons.add_circle_outline),
              ),
              ButtonSegment(
                value: _PreviewTab.update,
                label: Text('To update (${result.toUpdate.length})'),
                icon: const Icon(Icons.sync_alt),
              ),
              ButtonSegment(
                value: _PreviewTab.reject,
                label: Text('Rejected (${result.rejected.length})'),
                icon: const Icon(Icons.block),
              ),
            ],
            selected: {tab},
            onSelectionChanged: (selection) => onTabChanged(selection.first),
          ),
          const SizedBox(height: AppSpacing.md),
          switch (tab) {
            _PreviewTab.create => _CreateTable(rows: result.toCreate),
            _PreviewTab.update => _UpdateTable(rows: result.toUpdate),
            _PreviewTab.reject => _RejectedTable(rows: result.rejected),
          },
          if (confirmError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Text(confirmError!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              OutlinedButton(onPressed: confirming ? null : onCancel, child: const Text('Cancel')),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: (canConfirm && !confirming) ? onConfirm : null,
                icon: confirming
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.onPrimary),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(confirming ? 'Importing…' : 'Confirm import'),
              ),
              if (!canConfirm) ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'Every row was rejected — nothing to import. Fix the file and upload it again.',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _money(double? v) => v == null ? '—' : v.toStringAsFixed(2);

class _CreateTable extends StatelessWidget {
  const _CreateTable({required this.rows});

  final List<ImportCreateRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<ImportCreateRow>(
      rows: rows,
      emptyTitle: 'No rows to create',
      columns: [
        AppDataColumn(label: 'Row', cellBuilder: (r) => Text('${r.rowNumber}')),
        AppDataColumn(label: 'SKU', cellBuilder: (r) => Text(r.sku)),
        AppDataColumn(label: 'Name', cellBuilder: (r) => Text(r.name)),
        AppDataColumn(label: 'Workstream', cellBuilder: (r) => Text(r.workstreamName)),
        AppDataColumn(label: 'Category', cellBuilder: (r) => Text(r.categoryName)),
        AppDataColumn(label: 'Price', numeric: true, cellBuilder: (r) => Text(_money(r.sellingPrice))),
        AppDataColumn(label: 'UoM', cellBuilder: (r) => Text(r.uom)),
      ],
    );
  }
}

class _UpdateTable extends StatelessWidget {
  const _UpdateTable({required this.rows});

  final List<ImportUpdateRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<ImportUpdateRow>(
      rows: rows,
      emptyTitle: 'No rows to update',
      columns: [
        AppDataColumn(label: 'Row', cellBuilder: (r) => Text('${r.row.rowNumber}')),
        AppDataColumn(label: 'SKU', cellBuilder: (r) => Text(r.row.sku)),
        AppDataColumn(label: 'Name', cellBuilder: (r) => Text(r.row.name)),
        AppDataColumn(
          label: 'Changes',
          cellBuilder: (r) => r.changes.isEmpty
              ? const Text('—')
              : Text(r.changes.map((c) => '${c.field}: ${c.oldValue ?? '—'} → ${c.newValue ?? '—'}').join('; ')),
        ),
      ],
    );
  }
}

class _RejectedTable extends StatelessWidget {
  const _RejectedTable({required this.rows});

  final List<ImportRejectedRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppDataTable<ImportRejectedRow>(
      rows: rows,
      emptyTitle: 'No rows rejected',
      columns: [
        AppDataColumn(label: 'Row', cellBuilder: (r) => Text('${r.rowNumber}')),
        AppDataColumn(label: 'SKU', cellBuilder: (r) => Text(r.sku ?? '—')),
        AppDataColumn(label: 'Reason', cellBuilder: (r) => Text(r.reason)),
      ],
    );
  }
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({
    required this.result,
    required this.fileName,
    required this.onDone,
    required this.onImportAnother,
  });

  final ImportConfirmResult result;
  final String fileName;
  final VoidCallback onDone;
  final VoidCallback onImportAnother;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasFailures = result.failed.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepLabel(step: 3, title: 'Done'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Icon(
                hasFailures ? Icons.info_outline : Icons.check_circle_outline,
                color: hasFailures ? theme.colorScheme.error : context.semanticColors.success,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$fileName imported: ${result.created} created, ${result.updated} updated'
                  '${hasFailures ? ', ${result.failed.length} failed' : ''}.',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          if (hasFailures) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'These rows passed preview but failed when saving — the data behind them changed in the '
              'meantime (e.g. a workstream or category was deactivated). Fix and re-import just these rows.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppDataTable<ImportFailedRow>(
              rows: result.failed,
              emptyTitle: 'No failures',
              columns: [
                AppDataColumn(label: 'SKU', cellBuilder: (r) => Text(r.sku)),
                AppDataColumn(label: 'Reason', cellBuilder: (r) => Text(r.reason)),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              OutlinedButton(onPressed: onImportAnother, child: const Text('Import another file')),
              const SizedBox(width: AppSpacing.md),
              FilledButton(onPressed: onDone, child: const Text('Done')),
            ],
          ),
        ],
      ),
    );
  }
}
