import 'package:flutter/services.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class FinancialStatementPrinter {
  const FinancialStatementPrinter._();

  static Future<void> printProfitLoss({
    required ProfitLossReport report,
    required DateTime start,
    required DateTime end,
  }) async {
    final document = await _document(
      title: 'Profit & Loss Statement',
      subtitle: '${_date(start)} – ${_date(end)}',
      summaryRows: [
        _MoneyRow('Sales revenue', report.salesRevenueMinor),
        _MoneyRow('Other income', report.otherIncomeMinor),
        _MoneyRow('Cost of sales', -report.costOfSalesMinor),
        _MoneyRow('Gross profit', report.grossProfitMinor, emphasized: true),
        _MoneyRow('Operating expenses', -report.operatingExpensesMinor),
        _MoneyRow('Net profit', report.netProfitMinor, emphasized: true),
      ],
      detailTitle: 'Account detail',
      detailRows: [
        for (final row in report.accounts) _MoneyRow('${row.code}  ${row.name}', row.amountMinor),
      ],
    );
    await _print(document, 'Khanya-Profit-and-Loss-${_fileDate(end)}.pdf');
  }

  static Future<void> printBalanceSheet({
    required BalanceSheetReport report,
    required DateTime asOf,
  }) async {
    final document = await _document(
      title: 'Balance Sheet',
      subtitle: 'As at ${_date(asOf)}',
      summaryRows: [
        _MoneyRow('Assets', report.assetsMinor, emphasized: true),
        _MoneyRow('Liabilities', report.liabilitiesMinor),
        _MoneyRow('Equity before current earnings', report.equityMinor),
        _MoneyRow('Current earnings', report.currentEarningsMinor),
        _MoneyRow('Equity including current earnings', report.equityIncludingEarningsMinor, emphasized: true),
        _MoneyRow('Liabilities + equity', report.liabilitiesAndEquityMinor, emphasized: true),
        _MoneyRow('Balance sheet difference', report.differenceMinor),
      ],
      status: report.balances ? 'BALANCED' : 'OUT OF BALANCE',
    );
    await _print(document, 'Khanya-Balance-Sheet-${_fileDate(asOf)}.pdf');
  }

  static Future<void> printTrialBalance({
    required TrialBalanceReport report,
    required DateTime asOf,
  }) async {
    final logo = await _logo();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 40),
        header: (context) => _header(
          logo: logo,
          title: 'Trial Balance',
          subtitle: 'As at ${_date(asOf)}',
        ),
        footer: _footer,
        build: (context) => [
          pw.SizedBox(height: 14),
          _statusBanner(report.balances ? 'BALANCED' : 'OUT OF BALANCE', report.balances),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE0E5E1), width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(52),
              1: pw.FlexColumnWidth(2.5),
              2: pw.FlexColumnWidth(1.25),
              3: pw.FlexColumnWidth(1.25),
              4: pw.FlexColumnWidth(1.25),
            },
            children: [
              _tableHeader(['Code', 'Account', 'Debit', 'Credit', 'Balance']),
              for (final row in report.accounts)
                _tableRow([
                  row.code,
                  row.name,
                  _money(row.debitsMinor),
                  _money(row.creditsMinor),
                  _money(row.balanceMinor),
                ]),
              _tableRow(
                [
                  '',
                  'TOTAL',
                  _money(report.totalDebitsMinor),
                  _money(report.totalCreditsMinor),
                  _money(report.differenceMinor),
                ],
                bold: true,
              ),
            ],
          ),
        ],
      ),
    );
    await _print(document, 'Khanya-Trial-Balance-${_fileDate(asOf)}.pdf');
  }

  static Future<pw.Document> _document({
    required String title,
    required String subtitle,
    required List<_MoneyRow> summaryRows,
    List<_MoneyRow> detailRows = const [],
    String? detailTitle,
    String? status,
  }) async {
    final logo = await _logo();
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(38, 34, 38, 42),
        header: (context) => _header(logo: logo, title: title, subtitle: subtitle),
        footer: _footer,
        build: (context) => [
          pw.SizedBox(height: 16),
          if (status != null) ...[
            _statusBanner(status, status == 'BALANCED'),
            pw.SizedBox(height: 14),
          ],
          _moneyTable(summaryRows),
          if (detailRows.isNotEmpty) ...[
            pw.SizedBox(height: 22),
            pw.Text(
              detailTitle ?? 'Detail',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromInt(0xFF003B64),
              ),
            ),
            pw.SizedBox(height: 8),
            _moneyTable(detailRows),
          ],
        ],
      ),
    );
    return document;
  }

  static Future<pw.MemoryImage> _logo() async {
    final bytes = await rootBundle.load('assets/branding/khanya_app_icon_safe.jpg');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static pw.Widget _header({
    required pw.MemoryImage logo,
    required String title,
    required String subtitle,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              width: 54,
              height: 54,
              child: pw.Image(logo, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(width: 14),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'KHANYA RESOURCES',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromInt(0xFF006B3C),
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Management & Consultancy Services',
                    style: pw.TextStyle(fontSize: 8.5, color: PdfColor.fromInt(0xFF003B64)),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'People | Process | Profit | A Brighter Tomorrow',
                    style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF9B6E00)),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromInt(0xFF003B64),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(height: 2.2, color: PdfColor.fromInt(0xFFD8A020)),
        pw.Container(height: 0.8, color: PdfColor.fromInt(0xFF006B3C)),
      ],
    );
  }

  static pw.Widget _footer(pw.Context context) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColor.fromInt(0xFFDDE3DF), thickness: 0.6),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generated from the Khanya POS accounting ledger',
              style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF5E6B64)),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF5E6B64)),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _statusBanner(String text, bool ok) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(ok ? 0xFFE8F5EC : 0xFFFDECEA),
        borderRadius: pw.BorderRadius.circular(5),
        border: pw.Border.all(
          color: PdfColor.fromInt(ok ? 0xFF2F7D4A : 0xFFB3261E),
          width: 0.7,
        ),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromInt(ok ? 0xFF2F7D4A : 0xFFB3261E),
        ),
      ),
    );
  }

  static pw.Widget _moneyTable(List<_MoneyRow> rows) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColor.fromInt(0xFFE0E5E1), width: 0.45),
        bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFBCC6C0), width: 0.7),
      ),
      columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
      children: [
        for (final row in rows)
          pw.TableRow(
            decoration: row.emphasized
                ? pw.BoxDecoration(color: PdfColor.fromInt(0xFFF3F7F4))
                : null,
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: pw.Text(
                  row.label,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: row.emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
                  ),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Text(
                    _money(row.amountMinor),
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: row.emphasized ? pw.FontWeight.bold : pw.FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  static pw.TableRow _tableHeader(List<String> values) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFF006B3C)),
      children: [
        for (final value in values)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
            child: pw.Text(
              value,
              style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: value == 'Debit' || value == 'Credit' || value == 'Balance'
                  ? pw.TextAlign.right
                  : pw.TextAlign.left,
            ),
          ),
      ],
    );
  }

  static pw.TableRow _tableRow(List<String> values, {bool bold = false}) {
    return pw.TableRow(
      children: [
        for (var index = 0; index < values.length; index++)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: pw.Text(
              values[index],
              style: pw.TextStyle(fontSize: 7.6, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
              textAlign: index >= 2 ? pw.TextAlign.right : pw.TextAlign.left,
            ),
          ),
      ],
    );
  }

  static Future<void> _print(pw.Document document, String name) async {
    await Printing.layoutPdf(
      name: name,
      onLayout: (format) async => document.save(),
    );
  }

  static String _money(int minor) => Loti.formatMinor(minor);

  static String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  static String _fileDate(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
}

class _MoneyRow {
  const _MoneyRow(this.label, this.amountMinor, {this.emphasized = false});

  final String label;
  final int amountMinor;
  final bool emphasized;
}
