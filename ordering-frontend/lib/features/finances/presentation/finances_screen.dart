import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../app_shell/responsive_app_shell.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/error/app_error.dart';
import '../../../core/theme/nocturne.dart';
import '../../../shared/nx/nx_format.dart';
import '../../../shared/nx/nx_list_page.dart';
import '../../../shared/nx/nx_overlays.dart';
import '../../../shared/nx/nx_primitives.dart';
import '../../customers/data/customers_providers.dart';
import '../../customers/domain/customer.dart';
import '../../payments/domain/payment.dart';
import '../../reports/data/export_branding.dart';
import '../../reports/data/reports_api.dart' show ReportPeriod, ReportPeriodX;
import '../../../shared/export/report_export.dart';
import '../data/finances_api.dart';
import '../domain/finances.dart';
import 'expense_dialogs.dart';

/// Finances — a dashboard (cash collected, AR aging, revenue trend),
/// per-customer statements, expense tracking, and margin reporting. Separate
/// from Reports/Dashboard: a distinct audience (finances.view) and, for
/// expenses, its own permission boundary.
class FinancesScreen extends ConsumerStatefulWidget {
  const FinancesScreen({super.key, this.initialTab = 0, this.initialCustomerId});

  final int initialTab;

  /// Opens the Statements tab with this customer already selected — reached
  /// from the customer sheet's "Statement" button.
  final String? initialCustomerId;

  @override
  ConsumerState<FinancesScreen> createState() => _FinancesScreenState();
}

class _FinancesScreenState extends ConsumerState<FinancesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
  ReportPeriod _period = ReportPeriod.thisMonth;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final canRecord = ref.watch(authProvider.select((s) => s.value?.user?.can('finances.expenses.record') ?? false));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Finances', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: n.text)),
                    Text('Cash position, customer statements, expenses and margin.', style: TextStyle(fontSize: 12, color: n.n400)),
                  ],
                ),
              ),
              DropdownButton<ReportPeriod>(
                value: _period,
                underline: const SizedBox.shrink(),
                items: [for (final p in ReportPeriod.values) DropdownMenuItem(value: p, child: Text(p.label))],
                onChanged: (p) {
                  if (p != null) setState(() => _period = p);
                },
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'Statements'), Tab(text: 'Expenses'), Tab(text: 'Margin')],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(period: _period),
              _StatementsTab(period: _period, initialCustomerId: widget.initialCustomerId),
              _ExpensesTab(canRecord: canRecord),
              _MarginTab(period: _period),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Overview ───────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.period});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(financesSummaryProvider(period));

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(financesSummaryProvider(period)),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading finances…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load the finances summary.', onRetry: () => ref.invalidate(financesSummaryProvider(period))),
        data: (s) {
          final maxAging = s.aging.fold<double>(0, (m, b) => b.amount > m ? b.amount : m);
          final maxRevenue = s.revenueTrend.fold<double>(0, (m, p) => p.revenue > m ? p.revenue : m);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _StatTile(label: 'Collected', value: fmtMoney(s.collectedAmount), sub: '${s.collectedCount} payments', color: n.ok)),
                    const SizedBox(width: 12),
                    Expanded(child: _StatTile(label: 'Outstanding', value: fmtMoney(s.outstandingAmount), sub: '${s.outstandingCount} orders', color: s.outstandingAmount > 0 ? n.warn : null)),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Receivables ageing', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                const SizedBox(height: 10),
                NxSection(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      for (final b in s.aging)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              SizedBox(width: 56, child: Text(b.bucket, style: TextStyle(fontSize: 12, color: n.n400))),
                              Expanded(
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: maxAging > 0 ? (b.amount / maxAging).clamp(0.02, 1.0) : 0.02,
                                  child: Container(height: 10, decoration: BoxDecoration(color: b.bucket == '90+' ? n.bad : n.accent, borderRadius: BorderRadius.circular(4))),
                                ),
                              ),
                              const SizedBox(width: 10),
                              SizedBox(width: 90, child: Text(fmtMoney(b.amount), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: n.text, fontFeatures: tabular))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('Revenue by week', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text)),
                const SizedBox(height: 10),
                if (s.revenueTrend.isEmpty)
                  Text('No orders in this period.', style: TextStyle(fontSize: 12, color: n.n400))
                else
                  NxSection(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        for (final p in s.revenueTrend)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 5),
                            child: Row(
                              children: [
                                SizedBox(width: 80, child: Text(fmtDate(p.weekStart), style: TextStyle(fontSize: 12, color: n.n400))),
                                Expanded(
                                  child: FractionallySizedBox(
                                    alignment: Alignment.centerLeft,
                                    widthFactor: maxRevenue > 0 ? (p.revenue / maxRevenue).clamp(0.02, 1.0) : 0.02,
                                    child: Container(height: 10, decoration: BoxDecoration(color: n.accent, borderRadius: BorderRadius.circular(4))),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(width: 90, child: Text(fmtMoney(p.revenue), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: n.text, fontFeatures: tabular))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value, this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    return NxSection(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: n.n500)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color ?? n.text, fontFeatures: tabular)),
          if (sub != null) ...[const SizedBox(height: 2), Text(sub!, style: TextStyle(fontSize: 11, color: n.n500))],
        ],
      ),
    );
  }
}

