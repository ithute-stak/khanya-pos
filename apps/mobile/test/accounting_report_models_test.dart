import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';

void main() {
  test('parses trial balance amounts without losing cents', () {
    final report = TrialBalanceReport.fromJson({
      'accounts': [
        {
          'account_id': 'a1',
          'code': '1000',
          'name': 'Cash',
          'account_type': 'asset',
          'report_group': 'cash',
          'normal_balance': 'debit',
          'debits': '1250.55',
          'credits': '250.05',
          'balance': '1000.50',
        }
      ],
      'total_debits': '1250.55',
      'total_credits': '1250.55',
      'difference': '0.00',
    });

    expect(report.accounts.single.balanceMinor, 100050);
    expect(report.totalDebitsMinor, 125055);
    expect(report.totalCreditsMinor, 125055);
    expect(report.balances, isTrue);
  });

  test('parses profit and loss and balance sheet summaries', () {
    final profitLoss = ProfitLossReport.fromJson({
      'sales_revenue': '5000.00',
      'other_income': '100.00',
      'cost_of_sales': '2750.00',
      'gross_profit': '2250.00',
      'operating_expenses': '850.25',
      'net_profit': '1499.75',
      'accounts': [
        {'code': '4000', 'name': 'Sales Revenue', 'report_group': 'revenue', 'amount': '5000.00'}
      ],
    });
    final balanceSheet = BalanceSheetReport.fromJson({
      'assets': '12000.00',
      'liabilities': '3500.00',
      'equity': '7000.25',
      'current_earnings': '1499.75',
      'equity_including_current_earnings': '8500.00',
      'liabilities_and_equity': '12000.00',
      'difference': '0.00',
    });

    expect(profitLoss.netProfitMinor, 149975);
    expect(profitLoss.accounts.single.amountMinor, 500000);
    expect(balanceSheet.assetsMinor, 1200000);
    expect(balanceSheet.balances, isTrue);
  });

  test('parses reconciliation health indicators', () {
    final report = ReconciliationReport.fromJson({
      'healthy': false,
      'trial_balance_difference': '0.00',
      'inventory_difference': '10.50',
      'stock_in_transit_difference': '0.00',
      'accounts_payable_difference': '-2.25',
      'supplier_advances_difference': '0.00',
      'missing_sale_journals': 1,
      'missing_purchase_journals': 0,
      'missing_expense_journals': 2,
    });

    expect(report.healthy, isFalse);
    expect(report.inventoryDifferenceMinor, 1050);
    expect(report.accountsPayableDifferenceMinor, -225);
    expect(report.missingSaleJournals, 1);
    expect(report.missingExpenseJournals, 2);
  });

  test('parses journals and ledger rows for accountant review', () {
    final journal = JournalSummary.fromJson({
      'id': 'j1',
      'entry_number': 'JE-0001',
      'source_type': 'sale',
      'description': 'Sale S-100',
      'occurred_at': '2026-09-22T06:00:00Z',
      'reversal_of_id': null,
      'reversal_reason': null,
      'lines': [
        {
          'id': 'l1',
          'account_id': 'a1',
          'account_code': '1000',
          'account_name': 'Cash',
          'debit': '250.00',
          'credit': '0.00',
          'memo': 'Cash tender',
        },
        {
          'id': 'l2',
          'account_id': 'a2',
          'account_code': '4000',
          'account_name': 'Sales Revenue',
          'debit': '0.00',
          'credit': '250.00',
          'memo': null,
        },
      ],
    });
    final ledger = LedgerRow.fromJson({
      'journal_entry_id': 'j1',
      'entry_number': 'JE-0001',
      'occurred_at': '2026-09-22T06:00:00Z',
      'source_type': 'sale',
      'source_id': 's1',
      'description': 'Sale S-100',
      'account_code': '1000',
      'account_name': 'Cash',
      'debit': '250.00',
      'credit': '0.00',
      'memo': 'Cash tender',
    });

    expect(journal.totalDebitMinor, 25000);
    expect(journal.lines.length, 2);
    expect(ledger.accountCode, '1000');
    expect(ledger.debitMinor, 25000);
  });
}
