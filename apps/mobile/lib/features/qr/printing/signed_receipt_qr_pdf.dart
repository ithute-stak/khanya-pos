import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:khanya_pos/features/qr/data/qr_sale_receipt_repository.dart';

/// A QR lookup slip for an existing server-recorded sale, not proof of payment.
Future<Uint8List> buildSignedReceiptQrPdf(SignedSaleReceiptQr receipt) async {
  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a6,
    margin: pw.EdgeInsets.all(12 * PdfPageFormat.mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text('KHANYA POS',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4 * PdfPageFormat.mm),
        pw.Text('Sale receipt QR lookup', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 8 * PdfPageFormat.mm),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: receipt.token,
          width: 62 * PdfPageFormat.mm,
          height: 62 * PdfPageFormat.mm,
          drawText: false,
        ),
        pw.SizedBox(height: 7 * PdfPageFormat.mm),
        pw.Text(receipt.saleNumber,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 3 * PdfPageFormat.mm),
        pw.Text(
          'Scan in Khanya POS to look up this sale. '
          'Access requires an authorized account.',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 9),
        ),
        pw.SizedBox(height: 4 * PdfPageFormat.mm),
        pw.Text('Not proof of payment or refund eligibility',
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  ));
  return pdf.save();
}
