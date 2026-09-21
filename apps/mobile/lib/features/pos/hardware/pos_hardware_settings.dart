import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PosHardwareSettings extends Equatable {
  const PosHardwareSettings({
    this.printerName,
    this.paperWidthMm = 80,
    this.directThermalPrinting = false,
    this.autoPrintReceipts = false,
    this.openCashDrawerOnCashSale = false,
    this.cutReceipt = true,
  });

  final String? printerName;
  final int paperWidthMm;
  final bool directThermalPrinting;
  final bool autoPrintReceipts;
  final bool openCashDrawerOnCashSale;
  final bool cutReceipt;

  bool get hasPrinter => printerName != null && printerName!.trim().isNotEmpty;
  bool get is58mm => paperWidthMm == 58;

  PosHardwareSettings copyWith({
    String? printerName,
    bool clearPrinter = false,
    int? paperWidthMm,
    bool? directThermalPrinting,
    bool? autoPrintReceipts,
    bool? openCashDrawerOnCashSale,
    bool? cutReceipt,
  }) {
    return PosHardwareSettings(
      printerName: clearPrinter ? null : (printerName ?? this.printerName),
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      directThermalPrinting: directThermalPrinting ?? this.directThermalPrinting,
      autoPrintReceipts: autoPrintReceipts ?? this.autoPrintReceipts,
      openCashDrawerOnCashSale: openCashDrawerOnCashSale ?? this.openCashDrawerOnCashSale,
      cutReceipt: cutReceipt ?? this.cutReceipt,
    );
  }

  @override
  List<Object?> get props => [
        printerName,
        paperWidthMm,
        directThermalPrinting,
        autoPrintReceipts,
        openCashDrawerOnCashSale,
        cutReceipt,
      ];
}

class PosHardwareSettingsRepository {
  PosHardwareSettingsRepository({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _printerNameKey = 'khanya.pos.hardware.printer_name';
  static const _paperWidthKey = 'khanya.pos.hardware.paper_width_mm';
  static const _directThermalKey = 'khanya.pos.hardware.direct_thermal';
  static const _autoPrintKey = 'khanya.pos.hardware.auto_print';
  static const _cashDrawerKey = 'khanya.pos.hardware.cash_drawer';
  static const _cutReceiptKey = 'khanya.pos.hardware.cut_receipt';

  final FlutterSecureStorage _storage;

  Future<PosHardwareSettings> read() async {
    final values = await Future.wait([
      _storage.read(key: _printerNameKey),
      _storage.read(key: _paperWidthKey),
      _storage.read(key: _directThermalKey),
      _storage.read(key: _autoPrintKey),
      _storage.read(key: _cashDrawerKey),
      _storage.read(key: _cutReceiptKey),
    ]);

    final width = int.tryParse(values[1] ?? '') ?? 80;
    return PosHardwareSettings(
      printerName: _normalizePrinter(values[0]),
      paperWidthMm: width == 58 ? 58 : 80,
      directThermalPrinting: _readBool(values[2]),
      autoPrintReceipts: _readBool(values[3]),
      openCashDrawerOnCashSale: _readBool(values[4]),
      cutReceipt: values[5] == null ? true : _readBool(values[5]),
    );
  }

  Future<void> write(PosHardwareSettings settings) async {
    final printer = _normalizePrinter(settings.printerName);
    await Future.wait([
      if (printer == null)
        _storage.delete(key: _printerNameKey)
      else
        _storage.write(key: _printerNameKey, value: printer),
      _storage.write(key: _paperWidthKey, value: settings.paperWidthMm.toString()),
      _storage.write(key: _directThermalKey, value: settings.directThermalPrinting.toString()),
      _storage.write(key: _autoPrintKey, value: settings.autoPrintReceipts.toString()),
      _storage.write(key: _cashDrawerKey, value: settings.openCashDrawerOnCashSale.toString()),
      _storage.write(key: _cutReceiptKey, value: settings.cutReceipt.toString()),
    ]);
  }

  static bool _readBool(String? value) => value?.toLowerCase() == 'true';

  static String? _normalizePrinter(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
