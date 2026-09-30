import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../routing/route_paths.dart';
import '../../../shared/browser_download.dart';
import '../../../shared/nx/nx_form.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../products/presentation/products_list_providers.dart';
import '../data/product_import_providers.dart';
import '../domain/import_models.dart';

const _templateMimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

enum _ImportStep { upload, preview, result }

enum _PreviewTab { create, update, reject }

/// Bulk product import — a 3-step wizard (upload → preview → result) reached
/// from the Products screen's "Import" action. Supplements "New product".
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
      NxToast.ok('Template downloaded', 'product-import-template.xlsx');
    } on AppError catch (e) {
      NxToast.error('Could not download the template', e.message);
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _pickFile() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['xlsx', 'csv']);
    if (file == null) return;
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

  /// Nothing has been written yet — the staged session just expires server-side.
  void _cancelPreview() => setState(() {
    _previewResult = null;
    _pickedBytes = null;
    _pickedFileName = null;
    _step = _ImportStep.upload;
  });

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

  void _startOver() => setState(() {
    _step = _ImportStep.upload;
    _pickedBytes = null;
    _pickedFileName = null;
    _uploadError = null;
    _previewResult = null;
    _confirmError = null;
    _confirmResult = null;
  });

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(authProvider.select((s) => s.value?.user?.can('products.manage') ?? false));
    if (!canManage) {
      return const NxPageScroll(
        child: NxError(message: "You don't have permission to manage products"),
      );
    }
    return NxPageScroll(
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxPageHeader(
                title: 'Import products',
                sub: 'Create and update catalogue items in bulk from a spreadsheet.',
                actions: [NxButton(label: 'Back to products', icon: PhosphorIconsRegular.arrowLeft, onPressed: () => context.go(RoutePaths.products))],
              ),
              const SizedBox(height: 12),
              _Steps(current: _step),
              const SizedBox(height: 12),
              switch (_step) {
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
            ],
          ),
        ),
      ),
    );
  }
}