// ─── Statements ─────────────────────────────────────────────────────────────

class _StatementsTab extends ConsumerStatefulWidget {
  const _StatementsTab({required this.period, this.initialCustomerId});

  final ReportPeriod period;
  final String? initialCustomerId;

  @override
  ConsumerState<_StatementsTab> createState() => _StatementsTabState();
}

class _StatementsTabState extends ConsumerState<_StatementsTab> {
  final _search = TextEditingController();
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    _selectedCustomerId = widget.initialCustomerId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(CustomerStatement s) async {
    NxToast.info('Preparing PDF…', '${s.customerName} · ${s.entries.length} entries');
    try {
      final branding = await loadExportBranding(ref, scope: '${widget.period.label} statement');
      final rows = [
        for (final e in s.entries)
          [fmtDate(e.occurredAt.toLocal()), e.type == 'ORDER' ? (e.orderNumber ?? '—') : '${e.orderNumber ?? '—'} (${e.method?.label ?? ''})', e.isVoided ? 0 : e.amount, e.balance],
      ];
      final data = ReportData(
        title: '${s.customerName} — statement',
        description: 'Bought ${fmtMoney(s.bought)} · Paid ${fmtMoney(s.paid)} · Balance due ${fmtMoney(s.balanceDue)}',
        columns: const [ReportColumn('Date'), ReportColumn('Reference'), ReportColumn('Amount', ColType.money), ReportColumn('Balance', ColType.money)],
        rows: rows,
      );
      final name = await downloadReport(data, branding, pdf: true);
      NxToast.ok('PDF downloaded', name);
    } on AppError catch (e) {
      NxToast.error('Export failed', e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = context.nx;
    final customers = ref.watch(customersListProvider).value ?? const <Customer>[];
    final query = _search.text.trim().toLowerCase();
    final visible = query.isEmpty ? customers : customers.where((c) => c.name.toLowerCase().contains(query)).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 260,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search customers', isDense: true)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final c = visible[i];
                    final selected = c.id == _selectedCustomerId;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      title: Text(c.name, style: TextStyle(fontSize: 13, color: n.text)),
                      onTap: () => setState(() => _selectedCustomerId = c.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedCustomerId == null
              ? Center(child: Text('Pick a customer to see their statement.', style: TextStyle(fontSize: 13, color: n.n400)))
              : _StatementView(customerId: _selectedCustomerId!, period: widget.period, onExport: _export),
        ),
      ],
    );
  }
}

class _StatementView extends ConsumerWidget {
  const _StatementView({required this.customerId, required this.period, required this.onExport});

  final String customerId;
  final ReportPeriod period;
  final Future<void> Function(CustomerStatement) onExport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(customerStatementProvider((customerId, period)));

