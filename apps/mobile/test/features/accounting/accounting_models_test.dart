import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';
import 'package:khanya_pos/features/accounting/domain/cash_flow_report.dart';

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

  test('management summary parses liquidity and working capital', () {
    final report = ManagementSummary.fromJson({
      'cash_on_hand': '120.00',
      'bank': '500.00',
      'cash_equivalents': '80.00',
      'liquid_funds': '700.00',
      'accounts_receivable': '250.00',
      'inventory': '900.00',
      'accounts_payable': '400.00',
      'supplier_advances': '50.00',
      'current_assets': '1900.00',
      'working_capital': '1500.00',
      'sales_revenue': '3000.00',
      'gross_profit': '1200.00',
      'net_profit': '600.00',
      'ledger_healthy': true,
    });

    expect(report.liquidFundsMinor, 70000);
    expect(report.workingCapitalMinor, 150000);
    expect(report.accountsPayableMinor, 40000);
    expect(report.ledgerHealthy, isTrue);
  });

  test('cash flow parses categories and reconciliation', () {
    final report = CashFlowReport.fromJson({
      'opening_cash': '100.00',
      'operating_cash_flow': '250.00',
      'investing_cash_flow': '-50.00',
      'financing_cash_flow': '0.00',
      'net_change_in_cash': '200.00',
      'closing_cash': '300.00',
      'expected_closing_cash': '300.00',
      'difference': '0.00',
      'activities': [
        {
          'entry_number': 'JE-0002',
          'occurred_at': '2026-09-22T06:00:00Z',
          'description': 'Cash sale',
          'source_type': 'sale',
          'category': 'operating',
          'amount': '250.00',
        },
      ],
    });

    expect(report.openingCashMinor, 10000);
    expect(report.netChangeInCashMinor, 20000);
    expect(report.closingCashMinor, 30000);
    expect(report.reconciles, isTrue);
    expect(report.activities.single.category, 'operating');
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
