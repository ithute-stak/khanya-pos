import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/platform/data/platform_repository.dart';

class PlatformSubscriptionsPage extends StatefulWidget {
  const PlatformSubscriptionsPage({super.key});

  @override
  State<PlatformSubscriptionsPage> createState() => _PlatformSubscriptionsPageState();
}

class _PlatformSubscriptionsPageState extends State<PlatformSubscriptionsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];
  String? _busyTenantId;

  bool get _canOperate {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return false;
    return state.session.canOperatePlatform;
  }

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
      final items = await context.read<PlatformRepository>().subscriptions();
      if (mounted) setState(() => _items = items);
    } on DioException catch (error) {
      if (mounted) setState(() => _error = _message(error, 'Could not load subscriptions.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(Map<String, dynamic> item) async {
    if (!_canOperate) return;
    var plan = item['plan']?.toString() ?? 'starter';
    var status = item['status']?.toString() ?? 'trialing';
    final reference = TextEditingController(text: item['billing_reference']?.toString() ?? '');
    final notes = TextEditingController(text: item['notes']?.toString() ?? '');
    final result = await showDialog<(String, String, String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Subscription • ${item['tenant_name'] ?? 'Business'}'),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: plan,
                  decoration: const InputDecoration(labelText: 'Plan'),
                  items: const [
                    DropdownMenuItem(value: 'starter', child: Text('Starter • 3 staff / 1 branch')),
                    DropdownMenuItem(value: 'business', child: Text('Business • 10 staff / 3 branches')),
                    DropdownMenuItem(value: 'pro', child: Text('Pro • 50 staff / 20 branches')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => plan = value);
                  },
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Billing status'),
                  items: const [
                    DropdownMenuItem(value: 'trialing', child: Text('Trialing')),
                    DropdownMenuItem(value: 'active', child: Text('Active')),
                    DropdownMenuItem(value: 'past_due', child: Text('Past due')),
                    DropdownMenuItem(value: 'suspended', child: Text('Billing suspended')),
                    DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => status = value);
                  },
                ),
                const SizedBox(height: 14),
                TextField(controller: reference, decoration: const InputDecoration(labelText: 'Billing reference')),
                const SizedBox(height: 14),
                TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Billing notes')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, (plan, status, reference.text.trim(), notes.text.trim())),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    reference.dispose();
    notes.dispose();
    if (!mounted || result == null) return;
    final tenantId = item['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().updateSubscription(
            tenantId: tenantId,
            plan: result.$1,
            status: result.$2,
            billingReference: result.$3,
            notes: result.$4,
          );
      await _load();
    } on DioException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_message(error, 'Could not update subscription.'))));
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _items.where((item) => item['status'] == 'active').length;
    final trial = _items.where((item) => item['status'] == 'trialing').length;
    final attention = _items.where((item) => item['status'] == 'past_due' || item['status'] == 'suspended').length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscriptions & Billing'),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: _loading && _items.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Commercial controls', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: KhanyaBrand.navy)),
                const SizedBox(height: 4),
                const Text('Manage tenant plans and billing state independently from operational suspension.'),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Metric(label: 'Subscriptions', value: '${_items.length}', icon: Icons.workspace_premium_outlined),
                    _Metric(label: 'Active', value: '$active', icon: Icons.check_circle_outline),
                    _Metric(label: 'Trials', value: '$trial', icon: Icons.hourglass_top_outlined),
                    _Metric(label: 'Needs attention', value: '$attention', icon: Icons.warning_amber_outlined),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!))),
                ],
                const SizedBox(height: 20),
                Card(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Business')),
                        DataColumn(label: Text('Plan')),
                        DataColumn(label: Text('Billing')),
                        DataColumn(label: Text('Staff limit'), numeric: true),
                        DataColumn(label: Text('Branch limit'), numeric: true),
                        DataColumn(label: Text('Period ends')),
                        DataColumn(label: Text('Action')),
                      ],
                      rows: _items.map((item) {
                        final tenantId = item['tenant_id'].toString();
                        final busy = _busyTenantId == tenantId;
                        return DataRow(cells: [
                          DataCell(Text(item['tenant_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700))),
                          DataCell(Text(_title(item['plan']))),
                          DataCell(Chip(label: Text(_title(item['status'])))),
                          DataCell(Text('${item['seat_limit'] ?? 0}')),
                          DataCell(Text('${item['branch_limit'] ?? 0}')),
                          DataCell(Text(_date(item['current_period_end']))),
                          DataCell(_canOperate
                              ? TextButton(onPressed: busy ? null : () => _edit(item), child: Text(busy ? 'Saving…' : 'Manage'))
                              : const Text('Read only')),
                        ]);
                      }).toList(growable: false),
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

  String _date(Object? value) {
    if (value == null) return '—';
    final parsed = DateTime.tryParse(value.toString())?.toLocal();
    if (parsed == null) return '—';
    return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  String _title(Object? value) {
    final raw = value?.toString().replaceAll('_', ' ') ?? '—';
    if (raw.isEmpty) return '—';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: KhanyaBrand.forest),
                const SizedBox(height: 10),
                Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                Text(label),
              ],
            ),
          ),
        ),
      );
}
