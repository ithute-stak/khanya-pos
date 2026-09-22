import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/reports/domain/sales_summary_report.dart';

class ReportsRepository {
  ReportsRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<SalesSummaryReport> salesSummary({
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/reports/sales-summary',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );
    return SalesSummaryReport.fromJson(response.data ?? const <String, dynamic>{});
  }
}
