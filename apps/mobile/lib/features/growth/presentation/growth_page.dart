import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/growth/data/growth_repository.dart';

class GrowthPage extends StatefulWidget {
  const GrowthPage({super.key});

  @override
  State<GrowthPage> createState() => _GrowthPageState();
}

class _GrowthPageState extends State<GrowthPage> {
  bool _loading = true;
  String? _error;
  List<PromotionSummary> _promotions = const [];
  LoyaltyProgramSummary? _loyalty;
  Map<String, dynamic> _alerts = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final repository = context.read<GrowthRepository>();
      final results = await Future.wait<dynamic>([
        repository.promotions(),
        repository.loyaltyProgram(),
        repository.alerts(),
      ]);
      if (!mounted) return;
      setState(() {
        _promotions = results[0] as List<PromotionSummary>;
        _loyalty = results[1] as LoyaltyProgramSummary;
        _alerts = Map<String, dynamic>.from(results[2] as Map);
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is StateError ? error.message.toString() : 'Growth tools could not be loaded.';
        _loading = false;
      });
    }
  }

  Future<void> _addPromotion() async {
    final result = await showDialog<_PromotionDraft>(
      context: context,
      builder: (context) => const _PromotionDialog(),
    );
    if (!mounted || result == null) return;
    try {
      await context.read<GrowthRepository>().createPromotion(
            name: result.name,
            code: result.code,
            discountType: result.discountType,
            discountValue: result.discountValue,
            minSubtotal: result.minSubtotal,
            maxUses: result.maxUses,
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${result.name} is ready for the POS.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message.toString() : 'Promotion could not be saved.')),
      );
    }
  }

  Future<void> _configureLoyalty() async {
    final current = _loyalty;
    if (current == null) return;
    final result = await showDialog<_LoyaltyDraft>(
      context: context,
      builder: (context) => _LoyaltyDialog(current: current),
    );
    if (!mounted || result == null) return;
    try {
      await context.read<GrowthRepository>().saveLoyaltyProgram(
            name: result.name,
            isActive: result.isActive,
            pointsPerCurrency: result.pointsPerCurrency,
            currencyPerPoint: result.currencyPerPoint,
            minRedeemPoints: result.minRedeemPoints,
          );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loyalty programme updated.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loyalty programme could not be updated.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Growth & Customer Loyalty'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPromotion,
        icon: const Icon(Icons.add),
        label: const Text('New promotion'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, retry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 110),
                    children: [
                      _AlertsCard(alerts: _alerts),
                      const SizedBox(height: 18),
                      _LoyaltyCard(program: _loyalty!, onConfigure: _configureLoyalty),
                      const SizedBox(height: 18),
                      Text('Promotions', style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 10),
                      if (_promotions.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('No promotions yet. Create a code for percentage or fixed discounts.'),
                          ),
                        )
                      else
                        for (final item in _promotions) _PromotionCard(item: item),
                    ],
                  ),
                ),
    );
  }
}

class _AlertsCard extends StatelessWidget {
  const _AlertsCard({required this.alerts});
  final Map<String, dynamic> alerts;

  @override
  Widget build(BuildContext context) {
    final items = (alerts['alerts'] as List<dynamic>? ?? const <dynamic>[])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
    final critical = (alerts['critical_count'] as num?)?.toInt() ?? 0;
    final warnings = (alerts['warning_count'] as num?)?.toInt() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active_outlined),
                const SizedBox(width: 10),
                Expanded(child: Text('Business alerts', style: Theme.of(context).textTheme.titleMedium)),
                Chip(label: Text('$critical critical')),
                const SizedBox(width: 6),
                Chip(label: Text('$warnings warnings')),
              ],
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('No stock, overdue-credit or stale-till alerts for this branch.')
            else
              for (final item in items.take(8))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    item['severity'] == 'critical' ? Icons.error_outline : Icons.warning_amber_rounded,
                  ),
                  title: Text(item['title']?.toString() ?? 'Alert'),
                  subtitle: Text(item['message']?.toString() ?? ''),
                ),
          ],
        ),
      ),
    );
  }
}

class _LoyaltyCard extends StatelessWidget {
  const _LoyaltyCard({required this.program, required this.onConfigure});
  final LoyaltyProgramSummary program;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(program.isActive ? Icons.stars_rounded : Icons.stars_outlined, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(program.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    program.isActive
                        ? '${program.pointsPerCurrency} point(s) per M1 spent • each point worth M${program.currencyPerPoint} • minimum ${program.minRedeemPoints} to redeem'
                        : 'Customer rewards are currently disabled.',
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onConfigure,
              icon: const Icon(Icons.tune),
              label: const Text('Configure'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({required this.item});
  final PromotionSummary item;

  @override
  Widget build(BuildContext context) {
    final useText = item.maxUses == null ? '${item.useCount} uses' : '${item.useCount}/${item.maxUses} uses';
    final badge = item.code.length <= 2 ? item.code : item.code.substring(0, 2);
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(badge)),
        title: Text(item.name),
        subtitle: Text(
          '${item.code} • ${item.discountType == 'percentage' ? '${item.discountValue}%' : 'M ${item.discountValue}'} off • minimum M ${item.minSubtotal} • $useText',
        ),
        trailing: Chip(
          avatar: Icon(item.currentlyAvailable ? Icons.check_circle_outline : Icons.pause_circle_outline, size: 18),
          label: Text(item.currentlyAvailable ? 'Available' : 'Inactive'),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: retry, child: const Text('Try again')),
            ],
          ),
        ),
      );
}

