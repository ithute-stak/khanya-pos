import 'package:khanya_pos/features/pos/hardware/pos_hardware_service.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';
import 'package:printing/printing.dart';

class ReceiptPrinter {
  const ReceiptPrinter._();

  static Future<bool> printReceipt(
    SaleReceipt receipt, {
    PosHardwareSettings? settings,
    bool showDialogWhenUnconfigured = true,
  }) async {
    final widthMm = settings?.paperWidthMm ?? 80;

    if (settings != null && settings.hasPrinter && settings.directThermalPrinting) {
      final printed = await PosHardwareService.printRawReceipt(receipt, settings);
      if (printed || !showDialogWhenUnconfigured) return printed;
    }

    if (settings != null && settings.hasPrinter && !settings.directThermalPrinting) {
      final info = await Printing.info();
      if (info.directPrint && info.canListPrinters) {
        final printers = await Printing.listPrinters();
        final selected = printers.where((printer) => printer.name == settings.printerName).firstOrNull;
        if (selected != null) {
          final bytes = await buildSaleReceiptPdf(receipt, paperWidthMm: widthMm);
          return Printing.directPrintPdf(
            printer: selected,
            name: 'KhanyaPOS-${receipt.reference}.pdf',
            format: saleReceiptPageFormat(receipt, paperWidthMm: widthMm),
            dynamicLayout: false,
            forceCustomPrintPaper: true,
            onLayout: (_) async => bytes,
          );
        }
      }
      if (!showDialogWhenUnconfigured) return false;
    }

    if (!showDialogWhenUnconfigured) return false;
    final bytes = await buildSaleReceiptPdf(receipt, paperWidthMm: widthMm);
    return Printing.layoutPdf(
      name: 'KhanyaPOS-${receipt.reference}.pdf',
      format: saleReceiptPageFormat(receipt, paperWidthMm: widthMm),
      dynamicLayout: false,
      forceCustomPrintPaper: true,
      windowsModernDialog: true,
      onLayout: (_) async => bytes,
    );
  }
}
