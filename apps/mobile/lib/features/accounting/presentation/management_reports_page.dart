import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class ManagementReportsPage extends StatefulWidget {
  const ManagementReportsPage({super.key});

  @override
  State<ManagementReportsPage> createState() => _ManagementReportsPageState();
}

class _ManagementReportsPageState extends State<ManagementReportsPage> {
  int _days = 30;
  late Future<AccountingWorkspaceData> _future;

  DateTime get _end => DateTime.now();
  DateTime get _start => _end.subtract(Duration(days: _days));

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<AccountingRepository>().workspace(start: _start, end: _end);
  }

  String? _role() {
    final state = context.read<SessionBloc>().state;
    if (state is! SessionAuthenticated) return null;
    final tenantId = state.session.selectedTenantId;
    for (final membership in state.session.memberships) {
      if (membership.tenantId == tenantId) return membership.role;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final allowed = const {'owner', 'admin', 'manager', 'accountant'}.contains(_role());
    if (!allowed) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Management reports are available to authorised management and accounting roles.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Management Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh management reports',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _RangeBar(
            days: _days,
            onChanged: (days) {
              setState(() {
                _days = days;
                _reload();
              });
            },
          ),
          Expanded(
            child: FutureBuilder<AccountingWorkspaceData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(onRetry: () => setState(_reload));
                }
                return _ManagementBody(data: snapshot.requireData);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined, size: 19),
            const SizedBox(width: 8),
            const Expanded(child: Text('Management reporting period')),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30d')),
                ButtonSegment(value: 90, label: Text('90d')),
                ButtonSegment(value: 365, label: Text('1y')),
              ],
              selected: {days},
              onSelectionChanged: (values) => onChanged(values.first),
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagementBody extends StatelessWidget {
  const _ManagementBody({required this.data});

  final AccountingWorkspaceData data;

  @override
  Widget build(BuildContext context) {
    final report = data.managementSummary;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        _Hero(report: report),
        const SizedBox(height: 16),
        Text('Liquidity & working capital', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: wide ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: wide ? 1.55 : 1.18,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _Metric('Liquid funds', report.liquidFundsMinor, Icons.account_balance_wallet_outlined),
            _Metric('Receivables', report.accountsReceivableMinor, Icons.request_quote_outlined),
            _Metric('Inventory', report.inventoryMinor, Icons.inventory_2_outlined),
            _Metric('Payables', report.accountsPayableMinor, Icons.payments_outlined),
            _Metric('Working capital', report.workingCapitalMinor, Icons.swap_horiz_outlined),
            _Metric('Supplier advances', report.supplierAdvancesMinor, Icons.local_shipping_outlined),
            _Metric('Cash on hand', report.cashOnHandMinor, Icons.money_outlined),
            _Metric('Bank + electronic funds', report.bankMinor + report.cashEquivalentsMinor, Icons.account_balance_outlined),
          ],
        ),
        const SizedBox(height: 18),
        Text('Performance', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: wide ? 3 : 1,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: wide ? 1.8 : 2.3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _Metric('Sales revenue', report.salesRevenueMinor, Icons.point_of_sale_outlined),
            _Metric('Gross profit', report.grossProfitMinor, Icons.trending_up_outlined),
            _Metric('Net profit / (loss)', report.netProfitMinor, Icons.savings_outlined),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  report.ledgerHealthy ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: report.ledgerHealthy ? KhanyaBrand.forest : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data integrity', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        report.ledgerHealthy
                            ? 'The management snapshot is backed by a balanced ledger and reconciled core inventory/payables subledgers.'
                            : 'The accounting reconciliation needs attention. Review the Accounting workspace before relying on these figures for formal decisions.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.report});

  final ManagementSummary report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [KhanyaBrand.forestDark, KhanyaBrand.forest]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          const Icon(Icons.insights_outlined, size: 42, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Management Financial Snapshot',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  'Liquidity ${Loti.formatMinor(report.liquidFundsMinor)} • Working capital ${Loti.formatMinor(report.workingCapitalMinor)}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.valueMinor, this.icon);

  final String label;
  final int valueMinor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: KhanyaBrand.forest),
            const Spacer(),
            Text(Loti.formatMinor(valueMinor), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            const Text('Could not load management reports. Check the connection and your accounting permissions.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
