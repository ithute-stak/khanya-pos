import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';

class CustomerStatementPage extends StatefulWidget {
  const CustomerStatementPage({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerStatementPage> createState() => _CustomerStatementPageState();
}

class _CustomerStatementPageState extends State<CustomerStatementPage> {
  late Future<CustomerStatement> _future;

  @override
  void initState() {
    super.initState();
    _future = context.read<CustomerRepository>().getStatement(widget.customerId);
  }

  void _reload() {
    setState(() {
      _future = context.read<CustomerRepository>().getStatement(widget.customerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Statement'),
        actions: [
          IconButton(
            tooltip: 'Refresh statement',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<CustomerStatement>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 48),
                    const SizedBox(height: 12),
                    const Text('A full statement requires a live connection.'),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }
          return _StatementView(statement: snapshot.data!);
        },
      ),
    );
  }
}

class _StatementView extends StatelessWidget {
  const _StatementView({required this.statement});

  final CustomerStatement statement;

  @override
  Widget build(BuildContext context) {
    final entries = <_StatementEntry>[
      for (final sale in statement.sales)
        _StatementEntry(
          occurredAt: sale.completedAt,
          title: sale.saleNumber,
          subtitle: 'Sale${sale.dueAt == null ? '' : ' • due ${_date(sale.dueAt!)}'}',
          debitMinor: sale.totalMinor,
          creditMinor: 0,
          icon: Icons.point_of_sale_outlined,
        ),
      for (final payment in statement.payments)
        _StatementEntry(
          occurredAt: payment.receivedAt,
          title: payment.reference?.trim().isNotEmpty == true ? payment.reference! : 'Customer payment',
          subtitle: _paymentLabel(payment.method),
          debitMinor: 0,
          creditMinor: payment.amountMinor,
          icon: Icons.payments_outlined,
        ),
    ]..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    var runningBalance = 0;
    final rows = <_StatementRow>[];
    for (final entry in entries) {
      runningBalance += entry.debitMinor - entry.creditMinor;
      rows.add(_StatementRow(entry: entry, balanceMinor: runningBalance));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 22,
              runSpacing: 14,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statement.customer.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text(statement.customer.code),
                      if (statement.customer.phone != null) Text(statement.customer.phone!),
                    ],
                  ),
                ),
                _SummaryMetric(label: 'Outstanding', value: Loti.formatMinor(statement.outstandingMinor)),
                _SummaryMetric(
                  label: 'Unallocated advance',
                  value: Loti.formatMinor(statement.unallocatedAdvanceMinor),
                ),
                _SummaryMetric(label: 'Net position', value: Loti.formatMinor(statement.netPositionMinor)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Statement activity',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No sales or customer payments have been recorded yet.'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 820) {
                return _StatementTable(rows: rows);
              }
              return Column(
                children: [
                  for (final row in rows) _StatementMobileCard(row: row),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 3),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _StatementTable extends StatelessWidget {
  const _StatementTable({required this.rows});

  final List<_StatementRow> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Description')),
            DataColumn(label: Text('Debit')),
            DataColumn(label: Text('Credit')),
            DataColumn(label: Text('Running balance')),
          ],
          rows: [
            for (final row in rows)
              DataRow(
                cells: [
                  DataCell(Text(_date(row.entry.occurredAt))),
                  DataCell(
                    SizedBox(
                      width: 300,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(row.entry.subtitle, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  DataCell(Text(row.entry.debitMinor == 0 ? '—' : Loti.formatMinor(row.entry.debitMinor))),
                  DataCell(Text(row.entry.creditMinor == 0 ? '—' : Loti.formatMinor(row.entry.creditMinor))),
                  DataCell(Text(Loti.formatMinor(row.balanceMinor))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatementMobileCard extends StatelessWidget {
  const _StatementMobileCard({required this.row});

  final _StatementRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Icon(row.entry.icon, size: 20)),
        title: Text(row.entry.title),
        subtitle: Text('${_date(row.entry.occurredAt)} • ${row.entry.subtitle}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              row.entry.debitMinor > 0
                  ? '+${Loti.formatMinor(row.entry.debitMinor)}'
                  : '-${Loti.formatMinor(row.entry.creditMinor)}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text('Bal ${Loti.formatMinor(row.balanceMinor)}'),
          ],
        ),
      ),
    );
  }
}

class _StatementEntry {
  const _StatementEntry({
    required this.occurredAt,
    required this.title,
    required this.subtitle,
    required this.debitMinor,
    required this.creditMinor,
    required this.icon,
  });

  final DateTime occurredAt;
  final String title;
  final String subtitle;
  final int debitMinor;
  final int creditMinor;
  final IconData icon;
}

class _StatementRow {
  const _StatementRow({required this.entry, required this.balanceMinor});

  final _StatementEntry entry;
  final int balanceMinor;
}

String _paymentLabel(String method) => switch (method) {
      'cash' => 'Cash receipt',
      'card' => 'Card receipt',
      'mobile_money' => 'Mobile money receipt',
      'bank_transfer' => 'Bank transfer receipt',
      _ => 'Customer receipt',
    };

String _date(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
