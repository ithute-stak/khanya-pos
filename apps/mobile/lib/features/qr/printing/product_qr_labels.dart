import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:khanya_pos/features/qr/data/qr_product_label_repository.dart';

/// Printable A4 sheet of server-issued product QR locators.
///
/// QR data comes only from the authenticated backend. No product price or
/// stock level is embedded because these can change after labels are printed.
Future<Uint8List> buildProductQrLabelsPdf(
  ProductQrLabel label, {
  int quantity = 10,
}) async {
  if (quantity < 1 || quantity > 100) {
    throw ArgumentError.value(quantity, 'quantity', 'Must be between 1 and 100');
  }
  final document = pw.Document();
  final mm = PdfPageFormat.mm;
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(12 * mm),
      build: (_) => [
        pw.Text('Khanya POS - Product QR Labels',
            style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 7 * mm),
        pw.Wrap(
          spacing: 3 * mm,
          runSpacing: 3 * mm,
          children: List.generate(
            quantity,
            (_) => pw.Container(
              width: 90 * mm,
              height: 46 * mm,
              padding: pw.EdgeInsets.all(3 * mm),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
              ),
              child: pw.Row(
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(),
                    data: label.token,
                    width: 38 * mm,
                    height: 38 * mm,
                    drawText: false,
                  ),
                  pw.SizedBox(width: 3 * mm),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      children: [
                        pw.Text('KHANYA POS',
                            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2 * mm),
                        pw.Text(label.name,
                            maxLines: 3, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        pw.SizedBox(height: 2 * mm),
                        pw.Text('SKU: ${label.sku}', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text('Scan in Khanya POS', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  return document.save();
}
