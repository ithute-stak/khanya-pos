import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/storage/app_database.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/customers/data/customer_database.dart';

class SyncCentrePage extends StatefulWidget {
  const SyncCentrePage({super.key});

  @override
  State<SyncCentrePage> createState() => _SyncCentrePageState();
}

class _SyncCentrePageState extends State<SyncCentrePage> {
  bool _loading = true;
  String? _error;
  List<_SyncOperation> _operations = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return;
    final tenantId = state.session.selectedTenantId;
    final branchId = state.session.selectedBranchId;
    if (tenantId == null || branchId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = context.read<AppDatabase>();
      final customerDb = context.read<CustomerDatabase>();
      final results = await Future.wait<dynamic>([
        db.getSalesForHistory(tenantId: tenantId, branchId: branchId),
        db.getPendingPurchases(tenantId: tenantId, branchId: branchId),
        db.getPendingExpenses(tenantId: tenantId, branchId: branchId),
        db.getPendingDocuments(tenantId: tenantId, branchId: branchId),
        customerDb.getPendingPayments(tenantId: tenantId, branchId: branchId),
      ]);

      final items = <_SyncOperation>[
        for (final item in results[0] as List<PendingSale>)
          if (item.status != 'synced')
            _SyncOperation(
              type: 'Sale',
              reference: _shortRef(item.clientOperationId),
              status: item.status,
              attempts: item.attempts,
              error: item.lastError,
              createdAt: item.createdAt,
              icon: Icons.point_of_sale_outlined,
            ),
        for (final item in results[1] as List<PendingPurchase>)
          _SyncOperation(
            type: 'Purchase',
            reference: _shortRef(item.clientOperationId),
            status: item.status,
            attempts: item.attempts,
            error: item.lastError,
            createdAt: item.createdAt,
            icon: Icons.shopping_bag_outlined,
          ),
        for (final item in results[2] as List<PendingExpense>)
          _SyncOperation(
            type: 'Expense',
            reference: _shortRef(item.clientOperationId),
            status: item.status,
            attempts: item.attempts,
            error: item.lastError,
            createdAt: item.createdAt,
            icon: Icons.account_balance_wallet_outlined,
          ),
        for (final item in results[3] as List<PendingDocument>)
          if (item.status != 'uploaded')
            _SyncOperation(
              type: 'Receipt',
              reference: item.filename,
              status: item.status,
              attempts: item.attempts,
              error: item.lastError,
              createdAt: item.createdAt,
              icon: Icons.receipt_long_outlined,
            ),
        for (final item in results[4] as List<PendingCustomerPayment>)
          _SyncOperation(
            type: 'Customer payment',
            reference: _shortRef(item.clientOperationId),
            status: item.status,
            attempts: item.attempts,
            error: item.lastError,
            createdAt: item.createdAt,
            icon: Icons.payments_outlined,
          ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (!mounted) return;
      setState(() => _operations = List.unmodifiable(items));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the local sync queue.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _syncNow() async {
    context.read<SyncBloc>().add(const SyncRequested());
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncBloc>().state;
    final conflicts = _operations.where((item) => item.status == 'conflict').length;
    final queued = _operations.where((item) =>
      item.status == 'pending' || item.status == 'syncing' || item.status == 'uploading').length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Centre'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _SyncOverviewCard(
              queued: queued,
              conflicts: conflicts,
              syncing: sync.isSyncing,
              onSync: sync.isSyncing ? null : _syncNow,
            ),
            const SizedBox(height: 18),
            Text(
              'Operations on this device',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              'Queued and failed work stays visible here until it reaches Khanya successfully.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            if (_loading && _operations.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 56),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _MessageCard(
                icon: Icons.cloud_off_outlined,
                title: 'Sync queue unavailable',
                message: _error!,
              )
            else if (_operations.isEmpty)
              const _MessageCard(
                icon: Icons.verified_outlined,
                title: 'Everything is synced',
                message: 'There are no queued or failed operations on this device.',
              )
            else
              ..._operations.map(
                (item) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _SyncOperationCard(operation: item),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SyncOverviewCard extends StatelessWidget {
  const _SyncOverviewCard({
    required this.queued,
    required this.conflicts,
    required this.syncing,
    required this.onSync,
  });

  final int queued;
  final int conflicts;
  final bool syncing;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final metrics = Wrap(
              spacing: 22,
              runSpacing: 14,
              children: [
                _Metric(
                  icon: syncing ? Icons.sync : Icons.cloud_sync_outlined,
                  label: syncing ? 'Syncing now' : 'Queued',
                  value: '$queued',
                ),
                _Metric(
                  icon: conflicts > 0 ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  label: 'Needs attention',
                  value: '$conflicts',
                ),
              ],
            );
            final button = FilledButton.icon(
              onPressed: onSync,
              icon: syncing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.sync_rounded),
              label: Text(syncing ? 'Syncing…' : 'Sync now'),
            );

            if (constraints.maxWidth >= 620) {
              return Row(
                children: [
                  Expanded(child: metrics),
                  const SizedBox(width: 16),
                  button,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                metrics,
                const SizedBox(height: 16),
                button,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(icon, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _SyncOperationCard extends StatelessWidget {
  const _SyncOperationCard({required this.operation});
  final _SyncOperation operation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isConflict = operation.status == 'conflict';

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: isConflict ? scheme.errorContainer : scheme.secondaryContainer,
              foregroundColor: isConflict ? scheme.onErrorContainer : scheme.onSecondaryContainer,
              child: Icon(operation.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(operation.type, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(_statusLabel(operation.status)),
                      ),
                    ],
                  ),
                  Text(
                    operation.reference,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 6),
                  Text(_formatTime(operation.createdAt)),
                  if (operation.attempts > 0)
                    Text(
                      '${operation.attempts} sync attempt${operation.attempts == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (operation.error?.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        operation.error!,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.icon, required this.title, required this.message});
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SyncOperation {
  const _SyncOperation({
    required this.type,
    required this.reference,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.icon,
    this.error,
  });

  final String type;
  final String reference;
  final String status;
  final int attempts;
  final DateTime createdAt;
  final IconData icon;
  final String? error;
}

String _shortRef(String value) => value.length <= 12 ? value : value.substring(0, 12);

String _statusLabel(String value) => switch (value) {
      'pending' => 'Queued',
      'syncing' => 'Syncing',
      'uploading' => 'Uploading',
      'conflict' => 'Needs attention',
      _ => value,
    };

String _formatTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
