import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';
import 'package:khanya_pos/core/realtime/realtime_bloc.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionState = context.watch<SessionBloc>().state;
    final session = sessionState is SessionAuthenticated ? sessionState.session : null;
    final membership = session?.memberships
        .where((item) => item.tenantId == session.selectedTenantId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khanya POS'),
        actions: [
          BlocBuilder<ConnectivityBloc, ConnectivityState>(
            builder: (context, state) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                avatar: Icon(state.isNetworkAvailable ? Icons.cloud_done : Icons.cloud_off, size: 17),
                label: Text(state.isNetworkAvailable ? 'Online' : 'Offline'),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => context.read<SessionBloc>().add(const SessionSignedOut()),
            icon: const Icon(Icons.logout),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 14, padding, 8),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session == null ? 'Welcome' : 'Hello ${session.displayName.split(' ').first}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        membership?.tenantName ?? 'Khanya Resources Small Business POS',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54),
                      ),
                      const SizedBox(height: 16),
                      const _SystemStatusCard(),
                      const SizedBox(height: 22),
                      Text('Business tools', style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(padding, 8, padding, 28),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 340,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  delegate: SliverChildListDelegate.fixed([
                    _ModuleCard(
                      title: 'New Sale',
                      description: 'Fast checkout, offline queue and payments',
                      icon: Icons.point_of_sale,
                      onTap: () => context.push('/pos'),
                    ),
                    _ModuleCard(
                      title: 'Products',
                      description: 'Prices, SKUs, barcodes and product catalogue',
                      icon: Icons.inventory_2_outlined,
                      onTap: () => context.push('/products'),
                    ),
                    _ModuleCard(
                      title: 'Inventory',
                      description: 'On-hand quantities and low-stock visibility',
                      icon: Icons.warehouse_outlined,
                      onTap: () => context.push('/inventory'),
                    ),
                    _ModuleCard(
                      title: 'Purchases',
                      description: 'Buy stock, receive items and track supplier balances',
                      icon: Icons.shopping_bag_outlined,
                      onTap: () => context.push('/purchases'),
                    ),
                    _ModuleCard(
                      title: 'Receipt Vault',
                      description: 'Photograph and keep shopping receipts and supplier invoices',
                      icon: Icons.receipt_long_outlined,
                      onTap: () => context.push('/receipts'),
                    ),
                    _ModuleCard(
                      title: 'Suppliers',
                      description: 'Supplier contacts, purchases and outstanding balances',
                      icon: Icons.local_shipping_outlined,
                      onTap: () => context.push('/suppliers'),
                    ),
                    _ModuleCard(
                      title: 'Expenses',
                      description: 'Rent, electricity, transport, fuel and daily business costs',
                      icon: Icons.account_balance_wallet_outlined,
                      onTap: () => context.push('/expenses'),
                    ),
                    const _ModuleCard(
                      title: 'Accounting',
                      description: 'Next: ledgers, reports and tax readiness',
                      icon: Icons.account_balance_outlined,
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SystemStatusCard extends StatelessWidget {
  const _SystemStatusCard();

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncBloc>().state;
    final realtime = context.watch<RealtimeBloc>().state;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 18,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusItem(
              icon: sync.isSyncing ? Icons.sync : Icons.cloud_sync_outlined,
              label: sync.isSyncing ? 'Syncing' : '${sync.pendingCount} queued',
            ),
            _StatusItem(
              icon: sync.conflictCount > 0 ? Icons.warning_amber_rounded : Icons.verified_outlined,
              label: sync.conflictCount > 0 ? '${sync.conflictCount} sync issue(s)' : 'No sync conflicts',
            ),
            _StatusItem(
              icon: realtime.connected ? Icons.bolt : Icons.bolt_outlined,
              label: realtime.connected ? 'Realtime active' : 'Realtime reconnecting',
            ),
            FilledButton.tonalIcon(
              onPressed: sync.isSyncing ? null : () => context.read<SyncBloc>().add(const SyncRequested()),
              icon: const Icon(Icons.sync),
              label: const Text('Sync now'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  const _StatusItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19), const SizedBox(width: 7), Text(label)]);
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({required this.title, required this.description, required this.icon, this.onTap});
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 28, color: onTap == null ? Colors.grey : Theme.of(context).colorScheme.primary),
              const Spacer(),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(description, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
