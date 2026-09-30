import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/platform/data/platform_repository.dart';

class PlatformAdminPage extends StatefulWidget {
  const PlatformAdminPage({super.key});

  @override
  State<PlatformAdminPage> createState() => _PlatformAdminPageState();
}

class _PlatformAdminPageState extends State<PlatformAdminPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _pending = const [];
  List<Map<String, dynamic>> _tenants = const [];
  List<Map<String, dynamic>> _activity = const [];
  String? _busyTenantId;
  Timer? _refreshTimer;
  int _knownPending = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final repository = context.read<PlatformRepository>();
      final results = await Future.wait<dynamic>([
        repository.summary(),
        repository.pendingApplications(),
        repository.tenants(),
        repository.dailyActivity(),
      ]);
      if (!mounted) return;
      final pending = results[1] as List<Map<String, dynamic>>;
      final previousPending = _knownPending;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _pending = pending;
        _tenants = results[2] as List<Map<String, dynamic>>;
        _activity = results[3] as List<Map<String, dynamic>>;
        _knownPending = pending.length;
        _error = null;
      });
      if (silent && previousPending > 0 && pending.length > previousPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${pending.length - previousPending} new business application(s) need review.'),
            action: SnackBarAction(label: 'Review', onPressed: () {}),
          ),
        );
      }
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      setState(() => _error = detail ?? 'Could not load the platform dashboard.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the platform dashboard.');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> application) async {
    final tenantId = application['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().approve(tenantId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application['business_name']} approved and activated.')),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data is Map && data['detail'] != null ? data['detail'].toString() : 'Approval failed.')),
      );
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _reject(Map<String, dynamic> application) async {
    final reason = await _askReason(
      title: 'Reject ${application['business_name']}?',
      actionLabel: 'Reject application',
    );
    if (!mounted || reason == null) return;
    final tenantId = application['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().reject(tenantId, reason);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${application['business_name']} was rejected.')),
      );
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _suspend(Map<String, dynamic> tenant) async {
    final reason = await _askReason(
      title: 'Suspend ${tenant['business_name']}?',
      actionLabel: 'Suspend business',
    );
    if (!mounted || reason == null) return;
    final tenantId = tenant['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().suspend(tenantId, reason);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tenant['business_name']} has been suspended.')),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      _showDioError(error, fallback: 'Could not suspend this business.');
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _reactivate(Map<String, dynamic> tenant) async {
    final tenantId = tenant['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().reactivate(tenantId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tenant['business_name']} is active again.')),
      );
    } on DioException catch (error) {
      if (!mounted) return;
      _showDioError(error, fallback: 'Could not reactivate this business.');
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<String?> _askReason({required String title, required String actionLabel}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason',
            hintText: 'Give a clear reason for the decision',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length >= 2) Navigator.pop(context, value);
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  void _showDioError(DioException error, {required String fallback}) {
    final data = error.response?.data;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(data is Map && data['detail'] != null ? data['detail'].toString() : fallback)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khanya Platform Administration'),
        actions: [
          if (_pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Chip(
                avatar: const Icon(Icons.notifications_active_outlined, size: 18),
                label: Text('${_pending.length} pending'),
              ),
            ),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh'),
          IconButton(
            onPressed: () => context.read<SessionBloc>().add(const SessionSignedOut()),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading && _summary.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (_error != null) ...[
                    _ErrorCard(message: _error!),
                    const SizedBox(height: 18),
                  ],
                  Text(
                    'Platform overview',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: KhanyaBrand.navy,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Monitor Khanya as a service without entering a tenant workspace.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _MetricCard(icon: Icons.business_outlined, label: 'Total businesses', value: '${_summary['total_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.pending_actions_outlined, label: 'Pending approval', value: '${_summary['pending_applications'] ?? 0}'),
                      _MetricCard(icon: Icons.check_circle_outline, label: 'Active businesses', value: '${_summary['active_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.pause_circle_outline, label: 'Suspended', value: '${_summary['suspended_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.receipt_long_outlined, label: 'Transactions today', value: '${_summary['transactions_today'] ?? 0}'),
                      _MetricCard(icon: Icons.payments_outlined, label: 'Sales processed today', value: _money(_summary['gross_sales_today'])),
                      _MetricCard(icon: Icons.devices_outlined, label: 'Active devices today', value: '${_summary['active_devices_today'] ?? 0}'),
                      _MetricCard(icon: Icons.bolt_outlined, label: 'Tenants active today', value: '${_summary['active_tenants_today'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _sectionTitle(context, 'Account approvals', trailing: _pending.isEmpty ? null : '${_pending.length} waiting'),
                  const SizedBox(height: 12),
                  if (_pending.isEmpty)
                    const _EmptyCard(
                      icon: Icons.task_alt_outlined,
                      title: 'No applications waiting',
                      message: 'New business registrations will appear here automatically for review.',
                    )
                  else
                    ..._pending.map(
                      (application) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ApplicationCard(
                          application: application,
                          busy: _busyTenantId == application['tenant_id'].toString(),
                          onApprove: () => _approve(application),
                          onReject: () => _reject(application),
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                  _sectionTitle(context, 'Businesses'),
                  const SizedBox(height: 12),
                  if (_tenants.isEmpty)
                    const _EmptyCard(
                      icon: Icons.business_outlined,
                      title: 'No businesses yet',
                      message: 'Approved, pending, rejected and suspended businesses will appear here.',
                    )
                  else
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Business')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Branches'), numeric: true),
                            DataColumn(label: Text('Users'), numeric: true),
                            DataColumn(label: Text('Today sales'), numeric: true),
                            DataColumn(label: Text('Transactions'), numeric: true),
                            DataColumn(label: Text('Devices'), numeric: true),
                            DataColumn(label: Text('Action')),
                          ],
                          rows: _tenants.map((tenant) {
                            final tenantId = tenant['tenant_id'].toString();
                            final status = tenant['status']?.toString() ?? tenant['onboarding_status']?.toString() ?? 'unknown';
                            final busy = _busyTenantId == tenantId;
                            return DataRow(cells: [
                              DataCell(
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(tenant['business_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(tenant['owner_email']?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              DataCell(_StatusChip(status: status)),
                              DataCell(Text('${tenant['active_branches'] ?? 0}')),
                              DataCell(Text('${tenant['active_users'] ?? 0}')),
                              DataCell(Text(_money(tenant['gross_sales']))),
                              DataCell(Text('${tenant['transactions'] ?? 0}')),
                              DataCell(Text('${tenant['active_devices'] ?? 0}')),
                              DataCell(
                                status == 'approved'
                                    ? TextButton(onPressed: busy ? null : () => _suspend(tenant), child: const Text('Suspend'))
                                    : status == 'suspended'
                                        ? FilledButton.tonal(onPressed: busy ? null : () => _reactivate(tenant), child: const Text('Reactivate'))
                                        : const Text('—'),
                              ),
                            ]);
                          }).toList(growable: false),
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                  _sectionTitle(context, 'Tenant activity today'),
                  const SizedBox(height: 12),
                  if (_activity.isEmpty)
                    const _EmptyCard(
                      icon: Icons.insights_outlined,
                      title: 'No tenant activity yet',
                      message: 'Daily tenant activity will appear as businesses use Khanya.',
                    )
                  else
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Business')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Sales'), numeric: true),
                            DataColumn(label: Text('Transactions'), numeric: true),
                            DataColumn(label: Text('Active users'), numeric: true),
                            DataColumn(label: Text('Devices'), numeric: true),
                            DataColumn(label: Text('Audit events'), numeric: true),
                            DataColumn(label: Text('Last activity')),
                          ],
                          rows: _activity
                              .map(
                                (item) => DataRow(
                                  cells: [
                                    DataCell(Text(item['business_name']?.toString() ?? '—')),
                                    DataCell(_StatusChip(status: item['status']?.toString() ?? '—')),
                                    DataCell(Text(_money(item['gross_sales']))),
                                    DataCell(Text('${item['transactions'] ?? 0}')),
                                    DataCell(Text('${item['active_users'] ?? 0}')),
                                    DataCell(Text('${item['active_devices'] ?? 0}')),
                                    DataCell(Text('${item['activity_events'] ?? 0}')),
                                    DataCell(Text(_formatDateTime(item['last_activity_at']))),
                                  ],
                                ),
                              )
                              .toList(growable: false),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, {String? trailing}) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
        if (trailing != null) Chip(label: Text(trailing)),
      ],
    );
  }

  String _formatDateTime(Object? value) {
    if (value == null) return 'No activity';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour}:$minute';
  }

  String _money(Object? value) {
    final amount = double.tryParse(value?.toString() ?? '') ?? 0;
    return 'M ${amount.toStringAsFixed(2)}';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: KhanyaBrand.forest),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final normalized = status.toLowerCase();
    final icon = switch (normalized) {
      'approved' => Icons.check_circle_outline,
      'pending' => Icons.schedule_outlined,
      'suspended' => Icons.pause_circle_outline,
      'rejected' => Icons.cancel_outlined,
      _ => Icons.help_outline,
    };
    return Chip(
      avatar: Icon(icon, size: 17),
      label: Text(normalized.isEmpty ? 'unknown' : '${normalized[0].toUpperCase()}${normalized.substring(1)}'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.application,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final Map<String, dynamic> application;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  application['business_name']?.toString() ?? 'Unnamed business',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 5),
                Text(
                  '${application['owner_name'] ?? 'Unknown owner'} • ${application['owner_email'] ?? 'No email'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (application['owner_phone'] != null) ...[
                  const SizedBox(height: 3),
                  Text(application['owner_phone'].toString()),
                ],
                const SizedBox(height: 5),
                Text(
                  'Submitted ${application['submitted_at'] ?? ''}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
                ),
              ],
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : onReject,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: busy ? null : onApprove,
                  icon: busy
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: const Text('Approve'),
                ),
              ],
            );
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 16), actions],
              );
            }
            return Row(children: [Expanded(child: details), const SizedBox(width: 16), actions]);
          },
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Icon(icon, size: 34, color: KhanyaBrand.forest),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.error_outline),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
