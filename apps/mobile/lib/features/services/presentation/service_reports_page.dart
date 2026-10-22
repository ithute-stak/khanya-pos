import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';

class ServiceReportsPage extends StatefulWidget {
  const ServiceReportsPage({super.key});

  @override
  State<ServiceReportsPage> createState() => _ServiceReportsPageState();
}

class _ServiceReportsPageState extends State<ServiceReportsPage> {
  late Future<Map<String, dynamic>> report;
  @override
  void initState() { super.initState(); _reload(); }
  void _reload() {
    final end = DateTime.now();
    report = context.read<ReportsRepository>().serviceSummary(
      start: end.subtract(const Duration(days: 30)), end: end,
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Service revenue'), actions: [
      IconButton(onPressed: () => setState(_reload), icon: const Icon(Icons.refresh)),
    ]),
    body: FutureBuilder<Map<String, dynamic>>(
      future: report,
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Could not load report: ${snapshot.error}'));
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final data = snapshot.data!;
        final items = (data['services'] as List<dynamic>? ?? []);
        return ListView(padding: const EdgeInsets.all(18), children: [
          Text('Last 30 days', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Card(child: ListTile(title: const Text('Gross service revenue'),
            trailing: Text('M ${data['gross_revenue']}'))),
          Card(child: ListTile(title: const Text('Service sales'),
            trailing: Text('${data['sale_count']}'))),
          Card(child: ListTile(title: const Text('Outstanding balances'),
            trailing: Text('M ${data['outstanding']}'))),
          const SizedBox(height: 16),
          Text('Revenue by service', style: Theme.of(context).textTheme.titleMedium),
          for (final raw in items)
            ListTile(
              title: Text((raw as Map)['name']?.toString() ?? 'Service'),
              subtitle: Text('Quantity: ${raw['quantity']}'),
              trailing: Text('M ${raw['revenue']}'),
            ),
          const SizedBox(height: 12),
          const Text('Revenue before returns and costs. This is not a profitability report.'),
        ]);
      },
    ),
  );
}
