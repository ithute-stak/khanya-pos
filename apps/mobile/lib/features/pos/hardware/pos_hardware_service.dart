import 'dart:io';
import 'dart:typed_data';

import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';
import 'package:windows_printer/windows_printer.dart';

class PosHardwareService {
  const PosHardwareService._();

  static bool get supportsWindowsRawPrinting => Platform.isWindows;

  static Future<bool> printRawReceipt(
    SaleReceipt receipt,
    PosHardwareSettings settings,
  ) async {
    if (!supportsWindowsRawPrinting || !settings.hasPrinter) return false;
    return WindowsPrinter.printRawData(
      printerName: settings.printerName!,
      data: buildEscPosReceiptBytes(receipt, settings),
      useRawDatatype: true,
    );
  }

  static Future<bool> openCashDrawer(PosHardwareSettings settings) async {
    if (!supportsWindowsRawPrinting || !settings.hasPrinter) return false;
    return WindowsPrinter.printRawData(
      printerName: settings.printerName!,
      data: buildCashDrawerPulseBytes(),
      useRawDatatype: true,
    );
  }

  static Future<bool> printTest(PosHardwareSettings settings) async {
    if (!supportsWindowsRawPrinting || !settings.hasPrinter) return false;
    final testReceipt = SaleReceipt(
      businessName: 'Khanya Resources',
      reference: 'HARDWARE-TEST',
      issuedAt: DateTime.now(),
      lines: const [
        SaleReceiptLine(
          name: 'Printer test item',
          sku: 'TEST',
          quantity: 1,
          unitPriceMinor: 100,
          lineTotalMinor: 100,
        ),
      ],
      paymentMethod: PaymentMethod.cash,
      syncStatus: 'Hardware test',
      cashierName: 'Khanya POS',
    );
    return printRawReceipt(testReceipt, settings);
  }
}

Uint8List buildCashDrawerPulseBytes() {
  // ESC p m t1 t2 — standard ESC/POS drawer kick on connector pin 2.
  return Uint8List.fromList(const [0x1b, 0x40, 0x1b, 0x70, 0x00, 0x19, 0xfa]);
}

Uint8List buildEscPosReceiptBytes(
  SaleReceipt receipt,
  PosHardwareSettings settings,
) {
  final width = settings.paperWidthMm == 58 ? 32 : 48;
  final divider = List<String>.filled(width, '-').join();
  final bytes = <int>[];

  void command(List<int> values) => bytes.addAll(values);
  void text(String value) => bytes.addAll(_ascii(value).codeUnits);
  void line([String value = '']) {
    text(value);
    bytes.add(0x0a);
  }

  command(const [0x1b, 0x40]); // Initialize printer.
  command(const [0x1b, 0x61, 0x01]); // Center.
  command(const [0x1b, 0x45, 0x01]); // Bold on.
  for (final part in _wrap(_ascii(receipt.businessName).toUpperCase(), width)) {
    line(part);
  }
  command(const [0x1b, 0x45, 0x00]); // Bold off.
  line('KHANYA POS');
  line('SALES RECEIPT');
  command(const [0x1b, 0x61, 0x00]); // Left.
  line(divider);
  for (final part in _wrap('Ref: ${_ascii(receipt.reference)}', width)) {
    line(part);
  }
  line('Date: ${_formatDate(receipt.issuedAt)}');
  if (receipt.branchId != null && receipt.branchId!.trim().isNotEmpty) {
    for (final part in _wrap('Branch: ${_ascii(receipt.branchId!)}', width)) {
      line(part);
    }
  }
  if (receipt.cashierName != null && receipt.cashierName!.trim().isNotEmpty) {
    for (final part in _wrap('Cashier: ${_ascii(receipt.cashierName!)}', width)) {
      line(part);
    }
  }
  line('Payment: ${_ascii(receipt.paymentMethod.label)}');
  line(divider);

  for (final item in receipt.lines) {
    for (final nameLine in _wrap(_ascii(item.name), width)) {
      line(nameLine);
    }
    final quantityPrice = '${item.quantity} x ${formatMalotiMinor(item.unitPriceMinor)}';
    line(_columns(quantityPrice, formatMalotiMinor(item.lineTotalMinor), width));
    if (item.sku != null && item.sku!.trim().isNotEmpty) {
      for (final part in _wrap('SKU: ${_ascii(item.sku!)}', width)) {
        line(part);
      }
    }
  }

  line(divider);
  command(const [0x1b, 0x45, 0x01]);
  line(_columns('TOTAL', formatMalotiMinor(receipt.totalMinor), width));
  command(const [0x1b, 0x45, 0x00]);
  line(divider);
  command(const [0x1b, 0x61, 0x01]);
  for (final part in _wrap('Status: ${_ascii(receipt.syncStatus)}', width)) {
    line(part);
  }
  line('Thank you for your business.');
  line('People | Process | Profit');
  line('A Brighter Tomorrow');
  command(const [0x1b, 0x61, 0x00]);
  command(const [0x1b, 0x64, 0x03]); // Feed 3 lines.

  if (settings.cutReceipt) {
    command(const [0x1d, 0x56, 0x01]); // Partial cut on common ESC/POS printers.
  }

  return Uint8List.fromList(bytes);
}

String _ascii(String value) {
  final output = StringBuffer();
  for (final rune in value.runes) {
    if (rune == 0x0a || rune == 0x0d) {
      output.write(' ');
    } else if (rune >= 0x20 && rune <= 0x7e) {
      output.writeCharCode(rune);
    } else {
      output.write('?');
    }
  }
  return output.toString();
}

String _columns(String left, String right, int width) {
  final safeRight = right.length >= width ? right.substring(0, width - 1) : right;
  final leftWidth = width - safeRight.length - 1;
  final safeLeft = left.length > leftWidth ? left.substring(0, leftWidth) : left;
  return safeLeft.padRight(width - safeRight.length) + safeRight;
}

List<String> _wrap(String value, int width) {
  final normalized = value.trim();
  if (normalized.isEmpty) return const [''];
  final lines = <String>[];
  var remaining = normalized;
  while (remaining.length > width) {
    var split = remaining.lastIndexOf(' ', width);
    if (split <= 0) split = width;
    lines.add(remaining.substring(0, split).trimRight());
    remaining = remaining.substring(split).trimLeft();
  }
  if (remaining.isNotEmpty) lines.add(remaining);
  return lines;
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