class _PromotionDraft {
  const _PromotionDraft({
    required this.name,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minSubtotal,
    this.maxUses,
  });
  final String name;
  final String code;
  final String discountType;
  final String discountValue;
  final String minSubtotal;
  final int? maxUses;
}

class _PromotionDialog extends StatefulWidget {
  const _PromotionDialog();
  @override
  State<_PromotionDialog> createState() => _PromotionDialogState();
}

class _PromotionDialogState extends State<_PromotionDialog> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _value = TextEditingController(text: '10');
  final _minimum = TextEditingController(text: '0');
  final _maxUses = TextEditingController();
  String _type = 'percentage';

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _value.dispose();
    _minimum.dispose();
    _maxUses.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New promotion'),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: _name, decoration: const InputDecoration(labelText: 'Promotion name')),
                const SizedBox(height: 12),
                TextField(controller: _code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code', hintText: 'SAVE10')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Discount type'),
                  items: const [
                    DropdownMenuItem(value: 'percentage', child: Text('Percentage')),
                    DropdownMenuItem(value: 'fixed', child: Text('Fixed amount')),
                  ],
                  onChanged: (value) => setState(() => _type = value ?? 'percentage'),
                ),
                const SizedBox(height: 12),
                TextField(controller: _value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Discount value')),
                const SizedBox(height: 12),
                TextField(controller: _minimum, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Minimum basket amount')),
                const SizedBox(height: 12),
                TextField(controller: _maxUses, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Maximum uses (optional)')),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final name = _name.text.trim();
              final code = _code.text.trim();
              final value = double.tryParse(_value.text.trim());
              if (name.length < 2 || code.length < 2 || value == null || value <= 0) return;
              Navigator.pop(
                context,
                _PromotionDraft(
                  name: name,
                  code: code,
                  discountType: _type,
                  discountValue: _value.text.trim(),
                  minSubtotal: _minimum.text.trim().isEmpty ? '0' : _minimum.text.trim(),
                  maxUses: int.tryParse(_maxUses.text.trim()),
                ),
              );
            },
            child: const Text('Create'),
          ),
        ],
      );
}

class _LoyaltyDraft {
  const _LoyaltyDraft({
    required this.name,
    required this.isActive,
    required this.pointsPerCurrency,
    required this.currencyPerPoint,
    required this.minRedeemPoints,
  });
  final String name;
  final bool isActive;
  final String pointsPerCurrency;
  final String currencyPerPoint;
  final int minRedeemPoints;
}

class _LoyaltyDialog extends StatefulWidget {
  const _LoyaltyDialog({required this.current});
  final LoyaltyProgramSummary current;

  @override
  State<_LoyaltyDialog> createState() => _LoyaltyDialogState();
}

class _LoyaltyDialogState extends State<_LoyaltyDialog> {
  late final TextEditingController _name;
  late final TextEditingController _earn;
  late final TextEditingController _value;
  late final TextEditingController _minimum;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.current.name);
    _earn = TextEditingController(text: widget.current.pointsPerCurrency);
    _value = TextEditingController(text: widget.current.currencyPerPoint);
    _minimum = TextEditingController(text: widget.current.minRedeemPoints.toString());
    _active = widget.current.isActive;
  }

  @override
  void dispose() {
    _name.dispose();
    _earn.dispose();
    _value.dispose();
    _minimum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Loyalty programme'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable customer rewards'),
                value: _active,
                onChanged: (value) => setState(() => _active = value),
              ),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Programme name')),
              const SizedBox(height: 12),
              TextField(controller: _earn, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Points earned per M1 spent')),
              const SizedBox(height: 12),
              TextField(controller: _value, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Loti value of one point')),
              const SizedBox(height: 12),
              TextField(controller: _minimum, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minimum points to redeem')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final minimum = int.tryParse(_minimum.text.trim());
              if (_name.text.trim().length < 2 || minimum == null || minimum < 0) return;
              Navigator.pop(
                context,
                _LoyaltyDraft(
                  name: _name.text.trim(),
                  isActive: _active,
                  pointsPerCurrency: _earn.text.trim(),
                  currencyPerPoint: _value.text.trim(),
                  minRedeemPoints: minimum,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      );
}
