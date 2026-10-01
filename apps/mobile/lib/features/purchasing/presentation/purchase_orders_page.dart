import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/purchasing/data/purchase_order_repository.dart';

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];
  List<Map<String, dynamic>> _suppliers = const [];
  List<Map<String, dynamic>> _products = const [];

  PurchaseOrderRepository get _repository => context.read<PurchaseOrderRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _repository.list(),
        _repository.suppliers(),
        _repository.products(),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = values[0];
        _suppliers = values[1];
        _products = values[2];
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    String? supplierId;
    String? productId;
    final quantity = TextEditingController(text: '1');
    final unitCost = TextEditingController();
    final tax = TextEditingController(text: '0');
    final notes = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New purchase order'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: supplierId,
                    decoration: const InputDecoration(labelText: 'Supplier'),
                    items: _suppliers
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id']?.toString(),
                              child: Text(item['name']?.toString() ?? 'Supplier'),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() => supplierId = value),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: productId,
                    decoration: const InputDecoration(labelText: 'Product'),
                    items: _products
                        .map((item) => DropdownMenuItem<String>(
                              value: item['id']?.toString(),
                              child: Text(item['name']?.toString() ?? 'Product'),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() => productId = value),
                  ),
                  TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                  TextField(controller: unitCost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit cost')),
                  TextField(controller: tax, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tax total')),
                  TextField(controller: notes, decoration: const InputDecoration(labelText: 'Notes (optional)')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: supplierId == null || productId == null ? null : () => Navigator.pop(context, true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || supplierId == null || productId == null) return;
    await _repository.create(
      supplierId: supplierId!,
      productId: productId!,
      quantity: double.tryParse(quantity.text) ?? 1,
      unitCost: double.tryParse(unitCost.text) ?? 0,
      taxTotal: double.tryParse(tax.text) ?? 0,
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    );
    await _load();
  }

  Future<void> _transition(Map<String, dynamic> order, String target) async {
    final id = order['id']?.toString();
    if (id == null) return;
    await _repository.updateStatus(id, target);
    await _load();
  }

  List<Widget> _actionsFor(Map<String, dynamic> order) {
    final status = order['status']?.toString() ?? '';
    if (status == 'draft') {
      return [
        TextButton(onPressed: () => _transition(order, 'submitted'), child: const Text('Submit')),
        TextButton(onPressed: () => _transition(order, 'cancelled'), child: const Text('Cancel')),
      ];
    }
    if (status == 'submitted') {
      return [
        FilledButton.tonal(onPressed: () => _transition(order, 'approved'), child: const Text('Approve')),
        TextButton(onPressed: () => _transition(order, 'cancelled'), child: const Text('Cancel')),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New PO'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: FilledButton(onPressed: _load, child: Text('Retry: $_error')))
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text('Procurement approvals', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    const Text('Draft, submit and approve supplier purchase orders before receiving stock.'),
                    const SizedBox(height: 20),
                    if (_orders.isEmpty)
                      const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No purchase orders yet.')))
                    else
                      for (final order in _orders)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(order['order_number']?.toString() ?? 'Purchase order', style: Theme.of(context).textTheme.titleMedium),
                                          const SizedBox(height: 4),
                                          Text('Status: ${order['status']} • Total: M${order['total'] ?? 0}'),
                                        ],
                                      ),
                                    ),
                                    Wrap(spacing: 8, children: _actionsFor(order)),
                                  ],
                                ),
                                if (order['expected_at'] != null) ...[
                                  const SizedBox(height: 8),
                                  Text('Expected: ${order['expected_at']}'),
                                ],
                                if ((order['notes']?.toString() ?? '').isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(order['notes'].toString()),
                                ],
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}
