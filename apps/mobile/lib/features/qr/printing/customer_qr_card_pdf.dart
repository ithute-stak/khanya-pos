import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:khanya_pos/features/qr/data/qr_customer_card_repository.dart';

/// Printable customer lookup card. Not an identity card, credit facility,
/// loyalty award or evidence that a payment occurred.
Future<Uint8List> buildCustomerQrCardPdf(SignedCustomerQrCard card) async {
  final document = pw.Document();
  document.addPage(pw.Page(
    pageFormat: PdfPageFormat.a6,
    margin: pw.EdgeInsets.all(12 * PdfPageFormat.mm),
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        pw.Text('KHANYA POS',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4 * PdfPageFormat.mm),
        pw.Text('Customer QR lookup card'),
        pw.SizedBox(height: 6 * PdfPageFormat.mm),
        pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: card.token,
          width: 63 * PdfPageFormat.mm,
          height: 63 * PdfPageFormat.mm,
          drawText: false,
        ),
        pw.SizedBox(height: 6 * PdfPageFormat.mm),
        pw.Text(card.customerName,
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            textAlign: pw.TextAlign.center),
        pw.Text('Customer code: ${card.customerCode}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 4 * PdfPageFormat.mm),
        pw.Text('Scan using an authorized Khanya POS account.',
            style: const pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
        pw.Text('Not proof of identity, credit or payment',
            style: const pw.TextStyle(fontSize: 7), textAlign: pw.TextAlign.center),
      ],
    ),
  ));
  return document.save();
}
