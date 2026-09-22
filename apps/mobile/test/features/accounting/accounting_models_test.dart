import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';

void main() {
  test('trial balance parses money and balanced status', () {
    final report = TrialBalanceReport.fromJson({
      'total_debits': '150.00',
      'total_credits': '150.00',
      'difference': '0.00',
      'accounts': [
        {
          'code': '1000',
          'name': 'Cash',
          'account_type': 'asset',
          'report_group': 'cash',
          'debits': '150.00',
          'credits': '0.00',
          'balance': '150.00',
        },
      ],
    });

    expect(report.totalDebitsMinor, 15000);
    expect(report.isBalanced, isTrue);
    expect(report.accounts.single.code, '1000');
  });

  test('profit and loss parses headline metrics', () {
    final report = ProfitLossReport.fromJson({
      'sales_revenue': '1000.00',
      'other_income': '50.00',
      'cost_of_sales': '400.00',
      'gross_profit': '600.00',
      'operating_expenses': '200.00',
      'net_profit': '450.00',
      'accounts': const [],
    });

    expect(report.salesRevenueMinor, 100000);
    expect(report.grossProfitMinor, 60000);
    expect(report.netProfitMinor, 45000);
  });

  test('reconciliation aggregates missing journals', () {
    final report = ReconciliationReport.fromJson({
      'healthy': false,
      'trial_balance_difference': '0.00',
      'inventory_difference': '0.00',
      'stock_in_transit_difference': '0.00',
      'accounts_payable_difference': '0.00',
      'supplier_advances_difference': '0.00',
      'missing_sale_journals': 1,
      'missing_purchase_journals': 2,
      'missing_expense_journals': 3,
    });

    expect(report.healthy, isFalse);
    expect(report.missingJournalCount, 6);
  });

  test('journal parses balanced lines', () {
    final journal = JournalEntrySummary.fromJson({
      'id': 'journal-1',
      'entry_number': 'JE-0001',
      'source_type': 'sale',
      'description': 'Sale',
      'occurred_at': '2026-09-22T06:00:00Z',
      'status': 'posted',
      'reversal_of_id': null,
      'lines': [
        {
          'account_code': '1000',
          'account_name': 'Cash',
          'debit': '100.00',
          'credit': '0.00',
          'memo': null,
        },
        {
          'account_code': '4000',
          'account_name': 'Sales',
          'debit': '0.00',
          'credit': '100.00',
          'memo': null,
        },
      ],
    });

    expect(journal.debitTotalMinor, 10000);
    expect(journal.creditTotalMinor, 10000);
  });
}
