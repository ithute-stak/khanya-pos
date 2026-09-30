import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';
import 'package:khanya_pos/features/reports/domain/business_intelligence.dart';
import 'package:khanya_pos/features/reports/domain/sales_summary_report.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportBundle {
  const _ReportBundle({
    required this.sales,
    required this.health,
    required this.stock,
    required this.suppliers,
  });

  final SalesSummaryReport sales;
  final BusinessHealthReport health;
  final StockIntelligenceReport stock;
  final SupplierIntelligenceReport suppliers;
}

class _ReportsPageState extends State<ReportsPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<_ReportBundle> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 30));
    _reload();
  }

  void _reload() {
    final repository = context.read<ReportsRepository>();
    _future = () async {
      final results = await Future.wait<Object>([
        repository.salesSummary(start: _start, end: _end),
        repository.businessHealth(start: _start, end: _end),
        repository.stockIntelligence(days: 30),
        repository.supplierIntelligence(days: 90),
      ]);
      return _ReportBundle(
        sales: results[0] as SalesSummaryReport,
        health: results[1] as BusinessHealthReport,
        stock: results[2] as StockIntelligenceReport,
        suppliers: results[3] as SupplierIntelligenceReport,
      );
    }();
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
      body: FutureBuilder<_ReportBundle>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorView(onRetry: () => setState(_reload));
          }
          final data = snapshot.requireData;
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
                  _BusinessHealthCard(data.health, wide: wide),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: wide ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: wide ? 1.8 : 1.35,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    children: [
                      _MetricCard('Net sales', Loti.formatMinor(data.sales.netSalesMinor), Icons.trending_up),
                      _MetricCard('Gross profit', Loti.formatMinor(data.sales.grossProfitMinor), Icons.savings_outlined),
                      _MetricCard('Transactions', '${data.sales.saleCount}', Icons.receipt_long_outlined),
                      _MetricCard('Returns', Loti.formatMinor(data.sales.returnsTotalMinor), Icons.assignment_return_outlined),
                      _MetricCard('Gross sales', Loti.formatMinor(data.sales.grossSalesMinor), Icons.point_of_sale_outlined),
                      _MetricCard('COGS', Loti.formatMinor(data.sales.costOfGoodsMinor), Icons.inventory_2_outlined),
                      _MetricCard('Tax', Loti.formatMinor(data.sales.taxTotalMinor), Icons.account_balance_outlined),
                      _MetricCard('Credit outstanding', Loti.formatMinor(data.sales.balanceDueMinor), Icons.credit_score_outlined),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _StockIntelligenceCard(data.stock)),
                        const SizedBox(width: 14),
                        Expanded(child: _SupplierIntelligenceCard(data.suppliers)),
                      ],
                    )
                  else ...[
                    _StockIntelligenceCard(data.stock),
                    const SizedBox(height: 14),
                    _SupplierIntelligenceCard(data.suppliers),
                  ],
                  const SizedBox(height: 20),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _PaymentsCard(data.sales.payments)),
                        const SizedBox(width: 14),
                        Expanded(child: _TopProductsCard(data.sales.topProducts)),
                      ],
                    )
                  else ...[
                    _PaymentsCard(data.sales.payments),
                    const SizedBox(height: 14),
                    _TopProductsCard(data.sales.topProducts),
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

class _BusinessHealthCard extends StatelessWidget {
  const _BusinessHealthCard(this.report, {required this.wide});

  final BusinessHealthReport report;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final growth = report.salesGrowthRate * 100;
    final margin = report.grossMarginRate * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: KhanyaBrand.forest.withValues(alpha: 0.12),
                  child: Text(
                    '${report.overallScore}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: KhanyaBrand.forest,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Business Health Score', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 3),
                      Text('${_bandLabel(report.band)} • Sales growth ${growth.toStringAsFixed(1)}% • Gross margin ${margin.toStringAsFixed(1)}%'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _ScoreChip('Sales growth', report.salesGrowthScore),
                _ScoreChip('Profitability', report.profitabilityScore),
                _ScoreChip('Stock health', report.stockHealthScore),
                _ScoreChip('Customer credit', report.customerCreditScore),
                _ScoreChip('Expense pressure', report.expensePressureScore),
                _ScoreChip('Returns control', report.returnsScore),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'The score combines sales trend, gross margin, stock pressure, customer credit exposure, expenses and returns. It is an operational indicator, not an accounting opinion.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip(this.label, this.score);
  final String label;
  final int score;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label), Text('$score/100', style: const TextStyle(fontWeight: FontWeight.w800))],
          ),
          const SizedBox(height: 5),
          LinearProgressIndicator(value: score / 100),
        ],
      ),
    );
  }
}

class _StockIntelligenceCard extends StatelessWidget {
  const _StockIntelligenceCard(this.report);
  final StockIntelligenceReport report;

  @override
  Widget build(BuildContext context) {
    final items = report.items.take(6).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stock intelligence', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('${report.lowStockCount} low • ${report.outOfStockCount} out • ${report.deadStockCount} dead stock'),
            if (report.deadStockCostValueMinor > 0) ...[
              const SizedBox(height: 4),
              Text('Dead-stock cost exposure: ${Loti.formatMinor(report.deadStockCostValueMinor)}'),
            ],
            const Divider(height: 24),
            if (items.isEmpty)
              const Text('No urgent stock risks in the current window.')
            else
              for (final item in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.isOutOfStock ? Icons.error_outline : item.isDeadStock ? Icons.hourglass_empty : Icons.inventory_2_outlined),
                  title: Text(item.name),
                  subtitle: Text(
                    item.isDeadStock
                        ? '${item.sku} • No sales in ${report.windowDays} days'
                        : '${item.sku} • ${item.daysCover == null ? 'No velocity' : '${item.daysCover!.toStringAsFixed(1)} days cover'}',
                  ),
                  trailing: item.suggestedReorderMilli > 0
                      ? Text('Order ${ScaledDecimal.fromMilli(item.suggestedReorderMilli)}', style: const TextStyle(fontWeight: FontWeight.w800))
                      : null,
                ),
          ],
        ),
      ),
    );
  }
}

class _SupplierIntelligenceCard extends StatelessWidget {
  const _SupplierIntelligenceCard(this.report);
  final SupplierIntelligenceReport report;

  @override
  Widget build(BuildContext context) {
    final suppliers = report.suppliers.take(6).toList(growable: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Supplier intelligence', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('90-day spend ${Loti.formatMinor(report.purchaseTotalMinor)} • Outstanding ${Loti.formatMinor(report.outstandingTotalMinor)}'),
            const Divider(height: 24),
            if (suppliers.isEmpty)
              const Text('No supplier activity in this period.')
            else
              for (final supplier in suppliers)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(supplier.name),
                  subtitle: Text('${supplier.purchaseCount} purchases • ${Loti.formatMinor(supplier.purchaseTotalMinor)}'),
                  trailing: supplier.outstandingMinor > 0
                      ? Text('Due ${Loti.formatMinor(supplier.outstandingMinor)}', style: const TextStyle(fontWeight: FontWeight.w800))
                      : const Text('Paid'),
                ),
          ],
        ),
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

String _bandLabel(String band) => switch (band) {
      'strong' => 'Strong',
      'healthy' => 'Healthy',
      'watch' => 'Needs attention',
      'at_risk' => 'At risk',
      _ => band,
    };

String _paymentLabel(String method) => switch (method) {
      'cash' => 'Cash',
      'card' => 'Card',
      'mobile_money' => 'Mobile money',
      'bank_transfer' => 'Bank transfer',
      _ => method,
    };
