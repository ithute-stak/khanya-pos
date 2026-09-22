import 'dart:typed_data';

import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_reports.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FinancialReportPdfService {
  const FinancialReportPdfService._();

  static Future<void> printProfitLoss({
    required ProfitLossReport report,
    required DateTime start,
    required DateTime end,
  }) async {
    final document = _document(
      title: 'Profit & Loss Statement',
      subtitle: '${_date(start)} to ${_date(end)}',
      body: [
        _moneyRow('Sales revenue', report.salesRevenueMinor),
        _moneyRow('Other income', report.otherIncomeMinor),
        _moneyRow('Cost of sales', -report.costOfSalesMinor),
        _rule(),
        _moneyRow('Gross profit', report.grossProfitMinor, bold: true),
        _moneyRow('Operating expenses', -report.operatingExpensesMinor),
        _rule(),
        _moneyRow('Net profit / (loss)', report.netProfitMinor, bold: true),
        pw.SizedBox(height: 16),
        pw.Text('Account detail', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.SizedBox(height: 6),
        for (final account in report.accounts)
          _detailRow('${account.code}  ${account.name}', Loti.formatMinor(account.amountMinor)),
      ],
    );
    await _print(document);
  }

  static Future<void> printBalanceSheet({
    required BalanceSheetReport report,
    required DateTime asOf,
  }) async {
    final document = _document(
      title: 'Balance Sheet',
      subtitle: 'As at ${_date(asOf)}',
      body: [
        _moneyRow('Total assets', report.assetsMinor, bold: true),
        pw.SizedBox(height: 8),
        _moneyRow('Liabilities', report.liabilitiesMinor),
        _moneyRow('Equity before current earnings', report.equityMinor),
        _moneyRow('Current earnings', report.currentEarningsMinor),
        _rule(),
        _moneyRow('Equity including current earnings', report.equityIncludingCurrentEarningsMinor, bold: true),
        _moneyRow('Liabilities + equity', report.liabilitiesAndEquityMinor, bold: true),
        _rule(),
        _moneyRow('Balance sheet difference', report.differenceMinor),
        pw.SizedBox(height: 12),
        pw.Text(
          report.isBalanced ? 'Status: BALANCED' : 'Status: OUT OF BALANCE',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
    await _print(document);
  }

  static Future<void> printTrialBalance({
    required TrialBalanceReport report,
    required DateTime asOf,
  }) async {
    final body = <pw.Widget>[
      _trialHeader(),
      for (final account in report.accounts)
        _trialRow(
          account.code,
          account.name,
          Loti.formatMinor(account.debitsMinor),
          Loti.formatMinor(account.creditsMinor),
          Loti.formatMinor(account.balanceMinor),
        ),
      _rule(),
      _trialRow(
        '',
        'TOTAL',
        Loti.formatMinor(report.totalDebitsMinor),
        Loti.formatMinor(report.totalCreditsMinor),
        Loti.formatMinor(report.differenceMinor),
        bold: true,
      ),
    ];
    final document = _document(
      title: 'Trial Balance',
      subtitle: 'As at ${_date(asOf)}',
      body: body,
    );
    await _print(document);
  }

  static pw.Document _document({
    required String title,
    required String subtitle,
    required List<pw.Widget> body,
  }) {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'KHANYA RESOURCES',
                      style: pw.TextStyle(
                        fontSize: 15,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#006B3C'),
                      ),
                    ),
                    pw.Text('Management & Consultancy Services', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
                pw.Text('Currency: LSL', style: const pw.TextStyle(fontSize: 8)),
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Text(title, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 12),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Khanya POS • Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        build: (_) => body,
      ),
    );
    return document;
  }

  static pw.Widget _moneyRow(String label, int valueMinor, {bool bold = false}) {
    final style = pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: style)),
          pw.Text(Loti.formatMinor(valueMinor), style: style),
        ],
      ),
    );
  }

  static pw.Widget _detailRow(String label, String amount) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Row(
          children: [
            pw.Expanded(child: pw.Text(label, style: const pw.TextStyle(fontSize: 8.5))),
            pw.Text(amount, style: const pw.TextStyle(fontSize: 8.5)),
          ],
        ),
      );

  static pw.Widget _trialHeader() => pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 5),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.6))),
        child: pw.Row(
          children: [
            pw.SizedBox(width: 42, child: pw.Text('Code', style: _smallBold)),
            pw.Expanded(child: pw.Text('Account', style: _smallBold)),
            pw.SizedBox(width: 75, child: pw.Text('Debits', style: _smallBold, textAlign: pw.TextAlign.right)),
            pw.SizedBox(width: 75, child: pw.Text('Credits', style: _smallBold, textAlign: pw.TextAlign.right)),
            pw.SizedBox(width: 75, child: pw.Text('Balance', style: _smallBold, textAlign: pw.TextAlign.right)),
          ],
        ),
      );

  static pw.Widget _trialRow(
    String code,
    String account,
    String debits,
    String credits,
    String balance, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(fontSize: 7.5, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 42, child: pw.Text(code, style: style)),
          pw.Expanded(child: pw.Text(account, style: style)),
          pw.SizedBox(width: 75, child: pw.Text(debits, style: style, textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 75, child: pw.Text(credits, style: style, textAlign: pw.TextAlign.right)),
          pw.SizedBox(width: 75, child: pw.Text(balance, style: style, textAlign: pw.TextAlign.right)),
        ],
      ),
    );
  }

  static pw.Widget _rule() => pw.Divider(height: 10, thickness: 0.5);

  static const _smallBold = pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold);

  static Future<void> _print(pw.Document document) async {
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(await document.save()),
    );
  }

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
}
