import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_controls.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';
import 'package:khanya_pos/features/accounting/domain/cash_flow_report.dart';
import 'package:uuid/uuid.dart';

class AccountingRepository {
  AccountingRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

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

  Future<CashFlowReport> cashFlow({
    required DateTime start,
    required DateTime end,
  }) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/cash-flow',
      queryParameters: {
        'start': start.toUtc().toIso8601String(),
        'end': end.toUtc().toIso8601String(),
      },
    );
    return CashFlowReport.fromJson(response.data ?? const <String, dynamic>{});
  }

  Future<AccountingControlsData> controls() async {
    final responses = await Future.wait<dynamic>([
      _apiClient.dio.get<List<dynamic>>('/accounting/accounts'),
      _apiClient.dio.get<Map<String, dynamic>>('/accounting/settings'),
    ]);
    final accountRows = responses[0].data as List<dynamic>? ?? const <dynamic>[];
    final settings = responses[1].data as Map<String, dynamic>? ?? const <String, dynamic>{};
    final accounts = accountRows
        .map((item) => AccountSummary.fromJson((item as Map).cast<String, dynamic>()))
        .toList(growable: false);
    return AccountingControlsData.fromSettings(accounts: accounts, settings: settings);
  }

  Future<List<JournalEntrySummary>> journalHistory({int limit = 150}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/accounting/journals',
      queryParameters: {'limit': limit},
    );
    return (response.data ?? const <dynamic>[])
        .map((item) => JournalEntrySummary.fromJson((item as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> postManualJournal({
    required String description,
    required List<ManualJournalLineDraft> lines,
    DateTime? occurredAt,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/accounting/journals/manual',
      data: {
        'client_operation_id': _uuid.v4(),
        'description': description.trim(),
        if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
        'lines': lines.map((line) => line.toJson()).toList(growable: false),
      },
    );
  }

  Future<void> reverseJournal({
    required String journalEntryId,
    required String reason,
    DateTime? occurredAt,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/accounting/journals/$journalEntryId/reverse',
      data: {
        'client_operation_id': _uuid.v4(),
        'reason': reason.trim(),
        if (occurredAt != null) 'occurred_at': occurredAt.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> advancePeriodLock({
    required DateTime lockedThrough,
    required String reason,
  }) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/accounting/period-lock',
      data: {
        'locked_through': lockedThrough.toUtc().toIso8601String(),
        'reason': reason.trim(),
      },
    );
  }
}
