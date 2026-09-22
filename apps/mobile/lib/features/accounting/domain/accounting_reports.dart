import 'package:khanya_pos/core/money/scaled_decimal.dart';

int _money(dynamic value) => ScaledDecimal.toMinor(value);

class TrialBalanceRow {
  const TrialBalanceRow({
    required this.code,
    required this.name,
    required this.accountType,
    required this.reportGroup,
    required this.debitsMinor,
    required this.creditsMinor,
    required this.balanceMinor,
  });

  final String code;
  final String name;
  final String accountType;
  final String reportGroup;
  final int debitsMinor;
  final int creditsMinor;
  final int balanceMinor;

  factory TrialBalanceRow.fromJson(Map<String, dynamic> json) => TrialBalanceRow(
        code: json['code'].toString(),
        name: json['name'].toString(),
        accountType: json['account_type'].toString(),
        reportGroup: json['report_group'].toString(),
        debitsMinor: _money(json['debits']),
        creditsMinor: _money(json['credits']),
        balanceMinor: _money(json['balance']),
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

  bool get isBalanced => differenceMinor == 0;

  factory TrialBalanceReport.fromJson(Map<String, dynamic> json) => TrialBalanceReport(
        accounts: (json['accounts'] as List<dynamic>? ?? const [])
            .map((row) => TrialBalanceRow.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
        totalDebitsMinor: _money(json['total_debits']),
        totalCreditsMinor: _money(json['total_credits']),
        differenceMinor: _money(json['difference']),
      );
}

class ProfitLossAccount {
  const ProfitLossAccount({
    required this.code,
    required this.name,
    required this.reportGroup,
    required this.amountMinor,
  });

  final String code;
  final String name;
  final String reportGroup;
  final int amountMinor;

  factory ProfitLossAccount.fromJson(Map<String, dynamic> json) => ProfitLossAccount(
        code: json['code'].toString(),
        name: json['name'].toString(),
        reportGroup: json['report_group'].toString(),
        amountMinor: _money(json['amount']),
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
  final List<ProfitLossAccount> accounts;

  factory ProfitLossReport.fromJson(Map<String, dynamic> json) => ProfitLossReport(
        salesRevenueMinor: _money(json['sales_revenue']),
        otherIncomeMinor: _money(json['other_income']),
        costOfSalesMinor: _money(json['cost_of_sales']),
        grossProfitMinor: _money(json['gross_profit']),
        operatingExpensesMinor: _money(json['operating_expenses']),
        netProfitMinor: _money(json['net_profit']),
        accounts: (json['accounts'] as List<dynamic>? ?? const [])
            .map((row) => ProfitLossAccount.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class BalanceSheetReport {
  const BalanceSheetReport({
    required this.assetsMinor,
    required this.liabilitiesMinor,
    required this.equityMinor,
    required this.currentEarningsMinor,
    required this.equityIncludingCurrentEarningsMinor,
    required this.liabilitiesAndEquityMinor,
    required this.differenceMinor,
  });

  final int assetsMinor;
  final int liabilitiesMinor;
  final int equityMinor;
  final int currentEarningsMinor;
  final int equityIncludingCurrentEarningsMinor;
  final int liabilitiesAndEquityMinor;
  final int differenceMinor;

  bool get isBalanced => differenceMinor == 0;

  factory BalanceSheetReport.fromJson(Map<String, dynamic> json) => BalanceSheetReport(
        assetsMinor: _money(json['assets']),
        liabilitiesMinor: _money(json['liabilities']),
        equityMinor: _money(json['equity']),
        currentEarningsMinor: _money(json['current_earnings']),
        equityIncludingCurrentEarningsMinor: _money(json['equity_including_current_earnings']),
        liabilitiesAndEquityMinor: _money(json['liabilities_and_equity']),
        differenceMinor: _money(json['difference']),
      );
}

class LedgerRow {
  const LedgerRow({
    required this.journalEntryId,
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

  final String journalEntryId;
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
        journalEntryId: json['journal_entry_id'].toString(),
        entryNumber: json['entry_number'].toString(),
        occurredAt: DateTime.parse(json['occurred_at'].toString()).toLocal(),
        sourceType: json['source_type'].toString(),
        description: json['description'].toString(),
        accountCode: json['account_code'].toString(),
        accountName: json['account_name'].toString(),
        debitMinor: _money(json['debit']),
        creditMinor: _money(json['credit']),
        memo: json['memo']?.toString(),
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
        debitMinor: _money(json['debit']),
        creditMinor: _money(json['credit']),
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
    required this.status,
    required this.lines,
  });

  final String id;
  final String entryNumber;
  final String sourceType;
  final String description;
  final DateTime occurredAt;
  final String status;
  final List<JournalLineSummary> lines;

  int get totalDebitsMinor => lines.fold(0, (sum, line) => sum + line.debitMinor);
  int get totalCreditsMinor => lines.fold(0, (sum, line) => sum + line.creditMinor);

  factory JournalSummary.fromJson(Map<String, dynamic> json) => JournalSummary(
        id: json['id'].toString(),
        entryNumber: json['entry_number'].toString(),
        sourceType: json['source_type'].toString(),
        description: json['description'].toString(),
        occurredAt: DateTime.parse(json['occurred_at'].toString()).toLocal(),
        status: json['status'].toString(),
        lines: (json['lines'] as List<dynamic>? ?? const [])
            .map((row) => JournalLineSummary.fromJson((row as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class LedgerReconciliation {
  const LedgerReconciliation({
    required this.healthy,
    required this.trialBalanceDifferenceMinor,
    required this.inventoryDifferenceMinor,
    required this.transitDifferenceMinor,
    required this.accountsPayableDifferenceMinor,
    required this.supplierAdvancesDifferenceMinor,
    required this.missingSaleJournals,
    required this.missingPurchaseJournals,
    required this.missingExpenseJournals,
  });

  final bool healthy;
  final int trialBalanceDifferenceMinor;
  final int inventoryDifferenceMinor;
  final int transitDifferenceMinor;
  final int accountsPayableDifferenceMinor;
  final int supplierAdvancesDifferenceMinor;
  final int missingSaleJournals;
  final int missingPurchaseJournals;
  final int missingExpenseJournals;

  factory LedgerReconciliation.fromJson(Map<String, dynamic> json) => LedgerReconciliation(
        healthy: json['healthy'] as bool? ?? false,
        trialBalanceDifferenceMinor: _money(json['trial_balance_difference']),
        inventoryDifferenceMinor: _money(json['inventory_difference']),
        transitDifferenceMinor: _money(json['stock_in_transit_difference']),
        accountsPayableDifferenceMinor: _money(json['accounts_payable_difference']),
        supplierAdvancesDifferenceMinor: _money(json['supplier_advances_difference']),
        missingSaleJournals: (json['missing_sale_journals'] as num?)?.toInt() ?? 0,
        missingPurchaseJournals: (json['missing_purchase_journals'] as num?)?.toInt() ?? 0,
        missingExpenseJournals: (json['missing_expense_journals'] as num?)?.toInt() ?? 0,
      );
}

class AccountingSnapshot {
  const AccountingSnapshot({
    required this.trialBalance,
    required this.profitLoss,
    required this.balanceSheet,
    required this.ledger,
    required this.journals,
    required this.reconciliation,
  });

  final TrialBalanceReport trialBalance;
  final ProfitLossReport profitLoss;
  final BalanceSheetReport balanceSheet;
  final List<LedgerRow> ledger;
  final List<JournalSummary> journals;
  final LedgerReconciliation reconciliation;
}
