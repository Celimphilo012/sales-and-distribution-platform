import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../data/audit_logs_providers.dart';
import '../domain/audit_log.dart';

Tone _actionTone(String action) => switch (action.toUpperCase()) {
  'CREATE' => Tone.ok,
  'UPDATE' => Tone.info,
  'DELETE' || 'DEACTIVATE' || 'REJECT' => Tone.bad,
  'APPROVE' => Tone.accent,
  _ => Tone.neutral,
};

/// Audit Log — every write, newest first, with who made it. The server pages it (100 a page); search, filters
/// and sorting work within the loaded page.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final q = ref.read(auditLogQueryProvider);
      if (q.pageSize != 100) ref.read(auditLogQueryProvider.notifier).update((q) => q.copyWith(pageSize: 100, page: 1));
    });
  }

  void _goTo(int page) => ref.read(auditLogQueryProvider.notifier).update((q) => q.copyWith(page: page));

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final async = ref.watch(auditLogsPageProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(auditLogsPageProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading the audit log…'),
        error: (e, _) => NxError(
          message: e is AppError ? e.message : 'Could not load the audit log.',
          onRetry: () => ref.invalidate(auditLogsPageProvider),
        ),
        data: (page) {
          final rows = page.data;
          List<(String, String)> opts(Iterable<String> v) => [for (final x in ({...v}.toList()..sort())) (x, x)];
          NxTag tag(AuditLog r) => NxTag(r.action, tone: _actionTone(r.action));
          final pages = page.totalPages == 0 ? 1 : page.totalPages;
          final pager = Row(
            children: [
              Expanded(
                child: Text(
                  'Page ${page.page} of $pages · ${fmtNum(page.total)} entries on the server',
                  style: TextStyle(fontSize: 12, color: n.n400),
                ),
              ),
              NxIconButton(icon: PhosphorIconsRegular.caretLeft, tooltip: 'Newer', onPressed: page.page > 1 ? () => _goTo(page.page - 1) : null),
              const SizedBox(width: 4),
              NxIconButton(icon: PhosphorIconsRegular.caretRight, tooltip: 'Older', onPressed: page.page < page.totalPages ? () => _goTo(page.page + 1) : null),
            ],
          );

          return NxListPage<AuditLog>(
            stateKey: 'audit',
            title: 'Audit Log',
            sub: 'Every write, newest first, with who made it.',
            rows: rows,
            totalCount: page.total,
            search: (r) => '${(r.user?.fullName ?? '—')} ${r.entity} ${r.entityId ?? ''} ${r.action}',
            searchPlaceholder: 'Entity ID, entity or person',
            stats: (rs) => [
              NxStat('Entries', fmtNum(rs.length), sub: 'of ${fmtNum(page.total)} on the server'),
              NxStat('People', fmtNum({for (final r in rs) ?r.user?.id}.length)),
              NxStat('Creates', fmtNum(rs.where((r) => r.action == 'CREATE').length)),
              NxStat('Updates', fmtNum(rs.where((r) => r.action == 'UPDATE').length)),
              NxStat(
                'Deletes',
                fmtNum(rs.where((r) => r.action == 'DELETE').length),
                color: rs.any((r) => r.action == 'DELETE') ? n.bad : null,
              ),
            ],
            quick: NxQuick(
              get: (r) => r.action,
              options: [('', 'All'), for (final a in {for (final r in rows) r.action}.toList()..sort()) (a, sentenceEnum(a))],
            ),
            filters: [
              NxSelectFilter('entity', 'Entity', options: opts(rows.map((r) => r.entity)), get: (r) => r.entity),
              NxSelectFilter('who', 'Who', searchable: true, options: opts(rows.map((r) => (r.user?.fullName ?? '—'))), get: (r) => (r.user?.fullName ?? '—')),
              NxDateFilter('date', 'Date', get: (r) => r.createdAt.toLocal()),
            ],
            defaultSort: ('when', -1),
            aboveContent: pager,
            columns: [
              NxColumn(key: 'when', label: 'When', sort: (r) => r.createdAt, cell: (r) => NxCellText(fmtTime(r.createdAt.toLocal()), sub: fmtDate(r.createdAt.toLocal()))),
              NxColumn(key: 'who', label: 'Who', sort: (r) => (r.user?.fullName ?? '—'), cell: (r) => NxCellText(r.user?.fullName ?? '—', sub: r.user?.email)),
              NxColumn(key: 'action', label: 'Action', sort: (r) => r.action, cell: (r) => Align(alignment: Alignment.centerLeft, child: tag(r))),
              NxColumn(key: 'entity', label: 'Entity', hide: NxHide.md, sort: (r) => r.entity, cell: (r) => NxCellText(r.entity, mono: true, color: n.n300)),
              NxColumn(key: 'eid', label: 'Entity ID', hide: NxHide.wide, cell: (r) => NxCellText(r.entityId ?? '—', mono: true, color: n.n400)),
            ],
            listRow: (r) => NxListRowSpec(
              icon: PhosphorIconsDuotone.user,
              iconColor: n.n500,
              title: '${r.action} · ${r.entity}',
              sub: '${r.entityId ?? '—'} · ${(r.user?.fullName ?? '—')}',
              right: fmtTime(r.createdAt.toLocal()),
              rightSub: fmtDate(r.createdAt.toLocal()),
            ),
            card: (r) => NxCardSpec(
              icon: PhosphorIconsDuotone.clockCounterClockwise,
              title: '${r.action} ${r.entity}',
              sub: r.entityId ?? '—',
              metrics: [('Who', (r.user?.fullName ?? '—'), null), ('When', fmtDateTime(r.createdAt.toLocal()), null)],
              tag: tag(r),
            ),
            onOpen: (r) => _showAuditEntry(context, r),
            emptyTitle: 'No entries match',
            emptyMessage: 'Try widening or clearing the filters.',
          );
        },
      ),
    );
  }
}

void _showAuditEntry(BuildContext context, AuditLog log) {
  const encoder = JsonEncoder.withIndent('  ');
  String render(Object? v) => v == null ? '(none)' : encoder.convert(v);
  final who = log.user != null ? '${log.user!.fullName} (${log.user!.email})' : '—';
  showNxDialog<void>(
    context,
    width: 720,
    builder: (ctx) {
      final n = ctx.nx;
      Widget block(String label, Object? v) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NxKicker(label, color: n.n500),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: n.bg, borderRadius: BorderRadius.circular(NxRadius.md)),
            child: SelectableText(render(v), style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: n.n200)),
          ),
        ],
      );
      return NxDialogFrame(
        title: log.action,
        titleWidget: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            NxTag(log.action, tone: _actionTone(log.action)),
            Text(log.entity, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: n.text)),
            if (log.entityId != null) Text(log.entityId!, style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: n.n400)),
          ],
        ),
        sub: '${fmtDateTime(log.createdAt.toLocal())} · $who',
        body: LayoutBuilder(
          builder: (context, box) {
            final two = box.maxWidth >= 460;
            final a = block('Before', log.oldValue);
            final b = block('After', log.newValue);
            return two
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [a, const SizedBox(height: 10), b]);
          },
        ),
        actions: [NxButton(label: 'Close', onPressed: () => Navigator.of(ctx).pop())],
      );
    },
  );
}
