import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/date_format.dart';
import '../../../shared/widgets/app_data_table.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/empty_loading_error_states.dart';
import '../data/audit_logs_providers.dart';
import '../domain/audit_log.dart';
import '../domain/audit_log_query.dart';

/// STEP 6f, wired up: the warehouse backend now has a `GET /audit-logs`
/// (`AuditController`/`AuditService`, gated `audit.view`) closing the gap
/// this screen used to report — the interceptor always wrote `audit_logs`,
/// there was just no controller reading it back. Newest-first, filterable,
/// paginated, ported from the ordering app's near-identical screen (which
/// got a real backend first) with one addition: rows here can be attributed
/// to an API key instead of a user (the warehouse's external API is
/// key-authenticated), so the actor column and detail dialog show whichever
/// applies.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  late final TextEditingController _userIdController;
  late final TextEditingController _entityController;
  late final TextEditingController _entityIdController;
  late final TextEditingController _actionController;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    final query = ref.read(auditLogQueryProvider);
    _userIdController = TextEditingController(text: query.userId ?? '');
    _entityController = TextEditingController(text: query.entity ?? '');
    _entityIdController = TextEditingController(text: query.entityId ?? '');
    _actionController = TextEditingController(text: query.action ?? '');
    _from = query.from;
    _to = query.to;
  }

  @override
  void dispose() {
    _userIdController.dispose();
    _entityController.dispose();
    _entityIdController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _from : _to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  void _applyFilters() {
    ref
        .read(auditLogQueryProvider.notifier)
        .update(
          (q) => AuditLogQuery(
            userId: _userIdController.text.trim().isEmpty ? null : _userIdController.text.trim(),
            entity: _entityController.text.trim().isEmpty ? null : _entityController.text.trim(),
            entityId: _entityIdController.text.trim().isEmpty ? null : _entityIdController.text.trim(),
            action: _actionController.text.trim().isEmpty ? null : _actionController.text.trim(),
            from: _from,
            to: _to,
            page: 1,
            pageSize: q.pageSize,
          ),
        );
  }

  void _clearFilters() {
    setState(() {
      _userIdController.clear();
      _entityController.clear();
      _entityIdController.clear();
      _actionController.clear();
      _from = null;
      _to = null;
    });
    ref.read(auditLogQueryProvider.notifier).update((q) => const AuditLogQuery());
  }

  void _goToPage(int page) {
    ref.read(auditLogQueryProvider.notifier).update((q) => q.copyWith(page: page));
  }

  @override
  Widget build(BuildContext context) {
    final canView = ref.watch(authProvider.select((s) => s.value?.user?.can('audit.view') ?? false));
    if (!canView) {
      return const EmptyStateView(
        title: "You don't have permission to view the audit log",
        message: 'Ask an administrator for the audit.view permission.',
        icon: Icons.lock_outline,
      );
    }

    final theme = Theme.of(context);
    final pageAsync = ref.watch(auditLogsPageProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Audit Log', style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              SizedBox(width: 220, child: AppTextField(label: 'User ID', controller: _userIdController)),
              SizedBox(
                width: 180,
                child: AppTextField(label: 'Entity', controller: _entityController, hintText: 'products'),
              ),
              SizedBox(width: 200, child: AppTextField(label: 'Entity ID', controller: _entityIdController)),
              SizedBox(
                width: 160,
                child: AppTextField(label: 'Action', controller: _actionController, hintText: 'CREATE'),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(isFrom: true),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_from == null ? 'From' : formatDateTime(_from!).split(' ').first),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDate(isFrom: false),
                icon: const Icon(Icons.calendar_today_outlined, size: 16),
                label: Text(_to == null ? 'To' : formatDateTime(_to!).split(' ').first),
              ),
              FilledButton.icon(
                onPressed: _applyFilters,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Apply'),
              ),
              TextButton(onPressed: _clearFilters, child: const Text('Clear')),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: pageAsync.when(
              loading: () => const LoadingStateView(message: 'Loading audit log…'),
              error: (error, stackTrace) => ErrorStateView(
                message: error is AppError ? error.message : 'Could not load the audit log.',
                onRetry: () => ref.invalidate(auditLogsPageProvider),
              ),
              data: (page) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AppDataTable<AuditLog>(
                      rows: page.data,
                      emptyTitle: 'No audit log entries',
                      emptyMessage: 'Try widening or clearing the filters.',
                      onRowTap: (log) => _showDetail(context, log),
                      columns: [
                        AppDataColumn(label: 'When', cellBuilder: (l) => Text(formatDateTime(l.createdAt))),
                        AppDataColumn(label: 'Who', cellBuilder: (l) => Text(l.actorLabel)),
                        AppDataColumn(label: 'Action', cellBuilder: (l) => Text(l.action)),
                        AppDataColumn(label: 'Entity', cellBuilder: (l) => Text(l.entity)),
                        AppDataColumn(label: 'Entity ID', cellBuilder: (l) => Text(l.entityId ?? '—')),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _PaginationBar(page: page, onGoToPage: _goToPage),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, AuditLog log) {
    const encoder = JsonEncoder.withIndent('  ');
    String render(Object? value) => value == null ? '(none)' : encoder.convert(value);
    final who = log.user != null
        ? '${log.user!.fullName} (${log.user!.email})'
        : (log.apiKey != null ? '${log.apiKey!.name} (API key)' : '—');

    AppDialog.show<void>(
      context,
      title: '${log.action} · ${log.entity}${log.entityId != null ? ' (${log.entityId})' : ''}',
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('When: ${formatDateTime(log.createdAt)}'),
            Text('Who: $who'),
            const SizedBox(height: AppSpacing.md),
            Text('Old value', style: Theme.of(context).textTheme.labelLarge),
            SelectableText(render(log.oldValue), style: const TextStyle(fontFamily: 'monospace')),
            const SizedBox(height: AppSpacing.md),
            Text('New value', style: Theme.of(context).textTheme.labelLarge),
            SelectableText(render(log.newValue), style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({required this.page, required this.onGoToPage});

  final AuditLogPage page;
  final void Function(int page) onGoToPage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          'Page ${page.page} of ${page.totalPages == 0 ? 1 : page.totalPages} · ${page.total} total',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Previous page',
          icon: const Icon(Icons.chevron_left),
          onPressed: page.page > 1 ? () => onGoToPage(page.page - 1) : null,
        ),
        IconButton(
          tooltip: 'Next page',
          icon: const Icon(Icons.chevron_right),
          onPressed: page.page < page.totalPages ? () => onGoToPage(page.page + 1) : null,
        ),
      ],
    );
  }
}
