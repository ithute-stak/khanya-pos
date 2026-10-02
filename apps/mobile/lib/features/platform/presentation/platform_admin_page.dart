import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';
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
  List<Map<String, dynamic>> _notifications = const [];
  List<Map<String, dynamic>> _staff = const [];
  String? _busyTenantId;
  Timer? _refreshTimer;
  int _knownPending = 0;

  AuthSession? get _session {
    final state = context.read<SessionBloc>().state;
    return state is SessionAuthenticated ? state.session : null;
  }

  bool get _canOperate => _session?.canOperatePlatform ?? false;
  bool get _isSuperAdmin => _session?.isPlatformSuperAdmin ?? false;

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
    if (!silent && mounted) {
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
        repository.notifications(),
        repository.staff(),
      ]);
      if (!mounted) return;
      final pending = results[1] as List<Map<String, dynamic>>;
      final previousPending = _knownPending;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _pending = pending;
        _tenants = results[2] as List<Map<String, dynamic>>;
        _activity = results[3] as List<Map<String, dynamic>>;
        _notifications = results[4] as List<Map<String, dynamic>>;
        _staff = results[5] as List<Map<String, dynamic>>;
        _knownPending = pending.length;
        _error = null;
      });
      if (silent && pending.length > previousPending) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pending.length - previousPending} new business application(s) need review.')),
        );
      }
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _error = _dioMessage(error, 'Could not load the platform dashboard.'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the platform dashboard.');
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  Future<void> _approve(Map<String, dynamic> application) async {
    if (!_canOperate) return;
    final tenantId = application['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().approve(tenantId);
      await _load();
      if (!mounted) return;
      _message('${application['business_name']} approved and activated.');
    } on DioException catch (error) {
      if (mounted) _message(_dioMessage(error, 'Approval failed.'));
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _reject(Map<String, dynamic> application) async {
    if (!_canOperate) return;
    final reason = await _askReason('Reject ${application['business_name']}?', 'Reject application');
    if (!mounted || reason == null) return;
    final tenantId = application['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().reject(tenantId, reason);
      await _load();
      if (mounted) _message('${application['business_name']} was rejected.');
    } on DioException catch (error) {
      if (mounted) _message(_dioMessage(error, 'Rejection failed.'));
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _suspend(Map<String, dynamic> tenant) async {
    if (!_canOperate) return;
    final reason = await _askReason('Suspend ${tenant['business_name']}?', 'Suspend business');
    if (!mounted || reason == null) return;
    final tenantId = tenant['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().suspend(tenantId, reason);
      await _load();
      if (mounted) _message('${tenant['business_name']} has been suspended and active sessions revoked.');
    } on DioException catch (error) {
      if (mounted) _message(_dioMessage(error, 'Could not suspend this business.'));
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _reactivate(Map<String, dynamic> tenant) async {
    if (!_canOperate) return;
    final tenantId = tenant['tenant_id'].toString();
    setState(() => _busyTenantId = tenantId);
    try {
      await context.read<PlatformRepository>().reactivate(tenantId);
      await _load();
      if (mounted) _message('${tenant['business_name']} is active again.');
    } on DioException catch (error) {
      if (mounted) _message(_dioMessage(error, 'Could not reactivate this business.'));
    } finally {
      if (mounted) setState(() => _busyTenantId = null);
    }
  }

  Future<void> _manageStaffRole() async {
    if (!_isSuperAdmin) return;
    final result = await Navigator.of(context).push<(String, String?)>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _PlatformStaffRolePage(),
      ),
    );
    if (!mounted || result == null) return;
    try {
      await context.read<PlatformRepository>().setStaffRole(
            email: result.$1,
            role: result.$2,
          );
      await _load();
      if (mounted) _message('Platform staff access updated.');
    } on DioException catch (error) {
      if (mounted) _message(_dioMessage(error, 'Could not update platform staff.'));
    }
  }

  Future<String?> _askReason(String title, String actionLabel) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _PlatformReasonPage(
          title: title,
          actionLabel: actionLabel,
        ),
      ),
    );
  }

  String _dioMessage(DioException error, String fallback) {
    final data = error.response?.data;
    return data is Map && data['detail'] != null ? data['detail'].toString() : fallback;
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SessionBloc>().state;
    final session = state is SessionAuthenticated ? state.session : null;
    final role = session?.platformRole ?? _summary['platform_role']?.toString();
    final canOperate = role == 'platform_super_admin' || role == 'platform_admin';
    final superAdmin = role == 'platform_super_admin';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Approvals & Platform'),
        actions: [
          if (_pending.isNotEmpty) Chip(label: Text('${_pending.length} pending')),
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
                  if (_error != null) ...[_ErrorCard(message: _error!), const SizedBox(height: 18)],
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Business approvals', style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: KhanyaBrand.navy, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text('Review new Khanya business registrations first, then monitor the wider platform.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
                          ],
                        ),
                      ),
                      _RoleChip(role: role),
                    ],
                  ),
                  if (!canOperate) ...[
                    const SizedBox(height: 14),
                    const _InfoCard(
                      icon: Icons.visibility_outlined,
                      title: 'Read-only platform access',
                      message: 'Support can monitor businesses, activity and notifications, but cannot approve, reject, suspend or reactivate tenants.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle(context, 'Account approvals', _pending.isEmpty ? null : '${_pending.length} waiting'),
                  const SizedBox(height: 12),
                  if (_pending.isEmpty)
                    const _InfoCard(icon: Icons.task_alt_outlined, title: 'No applications waiting', message: 'New registrations will appear here automatically.')
                  else
                    ..._pending.map((application) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ApplicationCard(
                            application: application,
                            busy: _busyTenantId == application['tenant_id'].toString(),
                            canOperate: canOperate,
                            onApprove: () => _approve(application),
                            onReject: () => _reject(application),
                          ),
                        )),
                  const SizedBox(height: 30),                  _sectionTitle(context, 'Platform overview', null),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      _MetricCard(icon: Icons.business_outlined, label: 'Total businesses', value: '${_summary['total_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.pending_actions_outlined, label: 'Pending approval', value: '${_summary['pending_applications'] ?? 0}'),
                      _MetricCard(icon: Icons.check_circle_outline, label: 'Active businesses', value: '${_summary['active_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.pause_circle_outline, label: 'Suspended', value: '${_summary['suspended_tenants'] ?? 0}'),
                      _MetricCard(icon: Icons.receipt_long_outlined, label: 'Transactions today', value: '${_summary['transactions_today'] ?? 0}'),
                      _MetricCard(icon: Icons.payments_outlined, label: 'Sales today', value: _money(_summary['gross_sales_today'])),
                      _MetricCard(icon: Icons.devices_outlined, label: 'Active devices', value: '${_summary['active_devices_today'] ?? 0}'),
                      _MetricCard(icon: Icons.notifications_outlined, label: 'Platform events', value: '${_summary['platform_events_today'] ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 30),
                  _sectionTitle(context, 'Businesses', null),
                  const SizedBox(height: 12),
                  _businessTable(canOperate),
                  const SizedBox(height: 30),
                  _sectionTitle(context, 'Platform notifications', '${_notifications.length} recent'),
                  const SizedBox(height: 12),
                  _notificationList(),
                  const SizedBox(height: 30),
                  _sectionTitle(context, 'Tenant activity today', null),
                  const SizedBox(height: 12),
                  _activityTable(),
                  const SizedBox(height: 30),
                  Row(
                    children: [
                      Expanded(child: _sectionTitle(context, 'Platform staff', null)),
                      if (superAdmin) FilledButton.icon(onPressed: _manageStaffRole, icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('Manage role')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _staffTable(),
                ],
              ),
            ),
    );
  }

  Widget _businessTable(bool canOperate) {
    if (_tenants.isEmpty) {
      return const _InfoCard(icon: Icons.business_outlined, title: 'No businesses yet', message: 'Businesses will appear here after registration.');
    }
    return Card(
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
            final status = tenant['status']?.toString() ?? 'unknown';
            final busy = _busyTenantId == tenant['tenant_id'].toString();
            final reason = tenant['suspension_reason']?.toString();
            return DataRow(cells: [
              DataCell(Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tenant['business_name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(reason?.isNotEmpty == true ? 'Suspended: $reason' : tenant['owner_email']?.toString() ?? '', style: Theme.of(context).textTheme.bodySmall),
              ])),
              DataCell(_StatusChip(status: status)),
              DataCell(Text('${tenant['active_branches'] ?? 0}')),
              DataCell(Text('${tenant['active_users'] ?? 0}')),
              DataCell(Text(_money(tenant['gross_sales']))),
              DataCell(Text('${tenant['transactions'] ?? 0}')),
              DataCell(Text('${tenant['active_devices'] ?? 0}')),
              DataCell(!canOperate
                  ? const Text('Read only')
                  : status == 'approved'
                      ? TextButton(onPressed: busy ? null : () => _suspend(tenant), child: const Text('Suspend'))
                      : status == 'suspended'
                          ? FilledButton.tonal(onPressed: busy ? null : () => _reactivate(tenant), child: const Text('Reactivate'))
                          : const Text('—')),
            ]);
          }).toList(growable: false),
        ),
      ),
    );
  }

  Widget _notificationList() {
    if (_notifications.isEmpty) {
      return const _InfoCard(icon: Icons.notifications_none_outlined, title: 'No platform events yet', message: 'Registrations and platform actions will appear here.');
    }
    return Card(
      child: Column(
        children: _notifications.take(20).map((item) {
          final severity = item['severity']?.toString() ?? 'info';
          return ListTile(
            leading: Icon(severity == 'warning' ? Icons.warning_amber_rounded : Icons.notifications_outlined),
            title: Text(item['title']?.toString() ?? 'Platform event', style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${item['message'] ?? ''}\n${_formatDateTime(item['occurred_at'])}'),
            isThreeLine: true,
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _activityTable() {
    if (_activity.isEmpty) {
      return const _InfoCard(icon: Icons.insights_outlined, title: 'No tenant activity yet', message: 'Daily tenant activity will appear as businesses use Khanya.');
    }
    return Card(
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
            DataColumn(label: Text('Last activity')),
          ],
          rows: _activity.map((item) => DataRow(cells: [
                DataCell(Text(item['business_name']?.toString() ?? '—')),
                DataCell(_StatusChip(status: item['status']?.toString() ?? 'unknown')),
                DataCell(Text(_money(item['gross_sales']))),
                DataCell(Text('${item['transactions'] ?? 0}')),
                DataCell(Text('${item['active_users'] ?? 0}')),
                DataCell(Text('${item['active_devices'] ?? 0}')),
                DataCell(Text(_formatDateTime(item['last_activity_at']))),
              ])).toList(growable: false),
        ),
      ),
    );
  }

  Widget _staffTable() {
    if (_staff.isEmpty) {
      return const _InfoCard(icon: Icons.admin_panel_settings_outlined, title: 'No platform staff listed', message: 'Super Admin can grant platform roles to existing Khanya users.');
    }
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Name')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Account')),
          ],
          rows: _staff.map((item) => DataRow(cells: [
                DataCell(Text(item['display_name']?.toString() ?? '—')),
                DataCell(Text(item['email']?.toString() ?? '—')),
                DataCell(_RoleChip(role: item['platform_role']?.toString())),
                DataCell(Text(item['is_active'] == true ? 'Active' : 'Disabled')),
              ])).toList(growable: false),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title, String? trailing) {
    return Row(children: [
      Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
      if (trailing != null) Chip(label: Text(trailing)),
    ]);
  }

  String _formatDateTime(Object? value) {
    if (value == null) return 'No activity';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
  Widget build(BuildContext context) => SizedBox(
        width: 220,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: KhanyaBrand.forest),
              const SizedBox(height: 12),
              Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(label, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.black54)),
            ]),
          ),
        ),
      );
}

