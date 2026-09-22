import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';

class AccountingRepository {
  AccountingRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<AccountingWorkspaceData> workspace({
    required DateTime start,
    required DateTime end,
  }) async {
    final settingsFuture = _apiClient.dio.get<Map<String, dynamic>>('/accounting/settings');
    final trialBalanceFuture = _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/trial-balance',
      queryParameters: {'as_of': end.toUtc().toIso8601String()},
    );
    final profitLossFuture = _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/profit-loss',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );
    final balanceSheetFuture = _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/balance-sheet',
      queryParameters: {'as_of': end.toUtc().toIso8601String()},
    );
    final reconciliationFuture = _apiClient.dio.get<Map<String, dynamic>>('/accounting/reconciliation');
    final managementSummaryFuture = _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/management-summary',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );
    final journalsFuture = _apiClient.dio.get<List<dynamic>>(
      '/accounting/journals',
      queryParameters: {'limit': 100},
    );
    final ledgerFuture = _apiClient.dio.get<List<dynamic>>(
      '/accounting/ledger',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );

    final responses = await Future.wait<dynamic>([
      settingsFuture,
      trialBalanceFuture,
      profitLossFuture,
      balanceSheetFuture,
      reconciliationFuture,
      managementSummaryFuture,
      journalsFuture,
      ledgerFuture,
    ]);

    final settings = responses[0].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final trialBalance = responses[1].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final profitLoss = responses[2].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final balanceSheet = responses[3].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final reconciliation = responses[4].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final managementSummary = responses[5].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final journals = responses[6].data as List<dynamic>? ?? const <dynamic>[];
    final ledger = responses[7].data as List<dynamic>? ?? const <dynamic>[];

    return AccountingWorkspaceData(
      settings: AccountingSettings.fromJson(settings),
      trialBalance: TrialBalanceReport.fromJson(trialBalance),
      profitLoss: ProfitLossReport.fromJson(profitLoss),
      balanceSheet: BalanceSheetReport.fromJson(balanceSheet),
      reconciliation: ReconciliationReport.fromJson(reconciliation),
      managementSummary: ManagementSummary.fromJson(managementSummary),
      journals: journals
          .map((item) => JournalEntrySummary.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      ledger: ledger
          .map((item) => LedgerLine.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}