    return async.when(
      loading: () => const NxLoading(message: 'Loading statement…'),
      error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load this statement.', onRetry: () => ref.invalidate(customerStatementProvider((customerId, period)))),
      data: (s) => NxPageScroll(
        onRefresh: () async => ref.invalidate(customerStatementProvider((customerId, period))),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(s.customerName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: n.text))),
                  NxButton(label: 'Export PDF', icon: PhosphorIconsRegular.filePdf, small: true, onPressed: () => onExport(s)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Bought', value: fmtMoney(s.bought))),
                  const SizedBox(width: 10),
                  Expanded(child: _StatTile(label: 'Paid', value: fmtMoney(s.paid))),
                  const SizedBox(width: 10),
                  Expanded(child: _StatTile(label: 'Balance due', value: fmtMoney(s.balanceDue), color: s.balanceDue > 0 ? n.warn : null)),
                ],
              ),
              const SizedBox(height: 16),
              if (s.entries.isEmpty)
                Text('No activity in this period.', style: TextStyle(fontSize: 12, color: n.n400))
              else
                NxSection(
                  child: Column(
                    children: [
                      for (final e in s.entries)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Icon(e.type == 'ORDER' ? PhosphorIconsRegular.receipt : PhosphorIconsRegular.handCoins, size: 16, color: n.n400),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      e.type == 'ORDER' ? 'Order ${e.orderNumber ?? ''}' : 'Payment · ${e.method?.label ?? ''}${e.isVoided ? ' (voided)' : ''}',
                                      style: TextStyle(fontSize: 13, color: n.text, decoration: e.isVoided ? TextDecoration.lineThrough : null),
                                    ),
                                    Text(fmtDate(e.occurredAt.toLocal()), style: TextStyle(fontSize: 11, color: n.n500)),
                                  ],
                                ),
                              ),
                              Text(
                                e.type == 'ORDER' ? '+${fmtMoney(e.amount)}' : (e.isVoided ? fmtMoney(0) : '-${fmtMoney(e.amount)}'),
                                style: TextStyle(fontSize: 13, color: e.type == 'ORDER' ? n.text : n.ok, fontFeatures: tabular),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(width: 80, child: Text(fmtMoney(e.balance), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.text, fontFeatures: tabular))),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Expenses ───────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  const _ExpensesTab({required this.canRecord});

  final bool canRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final canVoid = ref.watch(authProvider.select((s) => s.value?.user?.can('finances.expenses.void') ?? false));
    final async = ref.watch(allExpensesProvider);

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(allExpensesProvider),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading expenses…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load expenses.', onRetry: () => ref.invalidate(allExpensesProvider)),
        data: (expenses) {
          NxTag state(Expense e) => NxTag(e.isVoided ? 'Voided' : 'Recorded', tone: e.isVoided ? Tone.bad : Tone.ok, small: true);
          List<NxRowAction> acts(Expense e) => [
            if (canVoid && !e.isVoided)
              NxRowAction(
                icon: PhosphorIconsRegular.arrowCounterClockwise,
                label: 'Void',
                danger: true,
                onPressed: () async {
                  if (await showVoidExpenseDialog(context, expense: e)) ref.invalidate(allExpensesProvider);
                },
              ),
          ];

          return NxListPage<Expense>(
            stateKey: 'expenses',
            title: 'Expenses',
            sub: 'Money out. A mistake is voided — kept with the reason — never edited or deleted.',
            actions: [
              if (canRecord)
                NxButton.primary(
                  label: 'Record expense',
                  icon: PhosphorIconsRegular.plus,
                  onPressed: () async {
                    if (await showRecordExpenseDialog(context)) ref.invalidate(allExpensesProvider);
                  },
                ),
            ],
            rows: expenses,
            search: (e) => '${e.category.label} ${e.description ?? ''}',
            searchPlaceholder: 'Category or description',
            stats: (rs) {
              final live = rs.where((e) => !e.isVoided);
              return [
                NxStat('Total', fmtMoney(live.fold<double>(0, (s, e) => s + e.amount)), sub: '${live.length} expenses', color: n.bad),
                NxStat('Voided', fmtNum(rs.where((e) => e.isVoided).length), color: rs.any((e) => e.isVoided) ? n.bad : null),
              ];
            },
            quick: NxQuick(get: (e) => e.isVoided ? 'void' : 'ok', options: const [('', 'All'), ('ok', 'Recorded'), ('void', 'Voided')]),
            filters: [NxMultiFilter('category', 'Category', options: [for (final c in ExpenseCategory.values) (c.apiValue, c.label)], get: (e) => e.category.apiValue)],
            defaultSort: ('when', -1),
            columns: [
              NxColumn(key: 'when', label: 'Incurred', sort: (e) => e.incurredAt, cell: (e) => NxCellText(fmtDate(e.incurredAt.toLocal()))),
              NxColumn(key: 'category', label: 'Category', sort: (e) => e.category.label, cell: (e) => NxCellText(e.category.label, sub: e.description)),
              NxColumn(
                key: 'amount',
                label: 'Amount',
                align: TextAlign.right,
                sort: (e) => e.amount,
                cell: (e) => Text(
                  fmtMoney(e.amount),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: e.isVoided ? n.n500 : n.bad, decoration: e.isVoided ? TextDecoration.lineThrough : null, fontFeatures: tabular),
                ),
              ),
              NxColumn(key: 'by', label: 'Recorded by', hide: NxHide.wide, cell: (e) => NxCellText(e.recordedByName, color: n.n300)),
              NxColumn(key: 'state', label: 'Status', cell: (e) => Align(alignment: Alignment.centerLeft, child: state(e))),
              if (canVoid) NxColumn(key: 'act', label: '', width: 52, cell: (e) => NxRowActions(acts(e))),
            ],
            listRow: (e) => NxListRowSpec(
              icon: PhosphorIconsRegular.receiptX,
              iconColor: e.isVoided ? n.n500 : n.bad,
              title: '${e.category.label}${e.description == null ? '' : ' · ${e.description}'}',
              sub: [e.recordedByName, if (e.isVoided) 'voided: ${e.voidReason ?? ''}'].join(' · '),
              right: fmtMoney(e.amount),
              rightSub: fmtDate(e.incurredAt.toLocal()),
              rightColor: e.isVoided ? n.n500 : n.bad,
              tag: e.isVoided ? state(e) : null,
              actions: acts(e),
            ),
            card: (e) => NxCardSpec(
              icon: PhosphorIconsRegular.receiptX,
              iconColor: e.isVoided ? n.n500 : n.bad,
              title: fmtMoney(e.amount),
              sub: e.category.label,
              metrics: [('Incurred', fmtDate(e.incurredAt.toLocal()), null), ('By', e.recordedByName, null)],
              tag: state(e),
              actions: acts(e),
            ),
            emptyTitle: 'No expenses match',
            emptyMessage: 'Record one with "Record expense".',
          );
        },
      ),
    );
  }
}