/// The three steps as a strip: done ones ticked, the current one accented.
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final _ImportStep current;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    const labels = ['Upload a file', 'Review changes', 'Done'];
    return Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        for (var i = 0; i < labels.length; i++)
          () {
            final done = i < current.index;
            final on = i == current.index;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? n.a900 : Colors.transparent,
                    border: Border.all(color: on || done ? n.accent : n.divider),
                  ),
                  child: done
                      ? Icon(PhosphorIconsBold.check, size: 11, color: n.accent)
                      : Text('${i + 1}', style: TextStyle(fontSize: 11, color: on ? n.a200 : n.n400)),
                ),
                const SizedBox(width: 7),
                Text(labels[i], style: TextStyle(fontSize: 12, color: on ? n.text : n.n400, fontWeight: on ? FontWeight.w500 : FontWeight.w400)),
              ],
            );
          }(),
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
    final n = context.nx;
    return Text('Step $step of 3 — $title', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: n.text));
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: n.bad.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(NxRadius.md)),
      child: Text(text, style: TextStyle(fontSize: 12, color: n.bad)),
    );
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
    final n = context.nx;
    return NxSection(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _StepLabel(step: 1, title: 'Upload a file'),
          const SizedBox(height: 6),
          Text(
            'Download the template to see the exact columns expected, fill it in, then upload it here. '
            'Rows with a SKU that already exists will UPDATE that product; new SKUs will be created.',
            style: TextStyle(fontSize: 13, color: n.n400, height: 1.5),
          ),
          const SizedBox(height: 14),
          NxButton(
            label: downloadingTemplate ? 'Downloading…' : 'Download template (.xlsx)',
            icon: PhosphorIconsRegular.downloadSimple,
            onPressed: downloadingTemplate ? null : onDownloadTemplate,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              NxButton(label: 'Choose file', icon: PhosphorIconsRegular.paperclip, onPressed: onPickFile),
              if (pickedFileName != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsDuotone.fileXls, size: 18, color: n.a400),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(pickedFileName!, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: n.text)),
                    ),
                  ],
                )
              else
                Text('No file chosen — .xlsx or .csv', style: TextStyle(fontSize: 12, color: n.n500)),
            ],
          ),
          if (uploadError != null) ...[const SizedBox(height: 12), _Banner(uploadError!)],
          const SizedBox(height: 16),
          NxButton.primary(
            label: uploading ? 'Validating…' : 'Upload & preview',
            icon: PhosphorIconsRegular.uploadSimple,
            onPressed: (canUpload && !uploading) ? onUpload : null,
          ),
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
    final n = context.nx;
    final canConfirm = result.toCreate.isNotEmpty || result.toUpdate.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSection(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepLabel(step: 2, title: 'Review changes'),
              const SizedBox(height: 4),
              Text(
                '${result.fileName} — ${result.summary.totalRows} row${result.summary.totalRows == 1 ? '' : 's'} read. Nothing has been saved yet.',
                style: TextStyle(fontSize: 13, color: n.n400),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        NxStatStrip(
          stats: [
            NxStat('To create', fmtNum(result.summary.createCount), color: n.ok),
            NxStat('To update', fmtNum(result.summary.updateCount), color: n.a300),
            NxStat('Rejected', fmtNum(result.summary.rejectCount), color: result.summary.rejectCount > 0 ? n.bad : null),
            NxStat('Rows read', fmtNum(result.summary.totalRows)),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: NxSeg<_PreviewTab>(
            options: [
              (_PreviewTab.create, 'To create (${result.toCreate.length})', null),
              (_PreviewTab.update, 'To update (${result.toUpdate.length})', null),
              (_PreviewTab.reject, 'Rejected (${result.rejected.length})', null),
            ],
            value: tab,
            onChanged: onTabChanged,
          ),
        ),
        const SizedBox(height: 10),
        switch (tab) {
          _PreviewTab.create => _rowsOrEmpty(
            context,
            result.toCreate,
            'No rows to create',
            NxTable<ImportCreateRow>(
              rows: result.toCreate,
              columns: [
                NxColumn(key: 'row', label: 'Row', width: 60, cell: (r) => NxCellText('${r.rowNumber}', color: n.n400)),
                NxColumn(key: 'sku', label: 'SKU', cell: (r) => NxCellText(r.sku, mono: true)),
                NxColumn(key: 'name', label: 'Name', cell: (r) => NxCellText(r.name, weight: FontWeight.w500)),
                NxColumn(key: 'ws', label: 'Workstream', hide: NxHide.md, cell: (r) => NxCellText(r.workstreamName, color: n.n300)),
                NxColumn(key: 'cat', label: 'Category', cell: (r) => NxCellText(r.categoryName)),
                NxColumn(key: 'price', label: 'Price', align: TextAlign.right, cell: (r) => NxCellText(fmtMoney(r.sellingPrice), align: TextAlign.right)),
                NxColumn(key: 'uom', label: 'UOM', cell: (r) => NxCellText(r.uom, color: n.n400)),
              ],
            ),
          ),
          _PreviewTab.update => _rowsOrEmpty(
            context,
            result.toUpdate,
            'No rows to update',
            NxTable<ImportUpdateRow>(
              rows: result.toUpdate,
              columns: [
                NxColumn(key: 'row', label: 'Row', width: 60, cell: (r) => NxCellText('${r.row.rowNumber}', color: n.n400)),
                NxColumn(key: 'sku', label: 'SKU', cell: (r) => NxCellText(r.row.sku, mono: true)),
                NxColumn(key: 'name', label: 'Name', cell: (r) => NxCellText(r.row.name, weight: FontWeight.w500)),
                NxColumn(
                  key: 'chg',
                  label: 'Changes',
                  cell: (r) => r.changes.isEmpty
                      ? NxCellText('No changes', color: n.n500)
                      : NxCellText(r.changes.map((c) => '${c.field}: ${c.oldValue ?? '—'} → ${c.newValue ?? '—'}').join('; ')),
                ),
              ],
            ),
          ),
          _PreviewTab.reject => _rowsOrEmpty(
            context,
            result.rejected,
            'No rows rejected',
            NxTable<ImportRejectedRow>(
              rows: result.rejected,
              columns: [
                NxColumn(key: 'row', label: 'Row', width: 60, cell: (r) => NxCellText('${r.rowNumber}', color: n.n400)),
                NxColumn(key: 'sku', label: 'SKU', cell: (r) => NxCellText(r.sku ?? '—', mono: true)),
                NxColumn(key: 'why', label: 'Reason', cell: (r) => NxCellText(r.reason, color: n.bad)),
              ],
            ),
          ),
        },
        if (confirmError != null) ...[const SizedBox(height: 12), _Banner(confirmError!)],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            NxButton(label: 'Cancel', onPressed: confirming ? null : onCancel),
            NxButton.primary(
              label: confirming ? 'Importing…' : 'Confirm import',
              icon: PhosphorIconsRegular.checkCircle,
              onPressed: (canConfirm && !confirming) ? onConfirm : null,
            ),
            if (!canConfirm)
              Text('Every row was rejected — nothing to import. Fix the file and upload it again.', style: TextStyle(fontSize: 12, color: n.n400)),
          ],
        ),
      ],
    );
  }

  Widget _rowsOrEmpty(BuildContext context, List<Object> rows, String empty, Widget table) => rows.isEmpty
      ? NxSection(
          padding: const EdgeInsets.all(16),
          child: Text(empty, style: TextStyle(fontSize: 13, color: context.nx.n400)),
        )
      : table;
}

class _ResultStep extends StatelessWidget {
  const _ResultStep({required this.result, required this.fileName, required this.onDone, required this.onImportAnother});

  final ImportConfirmResult result;
  final String fileName;
  final VoidCallback onDone;
  final VoidCallback onImportAnother;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final hasFailures = result.failed.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSection(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepLabel(step: 3, title: 'Done'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(hasFailures ? PhosphorIconsFill.warningCircle : PhosphorIconsFill.checkCircle, color: hasFailures ? n.warn : n.ok),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$fileName imported: ${result.created} created, ${result.updated} updated${hasFailures ? ', ${result.failed.length} failed' : ''}.',
                      style: TextStyle(fontSize: 14, color: n.text),
                    ),
                  ),
                ],
              ),
              if (hasFailures) ...[
                const SizedBox(height: 10),
                Text(
                  'These rows passed preview but failed when saving — the data behind them changed in the meantime '
                  '(e.g. a workstream or category was deactivated). Fix and re-import just these rows.',
                  style: TextStyle(fontSize: 12, color: n.n400),
                ),
              ],
            ],
          ),
        ),
        if (hasFailures) ...[
          const SizedBox(height: 10),
          NxTable<ImportFailedRow>(
            rows: result.failed,
            columns: [
              NxColumn(key: 'sku', label: 'SKU', cell: (r) => NxCellText(r.sku, mono: true)),
              NxColumn(key: 'why', label: 'Reason', cell: (r) => NxCellText(r.reason, color: n.bad)),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          children: [
            NxButton(label: 'Import another file', onPressed: onImportAnother),
            NxButton.primary(label: 'Done', onPressed: onDone),
          ],
        ),
      ],
    );
  }
}
