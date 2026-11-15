import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:khanya_pos/features/qr/domain/qr_scan_target.dart';

/// One scan entry point for every Khanya module.
///
/// Local parsing is informational only: until a backend QR resolver verifies
/// signature + tenant/branch permissions, this page only opens module lists.
class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final TextEditingController _manualCode = TextEditingController();
  final MobileScannerController _camera = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: false,
  );

  QrScanTarget? _target;
  bool _cameraOn = false;
  String? _message;

  @override
  void dispose() {
    _manualCode.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _inspect(String value) {
    final target = inspectKhanyaQrLocator(value.trim());
    if (!mounted) return;
    setState(() {
      _cameraOn = false;
      _target = target;
      _message = target == null
          ? 'This is not a supported Khanya QR code. No action was performed.'
          : null;
    });
    _camera.stop();
  }

  void _detect(BarcodeCapture capture) {
    if (!_cameraOn) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.isNotEmpty) {
        _inspect(raw);
        return;
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (!Platform.isAndroid) return;
    if (_cameraOn) {
      await _camera.stop();
      if (mounted) setState(() => _cameraOn = false);
      return;
    }
    setState(() {
      _target = null;
      _message = null;
      _cameraOn = true;
    });
    try {
      await _camera.start();
    } catch (_) {
      if (mounted) {
        setState(() {
          _cameraOn = false;
          _message = 'The camera is unavailable. Paste a QR code instead.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    return Scaffold(
      appBar: AppBar(title: const Text('Khanya QR Centre')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.qr_code_scanner, size: 62),
          const SizedBox(height: 12),
          Text('One scanner, every module',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
            'Scan products, receipts, payments, stock, customers, loyalty cards '
            'and more. Scanning never authorizes a transaction.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (Platform.isAndroid)
            FilledButton.icon(
              key: const Key('qr-camera-button'),
              icon: Icon(_cameraOn ? Icons.stop_circle_outlined : Icons.camera_alt_outlined),
              label: Text(_cameraOn ? 'Stop camera' : 'Scan with camera'),
              onPressed: _toggleCamera,
            ),
          if (_cameraOn && Platform.isAndroid) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: MobileScanner(controller: _camera, onDetect: _detect),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const Key('qr-manual-entry'),
            controller: _manualCode,
            decoration: const InputDecoration(
              labelText: 'Paste QR code / scanner input',
              prefixIcon: Icon(Icons.qr_code_2_outlined),
              border: OutlineInputBorder(),
            ),
            onSubmitted: _inspect,
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const Key('qr-inspect-button'),
            onPressed: () => _inspect(_manualCode.text),
            icon: const Icon(Icons.search),
            label: const Text('Identify QR'),
          ),
          if (_message != null) ...[
            const SizedBox(height: 14),
            Text(_message!, key: const Key('qr-scan-error')),
          ],
          if (target != null) ...[
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('QR type: ${target.kind}',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text('Related module: ${target.moduleLabel}'),
                    const SizedBox(height: 8),
                    const Text(
                      'This code has NOT been verified by the server. '
                      'The next screen is a normal module list, not direct '
                      'access to the encoded record or proof of payment.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('qr-open-module-button'),
                      onPressed: () => context.push(target.modulePath),
                      icon: const Icon(Icons.open_in_new),
                      label: Text('Open ${target.moduleLabel}'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'On desktop, connect a USB scanner that enters QR text, or paste '
            'the code manually. Product barcodes can still be scanned in POS.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
