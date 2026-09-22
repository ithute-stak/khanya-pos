import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_reports.dart';

class AccountingRepository {
  AccountingRepository({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  Future<TrialBalanceReport> trialBalance({DateTime? asOf}) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/trial-balance',
      queryParameters: {if (asOf != null) 'as_of': asOf.toUtc().toIso8601String()},
    );
    return TrialBalanceReport.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<ProfitLossReport> profitLoss({DateTime? start, DateTime? end}) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/profit-loss',
      queryParameters: {
        if (start != null) 'start': start.toUtc().toIso8601String(),
        if (end != null) 'end': end.toUtc().toIso8601String(),
      },
    );
    return ProfitLossReport.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<BalanceSheetReport> balanceSheet({DateTime? asOf}) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/balance-sheet',
      queryParameters: {if (asOf != null) 'as_of': asOf.toUtc().toIso8601String()},
    );
    return BalanceSheetReport.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<List<LedgerRow>> ledger({DateTime? start, DateTime? end, String? accountCode}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/accounting/ledger',
      queryParameters: {
        if (start != null) 'start': start.toUtc().toIso8601String(),
        if (end != null) 'end': end.toUtc().toIso8601String(),
        if (accountCode != null && accountCode.trim().isNotEmpty) 'account_code': accountCode.trim(),
      },
    );
    return (response.data ?? const [])
        .map((row) => LedgerRow.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<JournalSummary>> journals({int limit = 150}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/accounting/journals',
      queryParameters: {'limit': limit},
    );
    return (response.data ?? const [])
        .map((row) => JournalSummary.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<LedgerReconciliation> reconciliation() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/accounting/reconciliation');
    return LedgerReconciliation.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<AccountingSnapshot> snapshot({required DateTime start, required DateTime end}) async {
    final trialBalanceReport = await trialBalance(asOf: end);
    final profitLossReport = await profitLoss(start: start, end: end);
    final balanceSheetReport = await balanceSheet(asOf: end);
    final ledgerRows = await ledger(start: start, end: end);
    final journalRows = await journals();
    final ledgerReconciliation = await reconciliation();
    return AccountingSnapshot(
      trialBalance: trialBalanceReport,
      profitLoss: profitLossReport,
      balanceSheet: balanceSheetReport,
      ledger: ledgerRows,
      journals: journalRows,
      reconciliation: ledgerReconciliation,
    );
  }
}
