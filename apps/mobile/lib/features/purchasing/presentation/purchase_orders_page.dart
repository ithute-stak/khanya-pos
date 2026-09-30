import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/purchasing/data/purchase_order_repository.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';

class PurchaseOrdersPage extends StatefulWidget {
  const PurchaseOrdersPage({super.key});

  @override
  State<PurchaseOrdersPage> createState() => _PurchaseOrdersPageState();
}

class _PurchaseOrdersPageState extends State<PurchaseOrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];
  String? _busyId;

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
      final data = await context.read<PurchaseOrderRepository>().list();
      if (mounted) setState(() => _orders = data);
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _message(error, 'Could not load purchase orders.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    try {
      final purchasing = context.read<PurchasingRepository>();
      final catalog = context.read<ProductRepository>();
      await catalog.refresh();
      final results = await Future.wait<dynamic>([
        purchasing.listSuppliers(),
        catalog.cachedCurrentCatalog(),
      ]);
      if (!mounted) return;
      final suppliers = results[0] as List<SupplierSummary>;
      final products = results[1] as List<ProductSummary>;
      if (suppliers.isEmpty || products.isEmpty) {
        _snack('Add at least one supplier and one product before creating a purchase order.');
        return;
      }
      final draft = await showDialog<_PurchaseOrderDraft>(
        context: context,
        builder: (_) => _PurchaseOrderDialog(suppliers: suppliers, products: products),
      );
      if (!mounted || draft == null) return;
      await context.read<PurchaseOrderRepository>().create(
            supplierId: draft.supplierId,
            expectedAt: draft.expectedAt,
            notes: draft.notes,
            items: draft.lines
                .map(
                  (line) => <String, dynamic>{
                    'product_id': line.product.id,
                    'quantity': ScaledDecimal.fromMilli(line.quantityMilli),
                    'unit_cost': ScaledDecimal.fromMinor(line.unitCostMinor),
                  },
                )
                .toList(growable: false),
          );
      await _load();
      if (mounted) _snack('Purchase order created as draft.');
    } on DioException catch (error) {
      if (mounted) _snack(_message(error, 'Could not create purchase order.'));
    } catch (error) {
      if (mounted) _snack('Could not create purchase order: $error');
    }
  }

  Future<void> _action(Map<String, dynamic> order, String action) async {
    final id = order['id'].toString();
    setState(() => _busyId = id);
    try {
      final repo = context.read<PurchaseOrderRepository>();
      if (action == 'approve') {
        await repo.approve(id);
      } else if (action == 'cancel') {
        await repo.cancel(id);
      } else if (action == 'receive') {
        final invoice = TextEditingController();
        final result = await showDialog<String>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text('Receive ${order['order_number']}'),
            content: TextField(
              controller: invoice,
              decoration: const InputDecoration(labelText: 'Supplier invoice number (optional)'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, invoice.text.trim()), child: const Text('Receive on supplier credit')),
            ],
          ),
        );
        invoice.dispose();
        if (!mounted || result == null) return;
        await repo.receive(
          id: id,
          supplierInvoiceNumber: result.isEmpty ? null : result,
          notes: 'Received from ${order['order_number']}',
        );
      }
      await _load();
      if (mounted) _snack('Purchase order ${action == 'receive' ? 'received into stock' : '${action}d'}.');
    } on DioException catch (error) {
      if (mounted) _snack(_message(error, 'Purchase order action failed.'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase Orders'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New order'),
      ),
      body: _loading && _orders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Workflow: Draft → Approve → Receive. Stock and accounting are updated only when an approved order is actually received.'),
                  ),
                ),
                const SizedBox(height: 14),
                if (_orders.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No purchase orders yet.')))
                else
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Order')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Total'), numeric: true),
                          DataColumn(label: Text('Order date')),
                          DataColumn(label: Text('Expected')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _orders.map((order) {
                          final status = order['status']?.toString() ?? 'draft';
                          final busy = _busyId == order['id'].toString();
                          return DataRow(cells: [
                            DataCell(Text(order['order_number']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Chip(label: Text(_title(status)))),
                            DataCell(Text('M ${order['total'] ?? '0.00'}')),
                            DataCell(Text(_date(order['order_date']))),
                            DataCell(Text(_date(order['expected_at']))),
                            DataCell(
                              busy
                                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                                  : Wrap(
                                      spacing: 4,
                                      children: [
                                        if (status == 'draft')
                                          TextButton(onPressed: () => _action(order, 'approve'), child: const Text('Approve')),
                                        if (status == 'approved')
                                          FilledButton.tonal(onPressed: () => _action(order, 'receive'), child: const Text('Receive')),
                                        if (status == 'draft' || status == 'approved')
                                          TextButton(onPressed: () => _action(order, 'cancel'), child: const Text('Cancel')),
                                      ],
                                    ),
                            ),
                          ]);
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                const SizedBox(height: 80),
              ],
            ),
    );
  }

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['detail'] != null ? data['detail'].toString() : fallback;
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  String _date(Object? raw) {
    final value = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (value == null) return '—';
    return '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }

  String _title(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
}

class _PurchaseOrderDialog extends StatefulWidget {
  const _PurchaseOrderDialog({required this.suppliers, required this.products});
  final List<SupplierSummary> suppliers;
  final List<ProductSummary> products;

  @override
  State<_PurchaseOrderDialog> createState() => _PurchaseOrderDialogState();
}

class _PurchaseOrderDialogState extends State<_PurchaseOrderDialog> {
  String? _supplierId;
  DateTime? _expectedAt;
  final _notes = TextEditingController();
  final List<_OrderLine> _lines = [];

  @override
  void initState() {
    super.initState();
    _supplierId = widget.suppliers.first.id;
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    final line = await showDialog<_OrderLine>(
      context: context,
      builder: (_) => _OrderLineDialog(products: widget.products),
    );
    if (line == null) return;
    setState(() {
      _lines.removeWhere((existing) => existing.product.id == line.product.id);
      _lines.add(line);
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _lines.fold<int>(0, (value, line) => value + ((line.quantityMilli * line.unitCostMinor) ~/ 1000));
    return AlertDialog(
      title: const Text('New purchase order'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: widget.suppliers.map((supplier) => DropdownMenuItem(value: supplier.id, child: Text(supplier.name))).toList(growable: false),
                onChanged: (value) => setState(() => _supplierId = value),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Expected delivery'),
                subtitle: Text(_expectedAt == null ? 'Not specified' : '${_expectedAt!.year}-${_expectedAt!.month.toString().padLeft(2, '0')}-${_expectedAt!.day.toString().padLeft(2, '0')}'),
                trailing: IconButton(
                  onPressed: () async {
                    final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime(2100), initialDate: _expectedAt ?? DateTime.now().add(const Duration(days: 7)));
                    if (picked != null) setState(() => _expectedAt = picked);
                  },
                  icon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text('Items', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  OutlinedButton.icon(onPressed: _addLine, icon: const Icon(Icons.add), label: const Text('Add item')),
                ],
              ),
              if (_lines.isEmpty)
                const Padding(padding: EdgeInsets.all(20), child: Text('Add at least one product.'))
              else
                for (final line in _lines)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(line.product.name),
                    subtitle: Text('Qty ${ScaledDecimal.fromMilli(line.quantityMilli)} × ${ScaledDecimal.fromMinor(line.unitCostMinor)}'),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _lines.remove(line))),
                  ),
              const Divider(),
              Align(alignment: Alignment.centerRight, child: Text('Order total: ${ScaledDecimal.fromMinor(total)}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _supplierId == null || _lines.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _PurchaseOrderDraft(supplierId: _supplierId!, expectedAt: _expectedAt, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(), lines: List.unmodifiable(_lines)),
                  ),
          child: const Text('Create draft'),
        ),
      ],
    );
  }
}

