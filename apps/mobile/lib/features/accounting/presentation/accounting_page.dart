import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key});

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<AccountingWorkspaceData> _future;
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _setDates(_days);
    _reload();
  }

  void _setDates(int days) {
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(Duration(days: days));
  }

  void _reload() {
    _future = context.read<AccountingRepository>().workspace(start: _start, end: _end);
  }

  void _setRange(int days) {
    setState(() {
      _days = days;
      _setDates(days);
      _reload();
    });
  }

  String? _role(BuildContext context) {
    final state = context.watch<SessionBloc>().state;
    if (state is! SessionAuthenticated) return null;
    final tenantId = state.session.selectedTenantId;
    for (final membership in state.session.memberships) {
      if (membership.tenantId == tenantId) return membership.role;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final role = _role(context);
    final canRead = const {'owner', 'admin', 'manager', 'accountant'}.contains(role);
    if (!canRead) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Accounting reports are available to authorised management and accounting roles.'),
          ),
        ),
      );
    }

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounting'),
          actions: [
            IconButton(
              tooltip: 'Refresh accounting data',
              onPressed: () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
            const SizedBox(width: 4),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Overview', icon: Icon(Icons.dashboard_outlined)),
              Tab(text: 'Profit & Loss', icon: Icon(Icons.trending_up)),
              Tab(text: 'Trial Balance', icon: Icon(Icons.balance_outlined)),
              Tab(text: 'Journals', icon: Icon(Icons.menu_book_outlined)),
              Tab(text: 'General Ledger', icon: Icon(Icons.table_view_outlined)),
            ],
          ),
        ),
        body: FutureBuilder<AccountingWorkspaceData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return _AccountingError(
                message: _errorMessage(snapshot.error!),
                onRetry: () => setState(_reload),
              );
            }
            final data = snapshot.requireData;
            return Column(
              children: [
                _PeriodBar(
                  days: _days,
                  start: _start,
                  end: _end,
                  onChange: _setRange,
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OverviewTab(data: data),
                      _ProfitLossTab(report: data.profitLoss),
                      _TrialBalanceTab(report: data.trialBalance),
                      _JournalsTab(journals: data.journals),
                      _LedgerTab(lines: data.ledger),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.days,
    required this.start,
    required this.end,
    required this.onChange,
  });

  final int days;
  final DateTime start;
  final DateTime end;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.date_range_outlined, size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${_date(start)} – ${_date(end)}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 30, label: Text('30d')),
                ButtonSegment(value: 90, label: Text('90d')),
                ButtonSegment(value: 365, label: Text('1y')),
              ],
              selected: {days},
              onSelectionChanged: (value) => onChange(value.first),
              showSelectedIcon: false,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.data});
  final AccountingWorkspaceData data;

  @override
  Widget build(BuildContext context) {
    final pnl = data.profitLoss;
    final balance = data.balanceSheet;
    final health = data.reconciliation;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final padding = wide ? 28.0 : 16.0;
        return ListView(
          padding: EdgeInsets.all(padding),
          children: [
            _HealthCard(report: health),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: wide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: wide ? 1.75 : 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _MoneyCard('Net profit', pnl.netProfitMinor, Icons.savings_outlined),
                _MoneyCard('Gross profit', pnl.grossProfitMinor, Icons.trending_up),
                _MoneyCard('Assets', balance.assetsMinor, Icons.account_balance_wallet_outlined),
                _MoneyCard('Liabilities', balance.liabilitiesMinor, Icons.payments_outlined),
                _MoneyCard('Sales revenue', pnl.salesRevenueMinor, Icons.point_of_sale_outlined),
                _MoneyCard('Operating expenses', pnl.operatingExpensesMinor, Icons.receipt_long_outlined),
                _MoneyCard('Equity + earnings', balance.equityIncludingEarningsMinor, Icons.account_balance_outlined),
                _MoneyCard('Balance difference', balance.differenceMinor, Icons.balance_outlined),
              ],
            ),
            const SizedBox(height: 16),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _BalanceSheetCard(report: balance)),
                  const SizedBox(width: 14),
                  Expanded(child: _SettingsCard(settings: data.settings)),
                ],
              )
            else ...[
              _BalanceSheetCard(report: balance),
              const SizedBox(height: 14),
              _SettingsCard(settings: data.settings),
            ],
          ],
        );
      },
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.report});
  final ReconciliationReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final healthy = report.healthy;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  healthy ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: healthy ? KhanyaBrand.forest : scheme.error,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    healthy ? 'Accounting reconciliation is healthy' : 'Accounting reconciliation needs attention',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _HealthValue('Trial balance', report.trialBalanceDifferenceMinor),
                _HealthValue('Inventory', report.inventoryDifferenceMinor),
                _HealthValue('Stock in transit', report.stockInTransitDifferenceMinor),
                _HealthValue('Accounts payable', report.accountsPayableDifferenceMinor),
                _HealthValue('Supplier advances', report.supplierAdvancesDifferenceMinor),
                _HealthText('Missing journals', '${report.missingJournalCount}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthValue extends StatelessWidget {
  const _HealthValue(this.label, this.valueMinor);
  final String label;
  final int valueMinor;

  @override
  Widget build(BuildContext context) => _HealthText(label, Loti.formatMinor(valueMinor));
}

