import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';
import 'package:printing/printing.dart';

class ReceiptPrinter {
  const ReceiptPrinter._();

  static Future<bool> printReceipt(SaleReceipt receipt) async {
    final bytes = await buildSaleReceiptPdf(receipt);
    return Printing.layoutPdf(
      name: 'KhanyaPOS-${receipt.reference}.pdf',
      onLayout: (_) async => bytes,
    );
  }
}
