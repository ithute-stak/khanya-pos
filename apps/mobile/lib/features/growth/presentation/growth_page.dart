import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/growth/data/growth_repository.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key});

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _promotions = const [];
  Map<String, dynamic> _loyalty = const {};

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
      final repo = context.read<GrowthRepository>();
      final results = await Future.wait<dynamic>([
        repo.promotions(),
        repo.loyaltyProgram(),
      ]);
      if (!mounted) return;
      setState(() {
        _promotions = results[0] as List<Map<String, dynamic>>;
        _loyalty = results[1] as Map<String, dynamic>;
      });
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _message(error, 'Could not load promotions and loyalty.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _configureLoyalty() async {
    var enabled = _loyalty['enabled'] == true;
    final earning = TextEditingController(text: '${_loyalty['points_per_currency'] ?? 0.1}');
    final value = TextEditingController(text: '${_loyalty['redemption_value'] ?? 0.1}');
    final minimum = TextEditingController(text: '${_loyalty['minimum_redeem_points'] ?? 10}');
    final result = await showDialog<(bool, double, double, int)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Customer loyalty'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  value: enabled,
                  onChanged: (v) => setDialogState(() => enabled = v),
                  title: const Text('Enable loyalty points'),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: earning,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Points earned per M1 spent'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: value,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Value of one point (M)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minimum,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Minimum points to redeem'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final earn = double.tryParse(earning.text.trim());
                final redemption = double.tryParse(value.text.trim());
                final minPoints = int.tryParse(minimum.text.trim());
                if (earn == null || earn < 0 || redemption == null || redemption < 0 || minPoints == null || minPoints < 1) return;
                Navigator.pop(dialogContext, (enabled, earn, redemption, minPoints));
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    earning.dispose();
    value.dispose();
    minimum.dispose();
    if (!mounted || result == null) return;
    try {
      await context.read<GrowthRepository>().setLoyaltyProgram(
            enabled: result.$1,
            pointsPerCurrency: result.$2,
            redemptionValue: result.$3,
            minimumRedeemPoints: result.$4,
          );
      await _load();
      if (mounted) _snack('Loyalty settings updated.');
    } on DioException catch (error) {
      if (mounted) _snack(_message(error, 'Could not update loyalty settings.'));
    }
  }

  Future<void> _editPromotion([Map<String, dynamic>? item]) async {
    final code = TextEditingController(text: item?['code']?.toString() ?? '');
    final name = TextEditingController(text: item?['name']?.toString() ?? '');
    final discount = TextEditingController(text: item?['discount_value']?.toString() ?? '10');
    final minimum = TextEditingController(text: item?['minimum_quantity']?.toString() ?? '1');
    final product = TextEditingController(text: item?['product_id']?.toString() ?? '');
    var type = item?['discount_type']?.toString() ?? 'percentage';
    var active = item?['is_active'] != false;
    var startsAt = DateTime.tryParse(item?['starts_at']?.toString() ?? '')?.toLocal() ?? DateTime.now();
    var endsAt = DateTime.tryParse(item?['ends_at']?.toString() ?? '')?.toLocal();

    final result = await showDialog<_PromotionForm>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item == null ? 'New promotion' : 'Edit promotion'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: code, decoration: const InputDecoration(labelText: 'Promotion code')),
                  const SizedBox(height: 12),
                  TextField(controller: name, decoration: const InputDecoration(labelText: 'Promotion name')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Discount type'),
                    items: const [
                      DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                      DropdownMenuItem(value: 'fixed', child: Text('Fixed amount per unit')),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: discount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: type == 'percentage' ? 'Discount (%)' : 'Discount per unit (M)')),
                  const SizedBox(height: 12),
                  TextField(controller: minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Minimum quantity')),
                  const SizedBox(height: 12),
                  TextField(controller: product, decoration: const InputDecoration(labelText: 'Product ID (blank = all products)')),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Starts'),
                    subtitle: Text(_date(startsAt)),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: () async {
                        final picked = await showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2100), initialDate: startsAt);
                        if (picked != null) setDialogState(() => startsAt = picked);
                      },
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ends'),
                    subtitle: Text(endsAt == null ? 'No end date' : _date(endsAt!)),
                    trailing: Wrap(
                      children: [
                        if (endsAt != null) IconButton(icon: const Icon(Icons.clear), onPressed: () => setDialogState(() => endsAt = null)),
                        IconButton(
                          icon: const Icon(Icons.calendar_month_outlined),
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, firstDate: startsAt, lastDate: DateTime(2100), initialDate: endsAt ?? startsAt.add(const Duration(days: 30)));
                            if (picked != null) setDialogState(() => endsAt = picked);
                          },
                        ),
                      ],
                    ),
                  ),
                  SwitchListTile(value: active, onChanged: (v) => setDialogState(() => active = v), title: const Text('Active'), contentPadding: EdgeInsets.zero),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amount = double.tryParse(discount.text.trim());
                final minQty = double.tryParse(minimum.text.trim());
                if (code.text.trim().length < 2 || name.text.trim().length < 2 || amount == null || amount <= 0 || minQty == null || minQty <= 0) return;
                Navigator.pop(
                  dialogContext,
                  _PromotionForm(
                    code: code.text.trim(),
                    name: name.text.trim(),
                    type: type,
                    value: amount,
                    minimum: minQty,
                    productId: product.text.trim().isEmpty ? null : product.text.trim(),
                    startsAt: startsAt,
                    endsAt: endsAt,
                    active: active,
                  ),
                );
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    code.dispose();
    name.dispose();
    discount.dispose();
    minimum.dispose();
    product.dispose();
    if (!mounted || result == null) return;
    try {
      final repo = context.read<GrowthRepository>();
      if (item == null) {
        await repo.createPromotion(
          code: result.code,
          name: result.name,
          discountType: result.type,
          discountValue: result.value,
          productId: result.productId,
          minimumQuantity: result.minimum,
          startsAt: result.startsAt,
          endsAt: result.endsAt,
          isActive: result.active,
        );
      } else {
        await repo.updatePromotion(
          id: item['id'].toString(),
          code: result.code,
          name: result.name,
          discountType: result.type,
          discountValue: result.value,
          productId: result.productId,
          minimumQuantity: result.minimum,
          startsAt: result.startsAt,
          endsAt: result.endsAt,
          isActive: result.active,
        );
      }
      await _load();
      if (mounted) _snack('Promotion saved.');
    } on DioException catch (error) {
      if (mounted) _snack(_message(error, 'Could not save promotion.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotions & Loyalty'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: _loading && _promotions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Customer loyalty', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 5),
                            Text(_loyalty['enabled'] == true
                                ? '${_loyalty['points_per_currency']} points per M1 • M${_loyalty['redemption_value']} per point • minimum ${_loyalty['minimum_redeem_points']} points'
                                : 'Loyalty points are currently disabled.'),
                          ],
                        ),
                        FilledButton.tonalIcon(onPressed: _configureLoyalty, icon: const Icon(Icons.loyalty_outlined), label: const Text('Configure')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Text('Promotions', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
                    FilledButton.icon(onPressed: () => _editPromotion(), icon: const Icon(Icons.add), label: const Text('New promotion')),
                  ],
                ),
                const SizedBox(height: 12),
                if (_promotions.isEmpty)
                  const Card(child: Padding(padding: EdgeInsets.all(20), child: Text('No promotions yet. Create a percentage or fixed-price promotion.')))
                else
                  Card(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Code')),
                          DataColumn(label: Text('Promotion')),
                          DataColumn(label: Text('Discount')),
                          DataColumn(label: Text('Scope')),
                          DataColumn(label: Text('Dates')),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Action')),
                        ],
                        rows: _promotions.map((item) {
                          final type = item['discount_type']?.toString() ?? 'percentage';
                          final value = item['discount_value']?.toString() ?? '0';
                          return DataRow(cells: [
                            DataCell(Text(item['code']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w800))),
                            DataCell(Text(item['name']?.toString() ?? '—')),
                            DataCell(Text(type == 'percentage' ? '$value%' : 'M$value / unit')),
                            DataCell(Text(item['product_id'] == null ? 'All products' : 'Selected product')),
                            DataCell(Text('${_dateText(item['starts_at'])} → ${item['ends_at'] == null ? 'Open' : _dateText(item['ends_at'])}')),
                            DataCell(Chip(label: Text(item['is_active'] == true ? 'Active' : 'Inactive'))),
                            DataCell(TextButton(onPressed: () => _editPromotion(item), child: const Text('Edit'))),
                          ]);
                        }).toList(growable: false),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, color: KhanyaBrand.forest),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text('At checkout Khanya automatically applies the single best eligible promotion. Promotions do not stack. Loyalty points are earned on the final sale amount, and redemption is validated against the customer’s available balance.'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _message(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['detail'] != null ? data['detail'].toString() : fallback;
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  String _dateText(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return parsed == null ? '—' : _date(parsed);
  }
}

class _PromotionForm {
  const _PromotionForm({
    required this.code,
    required this.name,
    required this.type,
    required this.value,
    required this.minimum,
    required this.productId,
    required this.startsAt,
    required this.endsAt,
    required this.active,
  });

  final String code;
  final String name;
  final String type;
  final double value;
  final double minimum;
  final String? productId;
  final DateTime startsAt;
  final DateTime? endsAt;
  final bool active;
}
