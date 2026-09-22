import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';
import 'package:khanya_pos/features/reports/domain/sales_summary_report.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<SalesSummaryReport> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 30));
    _reload();
  }

  void _reload() {
    _future = context.read<ReportsRepository>().salesSummary(start: _start, end: _end);
  }

  void _setRange(Duration duration) {
    final now = DateTime.now();
    setState(() {
      _end = now;
      _start = now.subtract(duration);
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Management Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<SalesSummaryReport>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(onRetry: () => setState(_reload));
          }
          final report = snapshot.requireData;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;
              final padding = wide ? 28.0 : 16.0;
              return ListView(
                padding: EdgeInsets.all(padding),
                children: [
                  _Header(
                    start: _start,
                    end: _end,
                    on7Days: () => _setRange(const Duration(days: 7)),
                    on30Days: () => _setRange(const Duration(days: 30)),
                    on90Days: () => _setRange(const Duration(days: 90)),
                  ),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: wide ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: wide ? 1.8 : 1.35,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _MetricCard('Net sales', Loti.formatMinor(report.netSalesMinor), Icons.trending_up),
                      _MetricCard('Gross profit', Loti.formatMinor(report.grossProfitMinor), Icons.savings_outlined),
                      _MetricCard('Transactions', '${report.saleCount}', Icons.receipt_long_outlined),
                      _MetricCard('Returns', Loti.formatMinor(report.returnsTotalMinor), Icons.assignment_return_outlined),
                      _MetricCard('Gross sales', Loti.formatMinor(report.grossSalesMinor), Icons.point_of_sale_outlined),
                      _MetricCard('COGS', Loti.formatMinor(report.costOfGoodsMinor), Icons.inventory_2_outlined),
                      _MetricCard('Tax', Loti.formatMinor(report.taxTotalMinor), Icons.account_balance_outlined),
                      _MetricCard('Credit outstanding', Loti.formatMinor(report.balanceDueMinor), Icons.credit_score_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _PaymentsCard(report.payments)),
                        const SizedBox(width: 14),
                        Expanded(child: _TopProductsCard(report.topProducts)),
                      ],
                    )
                  else ...[
                    _PaymentsCard(report.payments),
                    const SizedBox(height: 14),
                    _TopProductsCard(report.topProducts),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.start,
    required this.end,
    required this.on7Days,
    required this.on30Days,
    required this.on90Days,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback on7Days;
  final VoidCallback on30Days;
  final VoidCallback on90Days;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(Icons.analytics_outlined, color: KhanyaBrand.forest),
            Text(
              '${_date(start)} – ${_date(end)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: on7Days, child: const Text('7 days')),
            OutlinedButton(onPressed: on30Days, child: const Text('30 days')),
            OutlinedButton(onPressed: on90Days, child: const Text('90 days')),
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);

  final String label;
  final String value;
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
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard(this.items);
  final List<PaymentSummary> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Payment mix', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('No payments in this period.')
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_paymentLabel(item.method)),
                  trailing: Text(Loti.formatMinor(item.amountMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
          ],
        ),
      ),
    );
  }
}

class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard(this.items);
  final List<TopProductSummary> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Top products', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              const Text('No product sales in this period.')
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.name),
                  subtitle: Text('${item.sku} • Qty ${ScaledDecimal.fromMilli(item.quantityMilli)}'),
                  trailing: Text(Loti.formatMinor(item.revenueMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
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
            const Icon(Icons.cloud_off_outlined, size: 44),
            const SizedBox(height: 12),
            const Text('Could not load management reports. Check the connection and try again.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _paymentLabel(String method) => switch (method) {
      'cash' => 'Cash',
      'card' => 'Card',
      'mobile_money' => 'Mobile money',
      'bank_transfer' => 'Bank transfer',
      _ => method,
    };
