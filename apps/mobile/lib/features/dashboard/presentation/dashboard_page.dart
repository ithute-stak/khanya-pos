import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
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
        title: const KhanyaBrandTitle(compact: true),
        actions: [
          BlocBuilder<ConnectivityBloc, ConnectivityState>(
            builder: (context, state) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                avatar: Icon(
                  state.isNetworkAvailable ? Icons.cloud_done : Icons.cloud_off,
                  size: 17,
                  color: state.isNetworkAvailable ? KhanyaBrand.forest : Colors.orange.shade800,
                ),
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
                      _DashboardHero(
                        firstName: session?.displayName.split(' ').first,
                        businessName: membership?.tenantName,
                      ),
                      const SizedBox(height: 16),
                      const _SystemStatusCard(),
                      const SizedBox(height: 22),
                      Text(
                        'Business tools',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: KhanyaBrand.navy,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
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
                      accent: KhanyaBrand.forest,
                      onTap: () => context.push('/pos'),
                    ),
                    _ModuleCard(
                      title: 'Till & Shift',
                      description: 'Opening float, cash drawer movements and shift reconciliation',
                      icon: Icons.price_check_outlined,
                      accent: KhanyaBrand.goldDark,
                      onTap: () => context.push('/till'),
                    ),
                    _ModuleCard(
                      title: 'Customers & Credit',
                      description: 'Credit limits, balances, payments, ageing and statements',
                      icon: Icons.groups_2_outlined,
                      accent: KhanyaBrand.forest,
                      onTap: () => context.push('/customers'),
                    ),
                    _ModuleCard(
                      title: 'Products',
                      description: 'Prices, SKUs, barcodes and product catalogue',
                      icon: Icons.inventory_2_outlined,
                      accent: KhanyaBrand.navy,
                      onTap: () => context.push('/products'),
                    ),
                    _ModuleCard(
                      title: 'Inventory',
                      description: 'On-hand quantities and low-stock visibility',
                      icon: Icons.warehouse_outlined,
                      accent: KhanyaBrand.goldDark,
                      onTap: () => context.push('/inventory'),
                    ),
                    _ModuleCard(
                      title: 'Purchases',
                      description: 'Buy stock, receive items and track supplier balances',
                      icon: Icons.shopping_bag_outlined,
                      accent: KhanyaBrand.forest,
                      onTap: () => context.push('/purchases'),
                    ),
                    _ModuleCard(
                      title: 'Receipt Vault',
                      description: 'Photograph and keep shopping receipts and supplier invoices',
                      icon: Icons.receipt_long_outlined,
                      accent: KhanyaBrand.goldDark,
                      onTap: () => context.push('/receipts'),
                    ),
                    _ModuleCard(
                      title: 'Suppliers',
                      description: 'Supplier contacts, purchases and outstanding balances',
                      icon: Icons.local_shipping_outlined,
                      accent: KhanyaBrand.navy,
                      onTap: () => context.push('/suppliers'),
                    ),
                    _ModuleCard(
                      title: 'Expenses',
                      description: 'Rent, electricity, transport, fuel and daily business costs',
                      icon: Icons.account_balance_wallet_outlined,
                      accent: KhanyaBrand.forest,
                      onTap: () => context.push('/expenses'),
                    ),
                    const _ModuleCard(
                      title: 'Accounting',
                      description: 'Ledgers, reconciliation and financial reporting foundation',
                      icon: Icons.account_balance_outlined,
                      accent: KhanyaBrand.navy,
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

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({required this.firstName, required this.businessName});

  final String? firstName;
  final String? businessName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [KhanyaBrand.forestDark, KhanyaBrand.forest, Color(0xFF258A3C)],
        ),
        boxShadow: [
          BoxShadow(
            color: KhanyaBrand.forest.withValues(alpha: 0.20),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          const KhanyaMark(size: 74, radius: 18),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstName == null ? 'Welcome to Khanya POS' : 'Good day, $firstName',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  businessName ?? KhanyaBrand.companyName,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'People • Process • Profit • A Brighter Tomorrow',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFFFE7A3),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 19, color: KhanyaBrand.forest),
        const SizedBox(width: 7),
        Text(label),
      ],
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
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
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(icon, size: 25, color: onTap == null ? Colors.grey : accent),
                ),
              ),
              const Spacer(),
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