// ─── Margin ─────────────────────────────────────────────────────────────────

class _MarginTab extends ConsumerWidget {
  const _MarginTab({required this.period});

  final ReportPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = context.nx;
    final async = ref.watch(marginReportProvider(period));

    return NxPageScroll(
      onRefresh: () async => ref.invalidate(marginReportProvider(period)),
      child: async.when(
        loading: () => const NxLoading(message: 'Loading margin…'),
        error: (e, _) => NxError(message: e is AppError ? e.message : 'Could not load margin.', onRetry: () => ref.invalidate(marginReportProvider(period))),
        data: (m) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NxSection(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsRegular.info, size: 16, color: n.n400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Forward-looking only: orders placed before cost tracking shipped have no known cost and are left out, not treated as zero. '
                        '${m.knownCostRevenuePct.toStringAsFixed(0)}% of revenue in this period has a known cost '
                        '(${fmtMoney(m.knownCostRevenue)} of ${fmtMoney(m.totalRevenue)}).',
                        style: TextStyle(fontSize: 12, color: n.n400),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _StatTile(label: 'Margin (known-cost lines)', value: fmtMoney(m.margin), color: n.ok)),
                  const SizedBox(width: 10),
                  Expanded(child: _StatTile(label: 'Known-cost revenue', value: fmtMoney(m.knownCostRevenue))),
                ],
              ),
              const SizedBox(height: 16),
              if (m.products.isEmpty)
                Text('No sold lines with a known cost in this period.', style: TextStyle(fontSize: 12, color: n.n400))
              else
                NxSection(
                  child: Column(
                    children: [
                      for (final p in m.products)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.productName ?? p.productId, style: TextStyle(fontSize: 13, color: n.text)),
                                    Text('${fmtNum(p.quantity)} sold · revenue ${fmtMoney(p.revenue)}', style: TextStyle(fontSize: 11, color: n.n500)),
                                  ],
                                ),
                              ),
                              Text(fmtMoney(p.margin), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: n.ok, fontFeatures: tabular)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