class _HealthText extends StatelessWidget {
  const _HealthText(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 170,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _MoneyCard extends StatelessWidget {
  const _MoneyCard(this.label, this.valueMinor, this.icon);
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

class _BalanceSheetCard extends StatelessWidget {
  const _BalanceSheetCard({required this.report});
  final BalanceSheetReport report;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Balance sheet snapshot', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _ValueRow('Assets', report.assetsMinor),
            _ValueRow('Liabilities', report.liabilitiesMinor),
            _ValueRow('Equity', report.equityMinor),
            _ValueRow('Current earnings', report.currentEarningsMinor),
            const Divider(),
            _ValueRow('Liabilities + equity', report.liabilitiesAndEquityMinor, bold: true),
            _ValueRow('Difference', report.differenceMinor, bold: true),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.settings});
  final AccountingSettings settings;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Accounting controls', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.currency_exchange),
              title: const Text('Base currency'),
              trailing: Text(settings.baseCurrency, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Fiscal year starts'),
              trailing: Text(_month(settings.fiscalYearStartMonth), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_clock_outlined),
              title: const Text('Period lock'),
              subtitle: settings.lockReason == null ? null : Text(settings.lockReason!),
              trailing: Text(
                settings.lockedThrough == null ? 'Not locked' : 'Through ${_date(settings.lockedThrough!)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ListView(
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _SummaryTile('Sales revenue', report.salesRevenueMinor),
                _SummaryTile('Cost of sales', report.costOfSalesMinor),
                _SummaryTile('Gross profit', report.grossProfitMinor),
                _SummaryTile('Other income', report.otherIncomeMinor),
                _SummaryTile('Operating expenses', report.operatingExpensesMinor),
                _SummaryTile('Net profit', report.netProfitMinor, emphasized: true),
              ],
            ),
            const SizedBox(height: 18),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Code')),
                    DataColumn(label: Text('Account')),
                    DataColumn(label: Text('Group')),
                    DataColumn(label: Text('Amount'), numeric: true),
                  ],
                  rows: report.accounts
                      .map(
                        (account) => DataRow(cells: [
                          DataCell(Text(account.code)),
                          DataCell(SizedBox(width: 280, child: Text(account.name))),
                          DataCell(Text(_label(account.reportGroup))),
                          DataCell(Text(Loti.formatMinor(account.amountMinor))),
                        ]),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile(this.label, this.valueMinor, {this.emphasized = false});
  final String label;
  final int valueMinor;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 235,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 8),
              Text(
                Loti.formatMinor(valueMinor),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: emphasized ? KhanyaBrand.forest : null,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab({required this.report});
  final TrialBalanceReport report;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _HealthText('Total debits', Loti.formatMinor(report.totalDebitsMinor)),
                _HealthText('Total credits', Loti.formatMinor(report.totalCreditsMinor)),
                _HealthText('Difference', Loti.formatMinor(report.differenceMinor)),
                Chip(
                  avatar: Icon(report.isBalanced ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 18),
                  label: Text(report.isBalanced ? 'Balanced' : 'Out of balance'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
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
              rows: report.accounts
                  .map(
                    (account) => DataRow(cells: [
                      DataCell(Text(account.code)),
                      DataCell(SizedBox(width: 260, child: Text(account.name))),
                      DataCell(Text(_label(account.accountType))),
                      DataCell(Text(Loti.formatMinor(account.debitsMinor))),
                      DataCell(Text(Loti.formatMinor(account.creditsMinor))),
                      DataCell(Text(Loti.formatMinor(account.balanceMinor))),
                    ]),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _JournalsTab extends StatelessWidget {
  const _JournalsTab({required this.journals});
  final List<JournalEntrySummary> journals;

  @override
  Widget build(BuildContext context) {
    if (journals.isEmpty) return const Center(child: Text('No journal entries yet.'));
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: journals.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final journal = journals[index];
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            leading: CircleAvatar(child: Text(journal.sourceType.isEmpty ? 'J' : journal.sourceType.substring(0, 1).toUpperCase())),
            title: Text('${journal.entryNumber} • ${journal.description}'),
            subtitle: Text('${_dateTime(journal.occurredAt)} • ${_label(journal.sourceType)}'),
            trailing: Text(Loti.formatMinor(journal.debitTotalMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Account')),
                    DataColumn(label: Text('Debit'), numeric: true),
                    DataColumn(label: Text('Credit'), numeric: true),
                    DataColumn(label: Text('Memo')),
                  ],
                  rows: journal.lines
                      .map(
                        (line) => DataRow(cells: [
                          DataCell(SizedBox(width: 260, child: Text('${line.accountCode} • ${line.accountName}'))),
                          DataCell(Text(Loti.formatMinor(line.debitMinor))),
                          DataCell(Text(Loti.formatMinor(line.creditMinor))),
                          DataCell(SizedBox(width: 220, child: Text(line.memo ?? ''))),
                        ]),
                      )
                      .toList(growable: false),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({required this.lines});
  final List<LedgerLine> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const Center(child: Text('No ledger activity in this period.'));
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Entry')),
                DataColumn(label: Text('Account')),
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Debit'), numeric: true),
                DataColumn(label: Text('Credit'), numeric: true),
              ],
              rows: lines
                  .map(
                    (line) => DataRow(cells: [
                      DataCell(Text(_date(line.occurredAt))),
                      DataCell(Text(line.entryNumber)),
                      DataCell(SizedBox(width: 240, child: Text('${line.accountCode} • ${line.accountName}'))),
                      DataCell(SizedBox(width: 280, child: Text(line.description))),
                      DataCell(Text(Loti.formatMinor(line.debitMinor))),
                      DataCell(Text(Loti.formatMinor(line.creditMinor))),
                    ]),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow(this.label, this.valueMinor, {this.bold = false});
  final String label;
  final int valueMinor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            Loti.formatMinor(valueMinor),
            style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AccountingError extends StatelessWidget {
  const _AccountingError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 40),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _date(DateTime value) => '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _dateTime(DateTime value) => '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _month(int month) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  if (month < 1 || month > 12) return '$month';
  return months[month - 1];
}

String _label(String value) => value.replaceAll('_', ' ').split(' ').map((part) {
      if (part.isEmpty) return part;
      return '${part[0].toUpperCase()}${part.substring(1)}';
    }).join(' ');

String _errorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] != null) return data['detail'].toString();
    if (error.response?.statusCode == 403) return 'Your role does not have access to accounting reports.';
  }
  return 'Accounting data could not be loaded. These reports require a connection to the Khanya server.';
}
