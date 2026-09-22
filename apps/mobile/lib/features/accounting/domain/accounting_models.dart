import 'package:equatable/equatable.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

class AccountingSettings extends Equatable {
  const AccountingSettings({
    required this.baseCurrency,
    required this.fiscalYearStartMonth,
    required this.lockedThrough,
    required this.lockReason,
  });

  factory AccountingSettings.fromJson(Map<String, dynamic> json) => AccountingSettings(
        baseCurrency: json['base_currency']?.toString() ?? 'LSL',
        fiscalYearStartMonth: (json['fiscal_year_start_month'] as num?)?.toInt() ?? 1,
        lockedThrough: json['locked_through'] == null
            ? null
            : DateTime.tryParse(json['locked_through'].toString()),
        lockReason: json['lock_reason']?.toString(),
      );

  final String baseCurrency;
  final int fiscalYearStartMonth;
  final DateTime? lockedThrough;
  final String? lockReason;

  @override
  List<Object?> get props => [baseCurrency, fiscalYearStartMonth, lockedThrough, lockReason];
}

class TrialBalanceReport extends Equatable {
  const TrialBalanceReport({
    required this.accounts,
    required this.totalDebitsMinor,
    required this.totalCreditsMinor,
    required this.differenceMinor,
  });

  factory TrialBalanceReport.fromJson(Map<String, dynamic> json) => TrialBalanceReport(
        accounts: (json['accounts'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => TrialBalanceAccount.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
        totalDebitsMinor: ScaledDecimal.toMinor(json['total_debits']),
        totalCreditsMinor: ScaledDecimal.toMinor(json['total_credits']),
        differenceMinor: ScaledDecimal.toMinor(json['difference']),
      );

  final List<TrialBalanceAccount> accounts;
  final int totalDebitsMinor;
  final int totalCreditsMinor;
  final int differenceMinor;

  bool get isBalanced => differenceMinor == 0;

  @override
  List<Object?> get props => [accounts, totalDebitsMinor, totalCreditsMinor, differenceMinor];
}

class TrialBalanceAccount extends Equatable {
  const TrialBalanceAccount({
    required this.code,
    required this.name,
    required this.accountType,
    required this.reportGroup,
    required this.debitsMinor,
    required this.creditsMinor,
    required this.balanceMinor,
  });

  factory TrialBalanceAccount.fromJson(Map<String, dynamic> json) => TrialBalanceAccount(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        accountType: json['account_type']?.toString() ?? '',
        reportGroup: json['report_group']?.toString() ?? '',
        debitsMinor: ScaledDecimal.toMinor(json['debits']),
        creditsMinor: ScaledDecimal.toMinor(json['credits']),
        balanceMinor: ScaledDecimal.toMinor(json['balance']),
      );

  final String code;
  final String name;
  final String accountType;
  final String reportGroup;
  final int debitsMinor;
  final int creditsMinor;
  final int balanceMinor;

  @override
  List<Object?> get props => [code, name, accountType, reportGroup, debitsMinor, creditsMinor, balanceMinor];
}

class ProfitLossReport extends Equatable {
  const ProfitLossReport({
    required this.salesRevenueMinor,
    required this.otherIncomeMinor,
    required this.costOfSalesMinor,
    required this.grossProfitMinor,
    required this.operatingExpensesMinor,
    required this.netProfitMinor,
    required this.accounts,
  });

  factory ProfitLossReport.fromJson(Map<String, dynamic> json) => ProfitLossReport(
        salesRevenueMinor: ScaledDecimal.toMinor(json['sales_revenue'] ?? json['revenue']),
        otherIncomeMinor: ScaledDecimal.toMinor(json['other_income']),
        costOfSalesMinor: ScaledDecimal.toMinor(json['cost_of_sales']),
        grossProfitMinor: ScaledDecimal.toMinor(json['gross_profit']),
        operatingExpensesMinor: ScaledDecimal.toMinor(json['operating_expenses']),
        netProfitMinor: ScaledDecimal.toMinor(json['net_profit']),
        accounts: (json['accounts'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => ProfitLossAccount.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final int salesRevenueMinor;
  final int otherIncomeMinor;
  final int costOfSalesMinor;
  final int grossProfitMinor;
  final int operatingExpensesMinor;
  final int netProfitMinor;
  final List<ProfitLossAccount> accounts;

  @override
  List<Object?> get props => [
        salesRevenueMinor,
        otherIncomeMinor,
        costOfSalesMinor,
        grossProfitMinor,
        operatingExpensesMinor,
        netProfitMinor,
        accounts,
      ];
}

class ProfitLossAccount extends Equatable {
  const ProfitLossAccount({
    required this.code,
    required this.name,
    required this.reportGroup,
    required this.amountMinor,
  });

  factory ProfitLossAccount.fromJson(Map<String, dynamic> json) => ProfitLossAccount(
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        reportGroup: json['report_group']?.toString() ?? '',
        amountMinor: ScaledDecimal.toMinor(json['amount']),
      );

  final String code;
  final String name;
  final String reportGroup;
  final int amountMinor;

  @override
  List<Object?> get props => [code, name, reportGroup, amountMinor];
}

class BalanceSheetReport extends Equatable {
  const BalanceSheetReport({
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.equityMinor,
    required this.currentEarningsMinor,
    required this.equityIncludingEarningsMinor,
    required this.liabilitiesAndEquityMinor,
    required this.differenceMinor,
  });

  factory BalanceSheetReport.fromJson(Map<String, dynamic> json) => BalanceSheetReport(
        assetsMinor: ScaledDecimal.toMinor(json['assets']),
        liabilitiesMinor: ScaledDecimal.toMinor(json['liabilities']),
        equityMinor: ScaledDecimal.toMinor(json['equity']),
        currentEarningsMinor: ScaledDecimal.toMinor(json['current_earnings']),
        equityIncludingEarningsMinor: ScaledDecimal.toMinor(json['equity_including_current_earnings']),
        liabilitiesAndEquityMinor: ScaledDecimal.toMinor(json['liabilities_and_equity']),
        differenceMinor: ScaledDecimal.toMinor(json['difference']),
      );

  final int assetsMinor;
  final int liabilitiesMinor;
  final int equityMinor;
  final int currentEarningsMinor;
  final int equityIncludingEarningsMinor;
  final int liabilitiesAndEquityMinor;
  final int differenceMinor;

  bool get isBalanced => differenceMinor == 0;

  @override
  List<Object?> get props => [
        assetsMinor,
        liabilitiesMinor,
        equityMinor,
        currentEarningsMinor,
        equityIncludingEarningsMinor,
        liabilitiesAndEquityMinor,
        differenceMinor,
      ];
}

class ReconciliationReport extends Equatable {
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

  final bool healthy;
  final int trialBalanceDifferenceMinor;
  final int inventoryDifferenceMinor;
  final int stockInTransitDifferenceMinor;
  final int accountsPayableDifferenceMinor;
  final int supplierAdvancesDifferenceMinor;
  final int missingSaleJournals;
  final int missingPurchaseJournals;
  final int missingExpenseJournals;

  int get missingJournalCount => missingSaleJournals + missingPurchaseJournals + missingExpenseJournals;

  @override
  List<Object?> get props => [
        healthy,
        trialBalanceDifferenceMinor,
        inventoryDifferenceMinor,
        stockInTransitDifferenceMinor,
        accountsPayableDifferenceMinor,
        supplierAdvancesDifferenceMinor,
        missingSaleJournals,
        missingPurchaseJournals,
        missingExpenseJournals,
      ];
}

class JournalEntrySummary extends Equatable {
  const JournalEntrySummary({
    required this.id,
    required this.entryNumber,
    required this.sourceType,
    required this.description,
    required this.occurredAt,
    required this.status,
    required this.reversalOfId,
    required this.lines,
  });

  factory JournalEntrySummary.fromJson(Map<String, dynamic> json) => JournalEntrySummary(
        id: json['id']?.toString() ?? '',
        entryNumber: json['entry_number']?.toString() ?? '',
        sourceType: json['source_type']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        status: json['status']?.toString() ?? '',
        reversalOfId: json['reversal_of_id']?.toString(),
        lines: (json['lines'] as List<dynamic>? ?? const <dynamic>[])
            .map((item) => JournalLineSummary.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );

  final String id;
  final String entryNumber;
  final String sourceType;
  final String description;
  final DateTime occurredAt;
  final String status;
  final String? reversalOfId;
  final List<JournalLineSummary> lines;

  int get debitTotalMinor => lines.fold(0, (total, line) => total + line.debitMinor);
  int get creditTotalMinor => lines.fold(0, (total, line) => total + line.creditMinor);

  @override
  List<Object?> get props => [id, entryNumber, sourceType, description, occurredAt, status, reversalOfId, lines];
}

class JournalLineSummary extends Equatable {
  const JournalLineSummary({
    required this.accountCode,
    required this.accountName,
    required this.debitMinor,
    required this.creditMinor,
    required this.memo,
  });

  factory JournalLineSummary.fromJson(Map<String, dynamic> json) => JournalLineSummary(
        accountCode: json['account_code']?.toString() ?? '',
        accountName: json['account_name']?.toString() ?? '',
        debitMinor: ScaledDecimal.toMinor(json['debit']),
        creditMinor: ScaledDecimal.toMinor(json['credit']),
        memo: json['memo']?.toString(),
      );

  final String accountCode;
  final String accountName;
  final int debitMinor;
  final int creditMinor;
  final String? memo;

  @override
  List<Object?> get props => [accountCode, accountName, debitMinor, creditMinor, memo];
}

class LedgerLine extends Equatable {
  const LedgerLine({
    required this.entryNumber,
    required this.occurredAt,
    required this.sourceType,
    required this.description,
    required this.accountCode,
    required this.accountName,
    required this.debitMinor,
    required this.creditMinor,
  });

  factory LedgerLine.fromJson(Map<String, dynamic> json) => LedgerLine(
        entryNumber: json['entry_number']?.toString() ?? '',
        occurredAt: DateTime.tryParse(json['occurred_at']?.toString() ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
        sourceType: json['source_type']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        accountCode: json['account_code']?.toString() ?? '',
        accountName: json['account_name']?.toString() ?? '',
        debitMinor: ScaledDecimal.toMinor(json['debit']),
        creditMinor: ScaledDecimal.toMinor(json['credit']),
      );

  final String entryNumber;
  final DateTime occurredAt;
  final String sourceType;
  final String description;
  final String accountCode;
  final String accountName;
  final int debitMinor;
  final int creditMinor;

  @override
  List<Object?> get props => [entryNumber, occurredAt, sourceType, description, accountCode, accountName, debitMinor, creditMinor];
}

class AccountingWorkspaceData extends Equatable {
  const AccountingWorkspaceData({
    required this.settings,
    required this.trialBalance,
    required this.profitLoss,
    required this.balanceSheet,
    required this.reconciliation,
    required this.journals,
    required this.ledger,
  });

  final AccountingSettings settings;
  final TrialBalanceReport trialBalance;
  final ProfitLossReport profitLoss;
  final BalanceSheetReport balanceSheet;
  final ReconciliationReport reconciliation;
  final List<JournalEntrySummary> journals;
  final List<LedgerLine> ledger;

  @override
  List<Object?> get props => [settings, trialBalance, profitLoss, balanceSheet, reconciliation, journals, ledger];
}
