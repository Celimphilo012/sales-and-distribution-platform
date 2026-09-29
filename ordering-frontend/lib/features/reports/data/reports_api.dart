import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/providers.dart';
import '../domain/reports.dart';

/// A reporting period. [from]/[to] null = unbounded. Every figure is a
/// server-side SQL aggregate — the client never sums rows itself.
enum ReportPeriod { today, thisWeek, thisMonth, last30Days, allTime }

extension ReportPeriodX on ReportPeriod {
  String get label => switch (this) {
    ReportPeriod.today => 'Today',
    ReportPeriod.thisWeek => 'This week',
    ReportPeriod.thisMonth => 'This month',
    ReportPeriod.last30Days => 'Last 30 days',
    ReportPeriod.allTime => 'All time',
  };

  /// Start of the period in local time (weeks start on Monday, like the dashboard).
  DateTime? get from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      ReportPeriod.today => today,
      ReportPeriod.thisWeek => today.subtract(Duration(days: today.weekday - 1)),
      ReportPeriod.thisMonth => DateTime(now.year, now.month),
      ReportPeriod.last30Days => today.subtract(const Duration(days: 29)),
      ReportPeriod.allTime => null,
    };
  }
}

class ReportsApi {
  ReportsApi(this._apiClient);

  final ApiClient _apiClient;

  Map<String, dynamic> _range(ReportPeriod period) => {'from': ?period.from?.toUtc().toIso8601String()};

  Future<OrdersReport> orders(ReportPeriod period) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/reports/orders', queryParameters: _range(period)),
    );
    return OrdersReport.fromJson(response.data!);
  }

  Future<PaymentsReport> payments(ReportPeriod period) async {
    final response = await _apiClient.guard(
      (dio) => dio.get<Map<String, dynamic>>('/reports/payments', queryParameters: _range(period)),
    );
    return PaymentsReport.fromJson(response.data!);
  }

  Future<DashboardSummary> dashboard() async {
    final response = await _apiClient.guard((dio) => dio.get<Map<String, dynamic>>('/dashboard'));
    return DashboardSummary.fromJson(response.data!);
  }
}

final reportsApiProvider = Provider<ReportsApi>((ref) => ReportsApi(ref.watch(apiClientProvider)));

final ordersReportProvider = FutureProvider.autoDispose.family<OrdersReport, ReportPeriod>((ref, period) {
  return ref.watch(reportsApiProvider).orders(period);
});

final paymentsReportProvider = FutureProvider.autoDispose.family<PaymentsReport, ReportPeriod>((ref, period) {
  return ref.watch(reportsApiProvider).payments(period);
});

final dashboardProvider = FutureProvider.autoDispose<DashboardSummary>((ref) {
  return ref.watch(reportsApiProvider).dashboard();
});
