import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/growth/data/growth_repository.dart';

class BusinessOsPage extends StatefulWidget {
  const BusinessOsPage({super.key});

  @override
  State<BusinessOsPage> createState() => _BusinessOsPageState();
}

class _BusinessOsPageState extends State<BusinessOsPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _promotions = const [];
  List<Map<String, dynamic>> _documents = const [];
  List<Map<String, dynamic>> _alerts = const [];
  List<Map<String, dynamic>> _customers = const [];
  Map<String, dynamic>? _loyalty;
  String? _selectedCustomerId;

  GrowthRepository get _repository => context.read<GrowthRepository>();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final values = await Future.wait([
        _repository.promotions(),
        _repository.documents(),
        _repository.alerts(),
        _repository.customers(),
      ]);
      if (!mounted) return;
      setState(() {
        _promotions = values[0];
        _documents = values[1];
        _alerts = values[2];
        _customers = values[3];
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

  Future<void> _loadLoyalty(String customerId) async {
    final value = await _repository.loyalty(customerId);
    if (!mounted) return;
    setState(() {
      _selectedCustomerId = customerId;
      _loyalty = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Business OS'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promotions'),
            Tab(icon: Icon(Icons.description_outlined), text: 'Quotes & invoices'),
            Tab(icon: Icon(Icons.stars_outlined), text: 'Loyalty'),
            Tab(icon: Icon(Icons.notifications_active_outlined), text: 'Alerts'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _promotionsView(),
                    _documentsView(),
                    _loyaltyView(),
                    _alertsView(),
                  ],
                ),
    );
  }

  Widget _promotionsView() {
    return _Section(
      title: 'Sales promotions',
      description: 'Create percentage or fixed-value promotions and evaluate them consistently at checkout.',
      action: FilledButton.icon(
        onPressed: _createPromotion,
        icon: const Icon(Icons.add),
        label: const Text('New promotion'),
      ),
      child: _promotions.isEmpty
          ? const _Empty(message: 'No active promotions yet.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _promotions.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _promotions[index];
                final type = item['discount_type']?.toString() ?? '';
                final value = item['value']?.toString() ?? '0';
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.percent)),
                  title: Text(item['name']?.toString() ?? 'Promotion'),
                  subtitle: Text('${item['code']} • minimum M${item['minimum_spend'] ?? 0}'),
                  trailing: Text(type == 'percentage' ? '$value%' : 'M$value'),
                );
              },
            ),
    );
  }

  Widget _documentsView() {
    return _Section(
      title: 'Commercial documents',
      description: 'Prepare searchable quotations and invoices with preserved line-item pricing.',
      action: FilledButton.icon(
        onPressed: _createDocument,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('New document'),
      ),
      child: _documents.isEmpty
          ? const _Empty(message: 'No quotations or invoices yet.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _documents.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _documents[index];
                return ListTile(
                  leading: Icon(item['document_type'] == 'quotation'
                      ? Icons.request_quote_outlined
                      : Icons.receipt_long_outlined),
                  title: Text(item['document_number']?.toString() ?? 'Document'),
                  subtitle: Text('${item['customer_name']} • ${item['status']}'),
                  trailing: Text('${item['currency'] ?? 'LSL'} ${item['total'] ?? 0}'),
                );
              },
            ),
    );
  }

  Widget _loyaltyView() {
    final customerItems = _customers
        .map((customer) => DropdownMenuItem<String>(
              value: customer['id']?.toString(),
              child: Text(customer['name']?.toString() ?? 'Customer'),
            ))
        .where((item) => item.value != null)
        .toList(growable: false);

    return _Section(
      title: 'Customer loyalty',
      description: 'Points use a ledger so every earn, redemption and adjustment remains explainable.',
      action: _selectedCustomerId == null
          ? null
          : FilledButton.icon(
              onPressed: _adjustPoints,
              icon: const Icon(Icons.add_card),
              label: const Text('Adjust points'),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedCustomerId,
            decoration: const InputDecoration(labelText: 'Customer', border: OutlineInputBorder()),
            items: customerItems,
            onChanged: (value) {
              if (value != null) _loadLoyalty(value);
            },
          ),
          const SizedBox(height: 20),
          if (_loyalty == null)
            const _Empty(message: 'Choose a customer to view loyalty points.')
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Metric(label: 'Points balance', value: _loyalty!['points_balance']?.toString() ?? '0'),
                _Metric(label: 'Lifetime earned', value: _loyalty!['lifetime_earned']?.toString() ?? '0'),
              ],
            ),
            const SizedBox(height: 20),
            Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if ((_loyalty!['transactions'] as List<dynamic>? ?? const []).isEmpty)
              const _Empty(message: 'No loyalty activity yet.')
            else
              for (final dynamic raw in _loyalty!['transactions'] as List<dynamic>)
                if (raw is Map<String, dynamic>)
                  ListTile(
                    dense: true,
                    leading: Icon((num.tryParse(raw['points'].toString()) ?? 0) >= 0
                        ? Icons.add_circle_outline
                        : Icons.remove_circle_outline),
                    title: Text('${raw['transaction_type']} • ${raw['points']} points'),
                    subtitle: Text(raw['note']?.toString() ?? raw['reference']?.toString() ?? ''),
                  ),
          ],
        ],
      ),
    );
  }

  Widget _alertsView() {
    return _Section(
      title: 'Owner alerts',
      description: 'Refresh business alerts from operational data and acknowledge items as they are handled.',
      action: FilledButton.icon(
        onPressed: _refreshAlerts,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Scan now'),
      ),
      child: _alerts.isEmpty
          ? const _Empty(message: 'No open alerts.')
          : ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _alerts.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final item = _alerts[index];
                return ListTile(
                  leading: Icon(
                    item['severity'] == 'critical'
                        ? Icons.error_outline
                        : item['severity'] == 'warning'
                            ? Icons.warning_amber_outlined
                            : Icons.info_outline,
                  ),
                  title: Text(item['title']?.toString() ?? 'Alert'),
                  subtitle: Text(item['message']?.toString() ?? ''),
                  trailing: TextButton(
                    onPressed: () => _acknowledge(item['id']?.toString()),
                    child: const Text('Acknowledge'),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _createPromotion() async {
    final name = TextEditingController();
    final code = TextEditingController();
    final value = TextEditingController();
    final minimum = TextEditingController(text: '0');
    var type = 'percentage';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New promotion'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: code, decoration: const InputDecoration(labelText: 'Code')),
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
                  ],
                  onChanged: (next) => setDialogState(() => type = next ?? type),
                  decoration: const InputDecoration(labelText: 'Discount type'),
                ),
                TextField(controller: value, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Discount value')),
                TextField(controller: minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum spend')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _repository.createPromotion(
      name: name.text.trim(),
      code: code.text.trim(),
      discountType: type,
      value: double.tryParse(value.text) ?? 0,
      minimumSpend: double.tryParse(minimum.text) ?? 0,
    );
    await _load();
  }

  Future<void> _createDocument() async {
    final customerName = TextEditingController();
    final customerEmail = TextEditingController();
    final description = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final unitPrice = TextEditingController();
    var type = 'quotation';
    String? customerId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New quotation / invoice'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: type,
                    items: const [
                      DropdownMenuItem(value: 'quotation', child: Text('Quotation')),
                      DropdownMenuItem(value: 'invoice', child: Text('Invoice')),
                    ],
                    onChanged: (next) => setDialogState(() => type = next ?? type),
                    decoration: const InputDecoration(labelText: 'Document type'),
                  ),
                  DropdownButtonFormField<String>(
                    value: customerId,
                    decoration: const InputDecoration(labelText: 'Existing customer (optional)'),
                    items: _customers
                        .map((customer) => DropdownMenuItem<String>(
                              value: customer['id']?.toString(),
                              child: Text(customer['name']?.toString() ?? ''),
                            ))
                        .toList(),
                    onChanged: (next) {
                      setDialogState(() => customerId = next);
                      Map<String, dynamic>? customer;
                      for (final item in _customers) {
                        if (item['id']?.toString() == next) {
                          customer = item;
                          break;
                        }
                      }
                      if (customer != null) {
                        customerName.text = customer['name']?.toString() ?? '';
                        customerEmail.text = customer['email']?.toString() ?? '';
                      }
                    },
                  ),
                  TextField(controller: customerName, decoration: const InputDecoration(labelText: 'Customer name')),
                  TextField(controller: customerEmail, decoration: const InputDecoration(labelText: 'Customer email')),
                  const Divider(height: 28),
                  TextField(controller: description, decoration: const InputDecoration(labelText: 'Line description')),
                  TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                  TextField(controller: unitPrice, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Unit price')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (saved != true) return;
    await _repository.createDocument(
      documentType: type,
      customerId: customerId,
      customerName: customerName.text.trim(),
      customerEmail: customerEmail.text.trim().isEmpty ? null : customerEmail.text.trim(),
      description: description.text.trim(),
      quantity: double.tryParse(quantity.text) ?? 1,
      unitPrice: double.tryParse(unitPrice.text) ?? 0,
    );
    await _load();
  }

  Future<void> _adjustPoints() async {
    final points = TextEditingController();
    final note = TextEditingController();
    var type = 'earn';
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Loyalty points'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  items: const [
                    DropdownMenuItem(value: 'earn', child: Text('Earn')),
                    DropdownMenuItem(value: 'redeem', child: Text('Redeem')),
                    DropdownMenuItem(value: 'adjustment', child: Text('Adjustment')),
                  ],
                  onChanged: (next) => setDialogState(() => type = next ?? type),
                  decoration: const InputDecoration(labelText: 'Transaction'),
                ),
                TextField(controller: points, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Points')),
                TextField(controller: note, decoration: const InputDecoration(labelText: 'Note')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (saved != true || _selectedCustomerId == null) return;
    await _repository.adjustLoyalty(
      _selectedCustomerId!,
      points: double.tryParse(points.text) ?? 0,
      transactionType: type,
      note: note.text.trim().isEmpty ? null : note.text.trim(),
    );
    await _loadLoyalty(_selectedCustomerId!);
  }

  Future<void> _refreshAlerts() async {
    await _repository.refreshAlerts();
    final alerts = await _repository.alerts();
    if (mounted) setState(() => _alerts = alerts);
  }

  Future<void> _acknowledge(String? id) async {
    if (id == null) return;
    await _repository.updateAlert(id, 'acknowledged');
    final alerts = await _repository.alerts();
    if (mounted) setState(() => _alerts = alerts);
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.description, required this.child, this.action});

  final String title;
  final String description;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 650,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  Text(description, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.headlineSmall),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Text(message)),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
