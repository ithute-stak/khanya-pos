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
  List<Map<String, dynamic>> _activity = const [];
  String? _busyTenantId;

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
      final repository = context.read<PlatformRepository>();
      final results = await Future.wait<dynamic>([
        repository.summary(),
        repository.pendingApplications(),
        repository.dailyActivity(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _pending = results[1] as List<Map<String, dynamic>>;
        _activity = results[2] as List<Map<String, dynamic>>;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final detail = data is Map ? data['detail']?.toString() : null;
      setState(() => _error = detail ?? 'Could not load the platform dashboard.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the platform dashboard.');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reject ${application['business_name']}?'),
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
            child: const Text('Reject application'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khanya System Administration'),
        actions: [
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
                    'See onboarding decisions and tenant activity without entering or changing a tenant workspace.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _MetricCard(
                        icon: Icons.pending_actions_outlined,
                        label: 'Pending applications',
                        value: '${_summary['pending_applications'] ?? 0}',
                      ),
                      _MetricCard(
                        icon: Icons.business_outlined,
                        label: 'Active tenants',
                        value: '${_summary['active_tenants'] ?? 0}',
                      ),
                      _MetricCard(
                        icon: Icons.bolt_outlined,
                        label: 'Active today',
                        value: '${_summary['active_tenants_today'] ?? 0}',
                      ),
                      _MetricCard(
                        icon: Icons.timeline_outlined,
                        label: 'Events today',
                        value: '${_summary['activity_events_today'] ?? 0}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Account approvals',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (_pending.isNotEmpty)
                        Chip(label: Text('${_pending.length} waiting')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_pending.isEmpty)
                    const _EmptyCard(
                      icon: Icons.task_alt_outlined,
                      title: 'No applications waiting',
                      message: 'New business registrations will appear here for review.',
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
                  Text(
                    'Tenant activity today',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  if (_activity.isEmpty)
                    const _EmptyCard(
                      icon: Icons.insights_outlined,
                      title: 'No tenant activity yet',
                      message: 'Daily tenant activity will appear as audited actions are recorded.',
                    )
                  else
                    Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Business')),
                            DataColumn(label: Text('Status')),
                            DataColumn(label: Text('Events'), numeric: true),
                            DataColumn(label: Text('Active users'), numeric: true),
                            DataColumn(label: Text('Last activity')),
                          ],
                          rows: _activity
                              .map(
                                (item) => DataRow(
                                  cells: [
                                    DataCell(Text(item['business_name']?.toString() ?? '—')),
                                    DataCell(Text(item['status']?.toString() ?? '—')),
                                    DataCell(Text('${item['activity_events'] ?? 0}')),
                                    DataCell(Text('${item['active_users'] ?? 0}')),
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

  String _formatDateTime(Object? value) {
    if (value == null) return 'No activity';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour}:$minute';
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
              Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
            ],
          ),
        ),
      ),
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
            return Row(
              children: [Expanded(child: details), const SizedBox(width: 16), actions],
            );
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
