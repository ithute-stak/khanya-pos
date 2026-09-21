import 'dart:typed_data';

import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class SaleReceiptLine {
  const SaleReceiptLine({
    required this.name,
    required this.quantity,
    required this.unitPriceMinor,
    required this.lineTotalMinor,
    this.sku,
  });

  factory SaleReceiptLine.fromCartLine(CartLine line) => SaleReceiptLine(
        name: line.product.name,
        sku: line.product.sku,
        quantity: line.quantity,
        unitPriceMinor: line.product.priceMinor,
        lineTotalMinor: line.lineTotalMinor,
      );

  final String name;
  final String? sku;
  final int quantity;
  final int unitPriceMinor;
  final int lineTotalMinor;
}

class SaleReceipt {
  const SaleReceipt({
    required this.businessName,
    required this.reference,
    required this.issuedAt,
    required this.lines,
    required this.paymentMethod,
    required this.syncStatus,
    this.branchId,
    this.cashierName,
    this.customerName,
    this.paidNowMinor,
    this.balanceDueMinor,
    this.cashTenderedMinor,
  });

  final String businessName;
  final String reference;
  final DateTime issuedAt;
  final List<SaleReceiptLine> lines;
  final PaymentMethod paymentMethod;
  final String syncStatus;
  final String? branchId;
  final String? cashierName;
  final String? customerName;
  final int? paidNowMinor;
  final int? balanceDueMinor;
  final int? cashTenderedMinor;

  int get totalMinor => lines.fold(0, (total, line) => total + line.lineTotalMinor);
  int get paidMinor => paidNowMinor ?? totalMinor;
  int get creditBalanceMinor => balanceDueMinor ?? (totalMinor - paidMinor).clamp(0, totalMinor);
  bool get isCreditSale => creditBalanceMinor > 0;

  int? get cashChangeMinor {
    final tendered = cashTenderedMinor;
    if (paymentMethod != PaymentMethod.cash || tendered == null || paidMinor <= 0) return null;
    return tendered > paidMinor ? tendered - paidMinor : 0;
  }
}

String formatMalotiMinor(int minor) {
  final negative = minor < 0;
  final absolute = minor.abs();
  final whole = absolute ~/ 100;
  final cents = (absolute % 100).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}M $whole.$cents';
}

PdfPageFormat saleReceiptPageFormat(
  SaleReceipt receipt, {
  int paperWidthMm = 80,
}) {
  final widthMm = paperWidthMm == 58 ? 58 : 80;
  final lineCount = receipt.lines.isEmpty ? 1 : receipt.lines.length;
  final perLineMm = widthMm == 58 ? 20 : 15;
  final cashExtraMm = receipt.cashTenderedMinor == null ? 0 : 12;
  final creditExtraMm = receipt.isCreditSale ? 18 : 0;
  final customerExtraMm = receipt.customerName == null ? 0 : 8;
  final heightMm = (115 + cashExtraMm + creditExtraMm + customerExtraMm + (lineCount * perLineMm))
      .clamp(140, 2000)
      .toDouble();
  final margin = 4 * PdfPageFormat.mm;
  return PdfPageFormat(
    widthMm * PdfPageFormat.mm,
    heightMm * PdfPageFormat.mm,
    marginLeft: margin,
    marginRight: margin,
    marginTop: margin,
    marginBottom: margin,
  );
}

Future<Uint8List> buildSaleReceiptPdf(
  SaleReceipt receipt, {
  int paperWidthMm = 80,
}) async {
  final document = pw.Document(
    title: 'Khanya POS Receipt ${receipt.reference}',
    author: 'Khanya POS',
    creator: 'Khanya POS',
  );

  final paper = saleReceiptPageFormat(receipt, paperWidthMm: paperWidthMm);

  document.addPage(
    pw.Page(
      pageFormat: paper,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            receipt.businessName.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          pw.Text(
            'KHANYA POS',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            receipt.isCreditSale ? 'Sales / Credit Receipt' : 'Sales Receipt',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
          pw.SizedBox(height: 3 * PdfPageFormat.mm),
          _receiptPair('Reference', _shortReference(receipt.reference)),
          _receiptPair('Date', _formatReceiptDate(receipt.issuedAt)),
          if (receipt.branchId != null && receipt.branchId!.isNotEmpty)
            _receiptPair('Branch', receipt.branchId!),
          if (receipt.cashierName != null && receipt.cashierName!.isNotEmpty)
            _receiptPair('Cashier', receipt.cashierName!),
          if (receipt.customerName != null && receipt.customerName!.isNotEmpty)
            _receiptPair('Customer', receipt.customerName!),
          if (receipt.paidMinor > 0) _receiptPair('Payment', receipt.paymentMethod.label),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          pw.Divider(height: 1),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          ...receipt.lines.expand(
            (line) => [
              pw.Text(
                line.name,
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
              ),
              if (line.sku != null && line.sku!.trim().isNotEmpty)
                pw.Text('SKU: ${line.sku}', style: const pw.TextStyle(fontSize: 7)),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    '${line.quantity} x ${formatMalotiMinor(line.unitPriceMinor)}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    formatMalotiMinor(line.lineTotalMinor),
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              pw.SizedBox(height: 2.5 * PdfPageFormat.mm),
            ],
          ),
          pw.Divider(height: 1),
          pw.SizedBox(height: 2 * PdfPageFormat.mm),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('TOTAL', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                formatMalotiMinor(receipt.totalMinor),
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          if (receipt.isCreditSale) ...[
            pw.SizedBox(height: 2 * PdfPageFormat.mm),
            _receiptPair('Paid now', formatMalotiMinor(receipt.paidMinor)),
            _receiptPair('Balance due', formatMalotiMinor(receipt.creditBalanceMinor)),
          ],
          if (receipt.cashTenderedMinor != null && receipt.paidMinor > 0) ...[
            pw.SizedBox(height: 2 * PdfPageFormat.mm),
            _receiptPair('Cash received', formatMalotiMinor(receipt.cashTenderedMinor!)),
            _receiptPair('Change', formatMalotiMinor(receipt.cashChangeMinor ?? 0)),
          ],
          pw.SizedBox(height: 3 * PdfPageFormat.mm),
          pw.Text(
            'Sync status: ${receipt.syncStatus}',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.SizedBox(height: 3 * PdfPageFormat.mm),
          pw.Text(
            'Thank you for your business.',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 1.5 * PdfPageFormat.mm),
          pw.Text(
            'People | Process | Profit | A Brighter Tomorrow',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 6.5),
          ),
        ],
      ),
    ),
  );

  return document.save();
}

pw.Widget _receiptPair(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 19 * PdfPageFormat.mm,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 7.5)),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );

String _shortReference(String value) {
  if (value.length <= 18) return value;
  return value.substring(0, 18);
}

String _formatReceiptDate(DateTime dateTime) {
  final local = dateTime.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}
