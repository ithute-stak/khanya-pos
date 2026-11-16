import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';

import 'package:khanya_pos/features/qr/data/qr_product_label_repository.dart';
import 'package:khanya_pos/features/qr/printing/product_qr_labels.dart';

/// Authenticated QR label printing for a specific active product.
class ProductQrLabelsPage extends StatefulWidget {
  const ProductQrLabelsPage({super.key, required this.productId});

  final String productId;

  @override
  State<ProductQrLabelsPage> createState() => _ProductQrLabelsPageState();
}

class _ProductQrLabelsPageState extends State<ProductQrLabelsPage> {
  ProductQrLabel? _label;
  bool _loading = false;
  String? _error;
  int _quantity = 10;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      _label = null;
    });
    try {
      final label = await context.read<QrProductLabelRepository>().create(
            productId: widget.productId,
          );
      if (mounted) setState(() => _label = label);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = switch (error.response?.statusCode) {
          401 || 403 => 'You do not have permission to generate product labels.',
          404 => 'This product is no longer active or available.',
          503 => 'QR label signing has not been configured on the server.',
          _ => 'Could not generate signed QR labels. Check your connection.',
        };
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not prepare a valid product QR label.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _print() async {
    final label = _label;
    if (label == null || _loading) return;
    setState(() => _loading = true);
    try {
      final bytes = await buildProductQrLabelsPdf(label, quantity: _quantity);
      if (!mounted) return;
      await Printing.layoutPdf(
        name: 'Khanya-Product-QR-${label.sku}.pdf',
        onLayout: (_) async => bytes,
        format: PdfPageFormat.a4,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not print the product QR labels.')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _label;
    return Scaffold(
      appBar: AppBar(title: const Text('Product QR Labels')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.qr_code_2, size: 68),
              const SizedBox(height: 12),
              Text('Print product QR labels',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 14),
              const Text(
                'Each label contains a signed Khanya product identifier. '
                'Scanning will check the current product record. Prices and stock '
                'are never stored on the label.',
                textAlign: TextAlign.center,
              ),
              if (_loading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
              if (_error case final error?) ...[
                const SizedBox(height: 16),
                Text(error, key: const Key('qr-label-error')),
                TextButton(onPressed: _loading ? null : _load, child: const Text('Retry')),
              ],
              if (label != null) ...[
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(label.name),
                    subtitle: Text('SKU: ${label.sku}\nExpires: ${label.expiresAt.toLocal().toString().split(' ').first}'),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  key: const Key('qr-label-quantity'),
                  value: _quantity,
                  decoration: const InputDecoration(
                    labelText: 'Number of labels (A4)',
                    border: OutlineInputBorder(),
                  ),
                  items: const [1, 5, 10, 20, 50, 100]
                      .map((count) => DropdownMenuItem(value: count, child: Text('$count labels')))
                      .toList(),
                  onChanged: _loading ? null : (value) {
                    if (value != null) setState(() => _quantity = value);
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('qr-label-print'),
                  onPressed: _loading ? null : _print,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print QR labels'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
