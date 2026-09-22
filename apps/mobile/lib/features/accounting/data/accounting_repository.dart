import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:uuid/uuid.dart';

class AccountingSettings {
  const AccountingSettings({
    required this.baseCurrency,
    required this.fiscalYearStartMonth,
    this.lockedThrough,
    this.lockReason,
  });

  final String baseCurrency;
  final int fiscalYearStartMonth;
  final DateTime? lockedThrough;
  final String? lockReason;

  factory AccountingSettings.fromJson(Map<String, dynamic> json) => AccountingSettings(
        baseCurrency: json['base_currency']?.toString() ?? 'LSL',
        fiscalYearStartMonth: (json['fiscal_year_start_month'] as num?)?.toInt() ?? 1,
        lockedThrough: _dateTimeOrNull(json['locked_through']),
        lockReason: json['lock_reason']?.toString(),
      );
}

class AccountingAccount {
  const AccountingAccount({
    required this.code,
    required this.name,
    required this.accountType,
    required this.reportGroup,
    required this.normalBalance,
    required this.isSystem,
    required this.isActive,
  });

  final String code;
  final String name;
  final String accountType;
  final String? reportGroup;
  final String normalBalance;
  final bool isSystem;
  final bool isActive;

  factory AccountingAccount.fromJson(Map<String, dynamic> json) => AccountingAccount(
        code: json['code'].toString(),
        name: json['name'].toString(),
        accountType: json['account_type'].toString(),
        reportGroup: json['report_group']?.toString(),
        normalBalance: json['normal_balance'].toString(),
        isSystem: json['is_system'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class JournalLineSummary {
  const JournalLineSummary({
    required this.accountCode,
    required this.accountName,
    required this.debitMinor,
    required this.creditMinor,
    this.memo,
  });

  final String accountCode;
  final String accountName;
  final int debitMinor;
  final int creditMinor;
  final String? memo;

  factory JournalLineSummary.fromJson(Map<String, dynamic> json) => JournalLineSummary(
        accountCode: json['account_code'].toString(),
        accountName: json['account_name'].toString(),
        debitMinor: ScaledDecimal.toMinor(json['debit']),
        creditMinor: ScaledDecimal.toMinor(json['credit']),
        memo: json['memo']?.toString(),
      );
}

class JournalSummary {
  const JournalSummary({
    required this.id,
    required this.entryNumber,
    required this.sourceType,
    required this.description,
    required this.occurredAt,
    required this.lines,
    this.reversalOfId,
    this.reversalReason,
  });

  final String id;
  final String entryNumber;
  final String sourceType;
  final String description;
  final DateTime occurredAt;
  final List<JournalLineSummary> lines;
  final String? reversalOfId;
  final String? reversalReason;

  bool get isManual => sourceType == 'manual_journal';
  int get totalDebitMinor => lines.fold(0, (total, line) => total + line.debitMinor);

  factory JournalSummary.fromJson(Map<String, dynamic> json) => JournalSummary(
        id: json['id'].toString(),
        entryNumber: json['entry_number'].toString(),
        sourceType: json['source_type'].toString(),
        description: json['description'].toString(),
        occurredAt: DateTime.parse(json['occurred_at'].toString()).toLocal(),
        reversalOfId: json['reversal_of_id']?.toString(),
        reversalReason: json['reversal_reason']?.toString(),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((row) => JournalLineSummary.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class LedgerRow {
  const LedgerRow({
    required this.entryNumber,
    required this.occurredAt,
    required this.sourceType,
    required this.description,
    required this.accountCode,
    required this.accountName,
    required this.debitMinor,
    required this.creditMinor,
    this.memo,
  });

  final String entryNumber;
  final DateTime occurredAt;
  final String sourceType;
  final String description;
  final String accountCode;
  final String accountName;
  final int debitMinor;
  final int creditMinor;
  final String? memo;

  factory LedgerRow.fromJson(Map<String, dynamic> json) => LedgerRow(
        entryNumber: json['entry_number'].toString(),
        occurredAt: DateTime.parse(json['occurred_at'].toString()).toLocal(),
        sourceType: json['source_type'].toString(),
        description: json['description'].toString(),
        accountCode: json['account_code'].toString(),
        accountName: json['account_name'].toString(),
        debitMinor: ScaledDecimal.toMinor(json['debit']),
        creditMinor: ScaledDecimal.toMinor(json['credit']),
        memo: json['memo']?.toString(),
      );
}

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.code,
    required this.name,
    required this.accountType,
    required this.normalBalance,
    required this.debitsMinor,
    required this.creditsMinor,
    required this.balanceMinor,
  });

  final String code;
  final String name;
  final String accountType;
  final String normalBalance;
  final int debitsMinor;
  final int creditsMinor;
  final int balanceMinor;

  factory TrialBalanceRow.fromJson(Map<String, dynamic> json) => TrialBalanceRow(
        code: json['code'].toString(),
        name: json['name'].toString(),
        accountType: json['account_type'].toString(),
        normalBalance: json['normal_balance'].toString(),
        debitsMinor: ScaledDecimal.toMinor(json['debits']),
        creditsMinor: ScaledDecimal.toMinor(json['credits']),
        balanceMinor: ScaledDecimal.toMinor(json['balance']),
      );
}

class TrialBalanceReport {
  const TrialBalanceReport({
    required this.accounts,
    required this.totalDebitsMinor,
    required this.totalCreditsMinor,
    required this.differenceMinor,
  });

  final List<TrialBalanceRow> accounts;
  final int totalDebitsMinor;
  final int totalCreditsMinor;
  final int differenceMinor;

  bool get balances => differenceMinor == 0;

  factory TrialBalanceReport.fromJson(Map<String, dynamic> json) => TrialBalanceReport(
        accounts: (json['accounts'] as List<dynamic>? ?? const [])
            .map((row) => TrialBalanceRow.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
        totalDebitsMinor: ScaledDecimal.toMinor(json['total_debits']),
        totalCreditsMinor: ScaledDecimal.toMinor(json['total_credits']),
        differenceMinor: ScaledDecimal.toMinor(json['difference']),
      );
}

class ProfitLossAccountRow {
  const ProfitLossAccountRow({required this.code, required this.name, required this.amountMinor});

  final String code;
  final String name;
  final int amountMinor;

  factory ProfitLossAccountRow.fromJson(Map<String, dynamic> json) => ProfitLossAccountRow(
        code: json['code'].toString(),
        name: json['name'].toString(),
        amountMinor: ScaledDecimal.toMinor(json['amount']),
      );
}

class ProfitLossReport {
  const ProfitLossReport({
    required this.salesRevenueMinor,
    required this.otherIncomeMinor,
    required this.costOfSalesMinor,
    required this.grossProfitMinor,
    required this.operatingExpensesMinor,
    required this.netProfitMinor,
    required this.accounts,
  });

  final int salesRevenueMinor;
  final int otherIncomeMinor;
  final int costOfSalesMinor;
  final int grossProfitMinor;
  final int operatingExpensesMinor;
  final int netProfitMinor;
  final List<ProfitLossAccountRow> accounts;

  factory ProfitLossReport.fromJson(Map<String, dynamic> json) => ProfitLossReport(
        salesRevenueMinor: ScaledDecimal.toMinor(json['sales_revenue'] ?? json['revenue']),
        otherIncomeMinor: ScaledDecimal.toMinor(json['other_income']),
        costOfSalesMinor: ScaledDecimal.toMinor(json['cost_of_sales']),
        grossProfitMinor: ScaledDecimal.toMinor(json['gross_profit']),
        operatingExpensesMinor: ScaledDecimal.toMinor(json['operating_expenses']),
        netProfitMinor: ScaledDecimal.toMinor(json['net_profit']),
        accounts: (json['accounts'] as List<dynamic>? ?? const [])
            .map((row) => ProfitLossAccountRow.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class BalanceSheetReport {
  const BalanceSheetReport({
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.equityMinor,
    required this.currentEarningsMinor,
    required this.equityIncludingEarningsMinor,
    required this.liabilitiesAndEquityMinor,
    required this.differenceMinor,
  });

  final int assetsMinor;
  final int liabilitiesMinor;
  final int equityMinor;
  final int currentEarningsMinor;
  final int equityIncludingEarningsMinor;
  final int liabilitiesAndEquityMinor;
  final int differenceMinor;

  bool get balances => differenceMinor == 0;

  factory BalanceSheetReport.fromJson(Map<String, dynamic> json) => BalanceSheetReport(
        assetsMinor: ScaledDecimal.toMinor(json['assets']),
        liabilitiesMinor: ScaledDecimal.toMinor(json['liabilities']),
        equityMinor: ScaledDecimal.toMinor(json['equity']),
        currentEarningsMinor: ScaledDecimal.toMinor(json['current_earnings']),
        equityIncludingEarningsMinor: ScaledDecimal.toMinor(json['equity_including_current_earnings']),
        liabilitiesAndEquityMinor: ScaledDecimal.toMinor(json['liabilities_and_equity']),
        differenceMinor: ScaledDecimal.toMinor(json['difference']),
      );
}

class ReconciliationReport {
  const ReconciliationReport({
    required this.healthy,
    required this.trialBalanceDifferenceMinor,
    required this.inventoryDifferenceMinor,
    required this.stockInTransitDifferenceMinor,
    required this.accountsPayableDifferenceMinor,
    required this.supplierAdvancesDifferenceMinor,
    required this.missingSaleJournals,
    required this.missingPurchaseJournals,
    required this.missingExpenseJournals,
  });

  final bool healthy;
  final int trialBalanceDifferenceMinor;
  final int inventoryDifferenceMinor;
  final int stockInTransitDifferenceMinor;
  final int accountsPayableDifferenceMinor;
  final int supplierAdvancesDifferenceMinor;
  final int missingSaleJournals;
  final int missingPurchaseJournals;
  final int missingExpenseJournals;

  factory ReconciliationReport.fromJson(Map<String, dynamic> json) => ReconciliationReport(
        healthy: json['healthy'] as bool? ?? false,
        trialBalanceDifferenceMinor: ScaledDecimal.toMinor(json['trial_balance_difference']),
        inventoryDifferenceMinor: ScaledDecimal.toMinor(json['inventory_difference']),
        stockInTransitDifferenceMinor: ScaledDecimal.toMinor(json['stock_in_transit_difference']),
        accountsPayableDifferenceMinor: ScaledDecimal.toMinor(json['accounts_payable_difference']),
        supplierAdvancesDifferenceMinor: ScaledDecimal.toMinor(json['supplier_advances_difference']),
        missingSaleJournals: (json['missing_sale_journals'] as num?)?.toInt() ?? 0,
        missingPurchaseJournals: (json['missing_purchase_journals'] as num?)?.toInt() ?? 0,
        missingExpenseJournals: (json['missing_expense_journals'] as num?)?.toInt() ?? 0,
      );
}

class ManualJournalLineDraft {
  const ManualJournalLineDraft({
    required this.accountCode,
    required this.debitMinor,
    required this.creditMinor,
    this.memo,
  });

  final String accountCode;
  final int debitMinor;
  final int creditMinor;
  final String? memo;
}

class AccountingRepository {
  AccountingRepository({required ApiClient apiClient, Uuid? uuid})
      : _apiClient = apiClient,
        _uuid = uuid ?? const Uuid();

  final ApiClient _apiClient;
  final Uuid _uuid;

  Future<AccountingSettings> settings() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/accounting/settings');
    return AccountingSettings.fromJson(response.data ?? const {});
  }

  Future<List<AccountingAccount>> accounts() async {
    final response = await _apiClient.dio.get<List<dynamic>>('/accounting/accounts');
    return (response.data ?? const [])
        .map((row) => AccountingAccount.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<JournalSummary>> journals({int limit = 100}) async {
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/accounting/journals',
      queryParameters: {'limit': limit},
    );
    return (response.data ?? const [])
        .map((row) => JournalSummary.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<LedgerRow>> ledger({
    String? accountCode,
    DateTime? start,
    DateTime? end,
  }) async {
    final query = <String, dynamic>{};
    final normalizedCode = _blankToNull(accountCode);
    if (normalizedCode != null) query['account_code'] = normalizedCode;
    if (start != null) query['start'] = start.toUtc().toIso8601String();
    if (end != null) query['end'] = end.toUtc().toIso8601String();
    final response = await _apiClient.dio.get<List<dynamic>>(
      '/accounting/ledger',
      queryParameters: query,
    );
    return (response.data ?? const [])
        .map((row) => LedgerRow.fromJson((row as Map).cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<TrialBalanceReport> trialBalance({DateTime? asOf}) async {
    final query = <String, dynamic>{};
    if (asOf != null) query['as_of'] = asOf.toUtc().toIso8601String();
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/trial-balance',
      queryParameters: query,
    );
    return TrialBalanceReport.fromJson(response.data ?? const {});
  }

  Future<ProfitLossReport> profitLoss({DateTime? start, DateTime? end}) async {
    final query = <String, dynamic>{};
    if (start != null) query['start'] = start.toUtc().toIso8601String();
    if (end != null) query['end'] = end.toUtc().toIso8601String();
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/profit-loss',
      queryParameters: query,
    );
    return ProfitLossReport.fromJson(response.data ?? const {});
  }

  Future<BalanceSheetReport> balanceSheet({DateTime? asOf}) async {
    final query = <String, dynamic>{};
    if (asOf != null) query['as_of'] = asOf.toUtc().toIso8601String();
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/accounting/balance-sheet',
      queryParameters: query,
    );
    return BalanceSheetReport.fromJson(response.data ?? const {});
  }

  Future<ReconciliationReport> reconciliation() async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>('/accounting/reconciliation');
    return ReconciliationReport.fromJson(response.data ?? const {});
  }

  Future<void> lockPeriod({required DateTime lockedThrough, required String reason}) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/accounting/period-lock',
      data: {
        'locked_through': lockedThrough.toUtc().toIso8601String(),
        'reason': reason.trim(),
      },
    );
  }

  Future<void> postManualJournal({
    required String description,
    required List<ManualJournalLineDraft> lines,
    DateTime? occurredAt,
  }) async {
    final data = <String, dynamic>{
      'client_operation_id': _uuid.v4(),
      'description': description.trim(),
      'lines': lines.map(_linePayload).toList(growable: false),
    };
    if (occurredAt != null) data['occurred_at'] = occurredAt.toUtc().toIso8601String();
    await _apiClient.dio.post<Map<String, dynamic>>('/accounting/journals/manual', data: data);
  }

  Future<void> reverseManualJournal({required String journalId, required String reason}) async {
    await _apiClient.dio.post<Map<String, dynamic>>(
      '/accounting/journals/$journalId/reverse',
      data: {
        'client_operation_id': _uuid.v4(),
        'reason': reason.trim(),
      },
    );
  }

  Map<String, dynamic> _linePayload(ManualJournalLineDraft line) {
    final data = <String, dynamic>{
      'account_code': line.accountCode,
      'debit': ScaledDecimal.fromMinor(line.debitMinor),
      'credit': ScaledDecimal.fromMinor(line.creditMinor),
    };
    final memo = _blankToNull(line.memo);
    if (memo != null) data['memo'] = memo;
    return data;
  }
}

DateTime? _dateTimeOrNull(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String? _blankToNull(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? null : text;
}
