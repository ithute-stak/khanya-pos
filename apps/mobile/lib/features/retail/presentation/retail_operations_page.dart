import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:khanya_pos/features/retail/data/retail_repository.dart';

class RetailOperationsPage extends StatefulWidget {
  const RetailOperationsPage({super.key});

  @override
  State<RetailOperationsPage> createState() => _RetailOperationsPageState();
}

class _RetailOperationsPageState extends State<RetailOperationsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _promotions = const [];
  Map<String, dynamic> _loyalty = const {};
  List<Map<String, dynamic>> _purchaseOrders = const [];
  List<Map<String, dynamic>> _notifications = const [];
  List<ProductSummary> _products = const [];
  List<SupplierSummary> _suppliers = const [];
  List<Map<String, dynamic>> _labels = const [];

  RetailRepository get _repository => context.read<RetailRepository>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        _repository.promotions(),
        _repository.loyaltyProgram(),
        _repository.purchaseOrders(),
        _repository.notifications(),
        context.read<ProductRepository>().cachedCurrentCatalog(),
        context.read<PurchasingRepository>().listSuppliers(),
      ]);
      if (!mounted) return;
      setState(() {
        _promotions = results[0] as List<Map<String, dynamic>>;
        _loyalty = results[1] as Map<String, dynamic>;
        _purchaseOrders = results[2] as List<Map<String, dynamic>>;
        _notifications = results[3] as List<Map<String, dynamic>>;
        _products = results[4] as List<ProductSummary>;
        _suppliers = results[5] as List<SupplierSummary>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = _repository.errorMessage(error, 'Could not load retail operations.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addPromotion() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final value = TextEditingController(text: '10');
    final minimum = TextEditingController(text: '0.00');
    var type = 'percentage';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New promotion'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Promotion name')),
                const SizedBox(height: 12),
                TextField(controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Discount type'),
                  items: const [
                    DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                    DropdownMenuItem(value: 'fixed_amount', child: Text('Fixed amount')),
                  ],
                  onChanged: (next) {
                    if (next != null) setDialogState(() => type = next);
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Discount value')),
                const SizedBox(height: 12),
                TextField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Minimum sale amount')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await _repository.createPromotion(
        name: name.text,
        code: code.text,
        discountType: type,
        discountValue: value.text,
        minimumSubtotal: minimum.text,
      );
      await _load();
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not create the promotion.'));
    } finally {
      name.dispose();
      code.dispose();
      value.dispose();
      minimum.dispose();
    }
  }

  Future<void> _editLoyalty() async {
    final spend = TextEditingController(text: _loyalty['spend_per_point']?.toString() ?? '10.00');
    final redeemValue = TextEditingController(text: _loyalty['redemption_value_per_point']?.toString() ?? '0.10');
    final minimum = TextEditingController(text: _loyalty['minimum_redeem_points']?.toString() ?? '100');
    var active = _loyalty['is_active'] as bool? ?? true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Loyalty programme'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: active,
                  title: const Text('Programme active'),
                  onChanged: (value) => setDialogState(() => active = value),
                ),
                TextField(controller: spend, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Spend required for 1 point (M)')),
                const SizedBox(height: 12),
                TextField(controller: redeemValue, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Value of 1 point (M)')),
                const SizedBox(height: 12),
                TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum points to redeem')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await _repository.updateLoyaltyProgram(
        active: active,
        spendPerPoint: spend.text,
        redemptionValuePerPoint: redeemValue.text,
        minimumRedeemPoints: int.tryParse(minimum.text) ?? 100,
      );
      await _load();
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not update loyalty settings.'));
    } finally {
      spend.dispose();
      redeemValue.dispose();
      minimum.dispose();
    }
  }

  Future<void> _createPurchaseOrder() async {
    if (_suppliers.isEmpty || _products.isEmpty) {
      _showError('Add at least one supplier and product before creating a purchase order.');
      return;
    }
    SupplierSummary supplier = _suppliers.first;
    ProductSummary product = _products.first;
    final quantity = TextEditingController(text: '1');
    final unitCost = TextEditingController(text: ScaledDecimal.fromMinor(product.costPriceMinor));
    final notes = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New purchase order'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<SupplierSummary>(
                  initialValue: supplier,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Supplier'),
                  items: [for (final item in _suppliers) DropdownMenuItem(value: item, child: Text(item.name))],
                  onChanged: (next) {
                    if (next != null) setDialogState(() => supplier = next);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ProductSummary>(
                  initialValue: product,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [for (final item in _products) DropdownMenuItem(value: item, child: Text('${item.name} • ${item.sku}'))],
                  onChanged: (next) {
                    if (next != null) {
                      setDialogState(() => product = next);
                      unitCost.text = ScaledDecimal.fromMinor(next.costPriceMinor);
                    }
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: quantity, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Quantity'))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: unitCost, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Unit cost (M)'))),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Create the order, then use Approve → Send → Receive from the order list.'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Create draft')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    final quantityMilli = ScaledDecimal.toMilli(quantity.text);
    final unitCostMinor = ScaledDecimal.toMinor(unitCost.text);
    if (quantityMilli <= 0) {
      _showError('Quantity must be greater than zero.');
      return;
    }
    try {
      await _repository.createPurchaseOrder(
        supplierId: supplier.id,
        lines: [(product: product, quantityMilli: quantityMilli, unitCostMinor: unitCostMinor)],
        notes: notes.text,
      );
      await _load();
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not create the purchase order.'));
    } finally {
      quantity.dispose();
      unitCost.dispose();
      notes.dispose();
    }
  }

  Future<void> _purchaseOrderAction(Map<String, dynamic> item, String action) async {
    try {
      if (action == 'receive') {
        await _repository.receivePurchaseOrder(orderId: item['id'].toString());
      } else {
        await _repository.transitionPurchaseOrder(item['id'].toString(), action);
      }
      await _load();
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not update the purchase order.'));
    }
  }

  Future<void> _previewLabels() async {
    if (_products.isEmpty) {
      _showError('Add products before creating labels.');
      return;
    }
    ProductSummary product = _products.first;
    var copies = 1;
    var includePrice = true;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Product label preview'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<ProductSummary>(
                  initialValue: product,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: [for (final item in _products) DropdownMenuItem(value: item, child: Text('${item.name} • ${item.sku}'))],
                  onChanged: (next) {
                    if (next != null) setDialogState(() => product = next);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: copies,
                  decoration: const InputDecoration(labelText: 'Copies'),
                  items: [for (var value = 1; value <= 10; value++) DropdownMenuItem(value: value, child: Text('$value'))],
                  onChanged: (next) {
                    if (next != null) setDialogState(() => copies = next);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includePrice,
                  title: const Text('Show price'),
                  onChanged: (value) => setDialogState(() => includePrice = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Preview')),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      final labels = await _repository.labelPreview(
        productIds: [product.id],
        copies: copies,
        includePrice: includePrice,
      );
      if (mounted) setState(() => _labels = labels);
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not create the label preview.'));
    }
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read_at'] != null) return;
    try {
      await _repository.markNotificationRead(item['id'].toString());
      await _load();
    } catch (error) {
      _showError(_repository.errorMessage(error, 'Could not mark the notification as read.'));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retail Operations'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promotions'),
            Tab(icon: Icon(Icons.stars_outlined), text: 'Loyalty'),
            Tab(icon: Icon(Icons.request_quote_outlined), text: 'Purchase Orders'),
            Tab(icon: Icon(Icons.qr_code_2_outlined), text: 'Labels'),
            Tab(icon: Icon(Icons.notifications_outlined), text: 'Notifications'),
          ],
        ),
      ),
      body: _loading && _promotions.isEmpty && _purchaseOrders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_error != null)
                  MaterialBanner(
                    content: Text(_error!),
                    actions: [TextButton(onPressed: _load, child: const Text('Retry'))],
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _promotionsTab(),
                      _loyaltyTab(),
                      _purchaseOrdersTab(),
                      _labelsTab(),
                      _notificationsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _promotionsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text('Promotions', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: _addPromotion, icon: const Icon(Icons.add), label: const Text('New promotion')),
          ],
        ),
        const SizedBox(height: 12),
        if (_promotions.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No promotions yet.')))
        else
          ..._promotions.map((item) => Card(
                child: ListTile(
                  leading: Icon((item['is_active'] as bool? ?? false) ? Icons.local_offer : Icons.local_offer_outlined),
                  title: Text('${item['name']} • ${item['code']}'),
                  subtitle: Text(
                    item['discount_type'] == 'percentage'
                        ? '${item['discount_value']}% off • minimum M ${item['minimum_subtotal']}'
                        : 'M ${item['discount_value']} off • minimum M ${item['minimum_subtotal']}',
                  ),
                  trailing: Switch(
                    value: item['is_active'] as bool? ?? false,
                    onChanged: (value) async {
                      try {
                        await _repository.setPromotionActive(item['id'].toString(), value);
                        await _load();
                      } catch (error) {
                        _showError(_repository.errorMessage(error, 'Could not update the promotion.'));
                      }
                    },
                  ),
                ),
              )),
      ],
    );
  }

  Widget _loyaltyTab() {
    final active = _loyalty['is_active'] as bool? ?? false;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text('Customer Loyalty', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.tonalIcon(onPressed: _editLoyalty, icon: const Icon(Icons.edit), label: const Text('Configure')),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 28,
              runSpacing: 16,
              children: [
                _metric('Status', active ? 'Active' : 'Paused'),
                _metric('Earn 1 point every', 'M ${_loyalty['spend_per_point'] ?? '10.00'}'),
                _metric('1 point value', 'M ${_loyalty['redemption_value_per_point'] ?? '0.10'}'),
                _metric('Minimum redemption', '${_loyalty['minimum_redeem_points'] ?? 100} points'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('Customers earn points automatically on completed sales. Points can be redeemed only against an identified customer and every earn, redemption and manual adjustment is recorded in the loyalty ledger.'),
          ),
        ),
      ],
    );
  }

  Widget _purchaseOrdersTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text('Purchase Orders', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: _createPurchaseOrder, icon: const Icon(Icons.add), label: const Text('New PO')),
          ],
        ),
        const SizedBox(height: 12),
        if (_purchaseOrders.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No purchase orders yet.')))
        else
          ..._purchaseOrders.map((item) {
            final status = item['status']?.toString() ?? 'draft';
            final actions = switch (status) {
              'draft' => const [('approve', 'Approve'), ('cancel', 'Cancel')],
              'approved' => const [('send', 'Mark sent'), ('receive', 'Receive'), ('cancel', 'Cancel')],
              'sent' => const [('receive', 'Receive'), ('cancel', 'Cancel')],
              _ => const <(String, String)>[],
            };
            return Card(
              child: ListTile(
                leading: const Icon(Icons.request_quote_outlined),
                title: Text(item['order_number']?.toString() ?? 'Purchase order'),
                subtitle: Text('${status.toUpperCase()} • M ${item['total']}'),
                trailing: actions.isEmpty
                    ? Chip(label: Text(status))
                    : PopupMenuButton<String>(
                        onSelected: (action) => _purchaseOrderAction(item, action),
                        itemBuilder: (_) => [
                          for (final action in actions) PopupMenuItem(value: action.$1, child: Text(action.$2)),
                        ],
                      ),
              ),
            );
          }),
      ],
    );
  }

  Widget _labelsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text('Barcode & Shelf Labels', style: Theme.of(context).textTheme.headlineSmall)),
            FilledButton.icon(onPressed: _previewLabels, icon: const Icon(Icons.qr_code_2), label: const Text('Create preview')),
          ],
        ),
        const SizedBox(height: 12),
        if (_labels.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('Choose a product to create Code 128 label data using its barcode, with SKU fallback when no barcode is stored.')))
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final label in _labels)
                SizedBox(
                  width: 280,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 8),
                          SelectableText(label['barcode']?.toString() ?? ''),
                          const SizedBox(height: 4),
                          Text('SKU ${label['sku']} • CODE128'),
                          if (label['price'] != null) Text('M ${label['price']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _notificationsTab() {
    final unread = _notifications.where((item) => item['read_at'] == null).length;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: Text('Notifications', style: Theme.of(context).textTheme.headlineSmall)),
            Chip(label: Text('$unread unread')),
          ],
        ),
        const SizedBox(height: 12),
        if (_notifications.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No operational notifications yet.')))
        else
          ..._notifications.map((item) => Card(
                child: ListTile(
                  leading: Icon(
                    item['severity'] == 'warning' ? Icons.warning_amber_outlined : Icons.notifications_outlined,
                  ),
                  title: Text(item['title']?.toString() ?? ''),
                  subtitle: Text(item['body']?.toString() ?? ''),
                  trailing: item['read_at'] == null
                      ? TextButton(onPressed: () => _markRead(item), child: const Text('Mark read'))
                      : const Icon(Icons.done),
                ),
              )),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
