import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_service.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';

void main() {
  final receipt = SaleReceipt(
    businessName: 'Khanya Resources',
    reference: 'sale-123456',
    issuedAt: DateTime.utc(2026, 9, 21, 14, 30),
    branchId: 'Maseru',
    cashierName: 'Cashier One',
    lines: const [
      SaleReceiptLine(
        name: 'Bread',
        sku: 'BR-001',
        quantity: 2,
        unitPriceMinor: 1500,
        lineTotalMinor: 3000,
      ),
    ],
    paymentMethod: PaymentMethod.cash,
    syncStatus: 'Synced',
  );

  test('cash drawer command uses ESC/POS pulse sequence', () {
    expect(
      buildCashDrawerPulseBytes(),
      orderedEquals(const [0x1b, 0x40, 0x1b, 0x70, 0x00, 0x19, 0xfa]),
    );
  });

  test('80mm ESC/POS receipt contains sale information and cut command', () {
    const settings = PosHardwareSettings(
      printerName: 'Receipt Printer',
      paperWidthMm: 80,
      directThermalPrinting: true,
      cutReceipt: true,
    );

    final bytes = buildEscPosReceiptBytes(receipt, settings);
    final printable = ascii.decode(
      bytes.where((value) => value >= 0x20 && value <= 0x7e).toList(),
      allowInvalid: true,
    );

    expect(bytes.take(2), orderedEquals(const [0x1b, 0x40]));
    expect(printable, contains('KHANYA RESOURCES'));
    expect(printable, contains('KHANYA POS'));
    expect(printable, contains('Bread'));
    expect(printable, contains('TOTAL'));
    expect(printable, contains('M 30.00'));
    expect(bytes.sublist(bytes.length - 3), orderedEquals(const [0x1d, 0x56, 0x01]));
  });

  test('58mm ESC/POS receipt can leave cutter command disabled', () {
    const settings = PosHardwareSettings(
      printerName: 'Receipt Printer',
      paperWidthMm: 58,
      directThermalPrinting: true,
      cutReceipt: false,
    );

    final bytes = buildEscPosReceiptBytes(receipt, settings);

    expect(bytes.take(2), orderedEquals(const [0x1b, 0x40]));
    expect(bytes.length, greaterThan(40));
    expect(bytes.sublist(bytes.length - 3), orderedEquals(const [0x1b, 0x64, 0x03]));
  });
}
