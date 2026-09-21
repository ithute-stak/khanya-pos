import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_service.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/pos/printing/receipt_printer.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';
import 'package:printing/printing.dart';

class HardwareSettingsPage extends StatefulWidget {
  const HardwareSettingsPage({super.key});

  @override
  State<HardwareSettingsPage> createState() => _HardwareSettingsPageState();
}

class _HardwareSettingsPageState extends State<HardwareSettingsPage> {
  PosHardwareSettings _settings = const PosHardwareSettings();
  List<String> _printers = const [];
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = context.read<PosHardwareSettingsRepository>();
      final settings = await repository.read();
      final info = await Printing.info();
      final printers = info.canListPrinters
          ? (await Printing.listPrinters()).map((printer) => printer.name).toSet().toList()..sort()
          : <String>[];
      if (settings.hasPrinter && !printers.contains(settings.printerName)) {
        printers.add(settings.printerName!);
        printers.sort();
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _printers = List.unmodifiable(printers);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to read the Windows printer list. Check that the Print Spooler is running.';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<PosHardwareSettingsRepository>().write(_settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POS hardware settings saved on this computer.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save hardware settings.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testPrint() async {
    if (!_settings.hasPrinter) return;
    setState(() => _testing = true);
    try {
      final receipt = SaleReceipt(
        businessName: 'Khanya Resources',
        reference: 'PRINTER-TEST',
        issuedAt: DateTime.now(),
        lines: const [
          SaleReceiptLine(
            name: 'Khanya POS printer test',
            sku: 'TEST-001',
            quantity: 1,
            unitPriceMinor: 100,
            lineTotalMinor: 100,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
        syncStatus: 'Hardware test',
        cashierName: 'Windows workstation',
      );
      final success = await ReceiptPrinter.printReceipt(
        receipt,
        settings: _settings,
        showDialogWhenUnconfigured: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Test receipt sent to the printer.' : 'The test print was cancelled or rejected.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The test receipt could not be printed. Check the printer and driver.')),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _testDrawer() async {
    if (!_settings.hasPrinter || !_settings.directThermalPrinting) return;
    try {
      final success = await PosHardwareService.openCashDrawer(_settings);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'Cash drawer pulse sent.' : 'Cash drawer command was not accepted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the cash drawer. Verify the printer and drawer cable.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return const Scaffold(
        body: Center(child: Text('POS hardware configuration is currently available on Windows.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('POS Hardware'),
        actions: [
          IconButton(
            tooltip: 'Refresh printers',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Windows POS hardware', style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 6),
                      Text(
                        'Choose the receipt printer attached to this workstation. These settings stay on this PC and do not change other tills.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(_error!),
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: _settings.hasPrinter ? _settings.printerName : null,
                        decoration: const InputDecoration(
                          labelText: 'Receipt printer',
                          prefixIcon: Icon(Icons.print_outlined),
                          helperText: 'Install the Windows printer driver first, then refresh this list.',
                        ),
                        items: [
                          for (final printer in _printers)
                            DropdownMenuItem(value: printer, child: Text(printer, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) => setState(() => _settings = _settings.copyWith(printerName: value)),
                      ),
                      const SizedBox(height: 20),
                      Text('Receipt paper', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedButton<int>(
                          segments: const [
                            ButtonSegment(value: 58, label: Text('58 mm')),
                            ButtonSegment(value: 80, label: Text('80 mm')),
                          ],
                          selected: {_settings.paperWidthMm},
                          onSelectionChanged: (values) {
                            setState(() => _settings = _settings.copyWith(paperWidthMm: values.first));
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Direct ESC/POS thermal printing'),
                        subtitle: const Text(
                          'Send the receipt directly to a compatible thermal printer. Enables paper cutting and cash-drawer control.',
                        ),
                        value: _settings.directThermalPrinting,
                        onChanged: (value) => setState(
                          () => _settings = _settings.copyWith(directThermalPrinting: value),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Automatically print completed sales'),
                        subtitle: const Text('Print without showing the Windows print dialog after every successful sale.'),
                        value: _settings.autoPrintReceipts,
                        onChanged: _settings.hasPrinter
                            ? (value) => setState(() => _settings = _settings.copyWith(autoPrintReceipts: value))
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Open cash drawer for cash sales'),
                        subtitle: const Text('Sends an ESC/POS drawer pulse through the selected receipt printer.'),
                        value: _settings.openCashDrawerOnCashSale,
                        onChanged: _settings.hasPrinter && _settings.directThermalPrinting
                            ? (value) => setState(
                                  () => _settings = _settings.copyWith(openCashDrawerOnCashSale: value),
                                )
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cut receipt after printing'),
                        subtitle: const Text('Uses the thermal printer partial-cut command.'),
                        value: _settings.cutReceipt,
                        onChanged: _settings.directThermalPrinting
                            ? (value) => setState(() => _settings = _settings.copyWith(cutReceipt: value))
                            : null,
                      ),
                      const SizedBox(height: 20),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Cash drawers normally connect to the RJ11/RJ12 drawer port on an ESC/POS receipt printer, not directly to the PC.',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving…' : 'Save settings'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _settings.hasPrinter && !_testing ? _testPrint : null,
                            icon: const Icon(Icons.print_outlined),
                            label: Text(_testing ? 'Printing…' : 'Print test receipt'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _settings.hasPrinter && _settings.directThermalPrinting ? _testDrawer : null,
                            icon: const Icon(Icons.point_of_sale_outlined),
                            label: const Text('Test cash drawer'),
                          ),
                          TextButton.icon(
                            onPressed: _loading ? null : _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Refresh printers'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
