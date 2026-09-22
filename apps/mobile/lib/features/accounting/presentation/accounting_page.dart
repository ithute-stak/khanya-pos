import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_reports.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key});

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<AccountingSnapshot> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = DateTime(now.year, now.month, 1);
    _reload();
  }

  void _reload() {
    _future = context.read<AccountingRepository>().snapshot(start: _start, end: _end);
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: _end,
    );
    if (value == null) return;
    setState(() {
      _start = DateTime(value.year, value.month, value.day);
      _reload();
    });
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (value == null) return;
    setState(() {
      _end = DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
      _reload();
    });
  }

  void _monthToDate() {
    final now = DateTime.now();
    setState(() {
      _start = DateTime(now.year, now.month, 1);
      _end = now;
      _reload();
    });
  }

  void _yearToDate() {
    final now = DateTime.now();
    setState(() {
      _start = DateTime(now.year, 1, 1);
      _end = now;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounting'),
          actions: [
            IconButton(
              tooltip: 'Refresh accounting reports',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Profit & Loss'),
              Tab(text: 'Balance Sheet'),
              Tab(text: 'Trial Balance'),
              Tab(text: 'General Ledger'),
              Tab(text: 'Journals'),
            ],
          ),
        ),
        body: Column(
          children: [
            _PeriodBar(
              start: _start,
              end: _end,
              onStart: _pickStart,
              onEnd: _pickEnd,
              onMonthToDate: _monthToDate,
              onYearToDate: _yearToDate,
            ),
            Expanded(
              child: FutureBuilder<AccountingSnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _ErrorView(onRetry: () => setState(_reload));
                  }
                  final data = snapshot.requireData;
                  return TabBarView(
                    children: [
                      _OverviewTab(data: data),
                      _ProfitLossTab(report: data.profitLoss),
                      _BalanceSheetTab(report: data.balanceSheet),
                      _TrialBalanceTab(report: data.trialBalance),
                      _LedgerTab(rows: data.ledger),
                      _JournalsTab(items: data.journals),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.start,
    required this.end,
    required this.onStart,
    required this.onEnd,
    required this.onMonthToDate,
    required this.onYearToDate,
  });

  final DateTime start;
  final DateTime end;
  final VoidCallback onStart;
  final VoidCallback onEnd;
  final VoidCallback onMonthToDate;
  final VoidCallback onYearToDate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('From ${_date(start)}'),
            ),
            OutlinedButton.icon(
              onPressed: onEnd,
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text('To ${_date(end)}'),
            ),
            TextButton(onPressed: onMonthToDate, child: const Text('Month to date')),
            TextButton(onPressed: onYearToDate, child: const Text('Year to date')),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.data});

  final AccountingSnapshot data;

  @override
  Widget build(BuildContext context) {
    final pnl = data.profitLoss;
    final balance = data.balanceSheet;
    final reconciliation = data.reconciliation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ListView(
          padding: EdgeInsets.all(wide ? 24 : 16),
          children: [
            _AccountingStatusCard(reconciliation: reconciliation),
            const SizedBox(height: 14),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: wide ? 4 : 2,
              childAspectRatio: wide ? 1.75 : 1.25,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _MetricCard('Sales revenue', pnl.salesRevenueMinor, Icons.trending_up_outlined),
                _MetricCard('Gross profit', pnl.grossProfitMinor, Icons.savings_outlined),
                _MetricCard('Net profit', pnl.netProfitMinor, Icons.assessment_outlined),
                _MetricCard('Operating expenses', pnl.operatingExpensesMinor, Icons.payments_outlined),
                _MetricCard('Assets', balance.assetsMinor, Icons.account_balance_wallet_outlined),
                _MetricCard('Liabilities', balance.liabilitiesMinor, Icons.request_quote_outlined),
                _MetricCard('Equity + earnings', balance.equityIncludingCurrentEarningsMinor, Icons.account_balance_outlined),
                _MetricCard('Current earnings', balance.currentEarningsMinor, Icons.show_chart_outlined),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AccountingStatusCard extends StatelessWidget {
  const _AccountingStatusCard({required this.reconciliation});

  final LedgerReconciliation reconciliation;

  @override
  Widget build(BuildContext context) {
    final healthy = reconciliation.healthy;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: healthy ? scheme.primaryContainer : scheme.errorContainer,
                  child: Icon(healthy ? Icons.verified_outlined : Icons.warning_amber_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        healthy ? 'Ledger reconciliation healthy' : 'Ledger reconciliation needs attention',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        healthy
                            ? 'Trial balance and core subledgers reconcile.'
                            : 'Review the differences and missing source journals below.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                _StatusValue('Trial balance', reconciliation.trialBalanceDifferenceMinor),
                _StatusValue('Inventory', reconciliation.inventoryDifferenceMinor),
                _StatusValue('Stock in transit', reconciliation.transitDifferenceMinor),
                _StatusValue('Accounts payable', reconciliation.accountsPayableDifferenceMinor),
                _StatusValue('Supplier advances', reconciliation.supplierAdvancesDifferenceMinor),
                Text('Missing journals: ${reconciliation.missingSaleJournals + reconciliation.missingPurchaseJournals + reconciliation.missingExpenseJournals}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusValue extends StatelessWidget {
  const _StatusValue(this.label, this.valueMinor);

  final String label;
  final int valueMinor;

  @override
  Widget build(BuildContext context) => Text('$label: ${Loti.formatMinor(valueMinor)}');
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.valueMinor, this.icon);

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
            Text(
              Loti.formatMinor(valueMinor),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ProfitLossTab extends StatelessWidget {
  const _ProfitLossTab({required this.report});

  final ProfitLossReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportHeader(title: 'Profit & Loss', balanced: null),
        const SizedBox(height: 10),
        _AmountRow('Sales revenue', report.salesRevenueMinor, emphasized: true),
        _AmountRow('Other income', report.otherIncomeMinor),
        _AmountRow('Cost of sales', -report.costOfSalesMinor),
        _AmountRow('Gross profit', report.grossProfitMinor, emphasized: true),
        _AmountRow('Operating expenses', -report.operatingExpensesMinor),
        const Divider(height: 24),
        _AmountRow('Net profit / (loss)', report.netProfitMinor, emphasized: true),
        const SizedBox(height: 18),
        Text('Account detail', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final account in report.accounts)
          ListTile(
            dense: true,
            title: Text('${account.code}  ${account.name}'),
            subtitle: Text(_groupLabel(account.reportGroup)),
            trailing: Text(Loti.formatMinor(account.amountMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

class _BalanceSheetTab extends StatelessWidget {
  const _BalanceSheetTab({required this.report});

  final BalanceSheetReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportHeader(title: 'Balance Sheet', balanced: report.isBalanced),
        const SizedBox(height: 12),
        _AmountRow('Total assets', report.assetsMinor, emphasized: true),
        const SizedBox(height: 8),
        _AmountRow('Liabilities', report.liabilitiesMinor),
        _AmountRow('Equity before current earnings', report.equityMinor),
        _AmountRow('Current earnings', report.currentEarningsMinor),
        const Divider(height: 24),
        _AmountRow('Equity including current earnings', report.equityIncludingCurrentEarningsMinor, emphasized: true),
        _AmountRow('Liabilities + equity', report.liabilitiesAndEquityMinor, emphasized: true),
        const Divider(height: 24),
        _AmountRow('Balance sheet difference', report.differenceMinor),
      ],
    );
  }
}

class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab({required this.report});

  final TrialBalanceReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ReportHeader(title: 'Trial Balance', balanced: report.isBalanced),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Code')),
              DataColumn(label: Text('Account')),
              DataColumn(label: Text('Type')),
              DataColumn(label: Text('Debits'), numeric: true),
              DataColumn(label: Text('Credits'), numeric: true),
              DataColumn(label: Text('Balance'), numeric: true),
            ],
            rows: [
              for (final row in report.accounts)
                DataRow(
                  cells: [
                    DataCell(Text(row.code)),
                    DataCell(Text(row.name)),
                    DataCell(Text(row.accountType)),
                    DataCell(Text(Loti.formatMinor(row.debitsMinor))),
                    DataCell(Text(Loti.formatMinor(row.creditsMinor))),
                    DataCell(Text(Loti.formatMinor(row.balanceMinor))),
                  ],
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        _AmountRow('Total debits', report.totalDebitsMinor, emphasized: true),
        _AmountRow('Total credits', report.totalCreditsMinor, emphasized: true),
        _AmountRow('Difference', report.differenceMinor),
      ],
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.rows});

  final List<LedgerRow> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const Center(child: Text('No ledger activity in this period.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.menu_book_outlined)),
            title: Text('${row.accountCode}  ${row.accountName}'),
            subtitle: Text('${row.entryNumber} • ${_date(row.occurredAt)} • ${row.description}'),
            trailing: SizedBox(
              width: 190,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (row.debitMinor != 0) Text('Dr ${Loti.formatMinor(row.debitMinor)}'),
                  if (row.creditMinor != 0) Text('Cr ${Loti.formatMinor(row.creditMinor)}'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JournalsTab extends StatelessWidget {
  const _JournalsTab({required this.items});

  final List<JournalSummary> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Center(child: Text('No journal entries have been posted yet.'));
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ExpansionTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(item.entryNumber),
            subtitle: Text('${_date(item.occurredAt)} • ${_sourceLabel(item.sourceType)} • ${item.description}'),
            trailing: Text(Loti.formatMinor(item.totalDebitsMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
            children: [
              for (final line in item.lines)
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                  title: Text('${line.accountCode}  ${line.accountName}'),
                  subtitle: line.memo == null ? null : Text(line.memo!),
                  trailing: Text(
                    line.debitMinor > 0
                        ? 'Dr ${Loti.formatMinor(line.debitMinor)}'
                        : 'Cr ${Loti.formatMinor(line.creditMinor)}',
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.title, required this.balanced});

  final String title;
  final bool? balanced;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
        if (balanced != null)
          Chip(
            avatar: Icon(balanced! ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18),
            label: Text(balanced! ? 'Balanced' : 'Out of balance'),
          ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow(this.label, this.valueMinor, {this.emphasized = false});

  final String label;
  final int valueMinor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(Loti.formatMinor(valueMinor), style: style),
        ],
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
            const Text('Could not load accounting data. Check the connection and your accounting permissions.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _groupLabel(String value) => switch (value) {
      'revenue' => 'Sales revenue',
      'other_income' => 'Other income',
      'cost_of_sales' => 'Cost of sales',
      'operating_expense' => 'Operating expense',
      _ => value.replaceAll('_', ' '),
    };

String _sourceLabel(String value) => value.replaceAll('_', ' ');