class _PlatformStaffRolePage extends StatefulWidget {
  const _PlatformStaffRolePage();

  @override
  State<_PlatformStaffRolePage> createState() => _PlatformStaffRolePageState();
}

class _PlatformStaffRolePageState extends State<_PlatformStaffRolePage> {
  final _emailController = TextEditingController();
  String? _role = 'platform_support';
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid existing Khanya user email.');
      return;
    }
    Navigator.of(context).pop((email, _role));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage platform staff')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Platform access',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Assign or remove platform-level access for an existing Khanya user.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _emailController,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: 'Existing Khanya user email',
                        hintText: 'staff@example.com',
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String?>(
                      initialValue: _role,
                      decoration: const InputDecoration(labelText: 'Platform role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'platform_super_admin',
                          child: Text('Super Admin'),
                        ),
                        DropdownMenuItem(
                          value: 'platform_admin',
                          child: Text('Admin'),
                        ),
                        DropdownMenuItem(
                          value: 'platform_support',
                          child: Text('Support (read-only)'),
                        ),
                        DropdownMenuItem(
                          value: null,
                          child: Text('Remove platform access'),
                        ),
                      ],
                      onChanged: (value) => setState(() => _role = value),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.save_outlined),
                        label: const Text('Save role'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlatformReasonPage extends StatefulWidget {
  const _PlatformReasonPage({
    required this.title,
    required this.actionLabel,
  });

  final String title;
  final String actionLabel;

  @override
  State<_PlatformReasonPage> createState() => _PlatformReasonPageState();
}

class _PlatformReasonPageState extends State<_PlatformReasonPage> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.length < 2) {
      setState(() => _error = 'Give a clear reason for this decision.');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 36),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'This reason will be recorded with the platform action.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 22),
                    TextField(
                      controller: _controller,
                      autofocus: true,
                      maxLength: 500,
                      minLines: 3,
                      maxLines: 6,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Reason',
                        hintText: 'Give a clear reason for the decision',
                        errorText: _error,
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 50,
                      child: FilledButton(
                        onPressed: _submit,
                        child: Text(widget.actionLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String? role;

  @override
  Widget build(BuildContext context) {
    final label = switch (role) {
      'platform_super_admin' => 'Super Admin',
      'platform_admin' => 'Admin',
      'platform_support' => 'Support',
      _ => 'Platform staff',
    };
    return Chip(avatar: const Icon(Icons.admin_panel_settings_outlined, size: 17), label: Text(label));
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
      label: Text(normalized.isEmpty ? 'Unknown' : '${normalized[0].toUpperCase()}${normalized.substring(1)}'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.application, required this.busy, required this.canOperate, required this.onApprove, required this.onReject});
  final Map<String, dynamic> application;
  final bool busy;
  final bool canOperate;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 20,
          runSpacing: 14,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 520,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(application['business_name']?.toString() ?? 'Unnamed business', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text('${application['owner_name'] ?? 'Unknown owner'} • ${application['owner_email'] ?? 'No email'}'),
                if (application['owner_phone'] != null) Text(application['owner_phone'].toString()),
                const SizedBox(height: 5),
                Text('Submitted ${application['submitted_at'] ?? ''}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54)),
              ]),
            ),
            if (canOperate) ...[
              OutlinedButton.icon(onPressed: busy ? null : onReject, icon: const Icon(Icons.close_rounded), label: const Text('Reject')),
              FilledButton.icon(
                onPressed: busy ? null : onApprove,
                icon: busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                label: const Text('Approve'),
              ),
            ] else
              const Chip(label: Text('Read only')),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(children: [
            Icon(icon, size: 32, color: KhanyaBrand.forest),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(message),
            ])),
          ]),
        ),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [const Icon(Icons.error_outline), const SizedBox(width: 10), Expanded(child: Text(message))]),
        ),
      );
}
