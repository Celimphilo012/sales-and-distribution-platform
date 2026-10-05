import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';
import '../../reports/data/reports_api.dart' show ReportPeriod, ReportPeriodX;
import '../domain/finances.dart';

/// `/finances` — the dashboard, per-customer statements, expense tracking and margin reporting.
class FinancesApi {
  FinancesApi(this._apiClient);

  final ApiClient _apiClient;

  Map<String, dynamic> _range(ReportPeriod period) => {'from': ?period.from?.toUtc().toIso8601String()};

  Future<FinancesSummary> summary(ReportPeriod period) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/finances/summary', queryParameters: _range(period)));
    return FinancesSummary.fromJson(response.data!);
  }

  Future<CustomerStatement> statement(String customerId, ReportPeriod period) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/finances/statements/$customerId', queryParameters: _range(period)),
    );
    return CustomerStatement.fromJson(response.data!);
  }

  Future<MarginReport> margin(ReportPeriod period) async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/finances/margin', queryParameters: _range(period)));
    return MarginReport.fromJson(response.data!);
  }

  Future<List<Expense>> expenses() async {
    final response = await _apiClient.guard((dio) => dio.get<List<dynamic>>('/finances/expenses'));
    return response.data!.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> recordExpense({required ExpenseCategory category, required double amount, String? description, required DateTime incurredAt}) async {
    await _apiClient.guard(
      (dio) => dio.post<Map<String, dynamic>>(
        '/finances/expenses',
        data: {
          'category': category.apiValue,
          'amount': amount,
          'description': ?description,
          'incurredAt': incurredAt.toIso8601String().substring(0, 10),
        },
      ),
    );
  }

  /// Confirmed with a one-time code; the API client's OTP prompt appears automatically.
  Future<void> voidExpense(String id, {required String reason}) async {
    await _apiClient.guard((dio) => dio.post<Map<String, dynamic>>('/finances/expenses/$id/void', data: {'reason': reason}));
  }
}

final financesApiProvider = Provider<FinancesApi>((ref) => FinancesApi(ref.watch(apiClientProvider)));

final financesSummaryProvider = FutureProvider.autoDispose.family<FinancesSummary, ReportPeriod>((ref, period) {
  return ref.watch(financesApiProvider).summary(period);
});

final customerStatementProvider = FutureProvider.autoDispose.family<CustomerStatement, (String, ReportPeriod)>((ref, args) {
  return ref.watch(financesApiProvider).statement(args.$1, args.$2);
});

final marginReportProvider = FutureProvider.autoDispose.family<MarginReport, ReportPeriod>((ref, period) {
  return ref.watch(financesApiProvider).margin(period);
});

final allExpensesProvider = FutureProvider.autoDispose<List<Expense>>((ref) {
  return ref.watch(financesApiProvider).expenses();
});