class _OrderLineDialog extends StatefulWidget {
  const _OrderLineDialog({required this.products});
  final List<ProductSummary> products;

  @override
  State<_OrderLineDialog> createState() => _OrderLineDialogState();
}

class _OrderLineDialogState extends State<_OrderLineDialog> {
  late ProductSummary _product;
  final _quantity = TextEditingController(text: '1');
  late final TextEditingController _cost;

  @override
  void initState() {
    super.initState();
    _product = widget.products.first;
    _cost = TextEditingController(text: ScaledDecimal.fromMinor(_product.costPriceMinor));
  }

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Purchase order item'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _product.id,
                decoration: const InputDecoration(labelText: 'Product'),
                items: widget.products.map((product) => DropdownMenuItem(value: product.id, child: Text('${product.name} • ${product.sku}'))).toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  final selected = widget.products.firstWhere((product) => product.id == value);
                  setState(() {
                    _product = selected;
                    _cost.text = ScaledDecimal.fromMinor(selected.costPriceMinor);
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: _quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity')),
              const SizedBox(height: 12),
              TextField(controller: _cost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit cost')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final quantity = double.tryParse(_quantity.text.trim());
              final cost = double.tryParse(_cost.text.trim());
              if (quantity == null || quantity <= 0 || cost == null || cost < 0) return;
              Navigator.pop(
                context,
                _OrderLine(
                  product: _product,
                  quantityMilli: (quantity * 1000).round(),
                  unitCostMinor: (cost * 100).round(),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      );
}

class _PurchaseOrderDraft {
  const _PurchaseOrderDraft({required this.supplierId, required this.expectedAt, required this.notes, required this.lines});
  final String supplierId;
  final DateTime? expectedAt;
  final String? notes;
  final List<_OrderLine> lines;
}

class _OrderLine {
  const _OrderLine({required this.product, required this.quantityMilli, required this.unitCostMinor});
  final ProductSummary product;
  final int quantityMilli;
  final int unitCostMinor;
}
