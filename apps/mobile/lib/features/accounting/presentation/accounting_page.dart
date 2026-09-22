import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';

class AccountingPage extends StatefulWidget {
  const AccountingPage({super.key});

  @override
  State<AccountingPage> createState() => _AccountingPageState();
}

class _AccountingPageState extends State<AccountingPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<_AccountingViewData> _future;
  String? _ledgerAccountCode;

  AccountingRepository get _repository => context.read<AccountingRepository>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 30));
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_AccountingViewData> _load() async {
    final results = await Future.wait<Object>([
      _repository.settings(),
      _repository.reconciliation(),
      _repository.profitLoss(start: _start, end: _end),
      _repository.balanceSheet(asOf: _end),
      _repository.trialBalance(asOf: _end),
      _repository.journals(limit: 100),
      _repository.accounts(),
      _repository.ledger(start: _start, end: _end),
    ]);
    return _AccountingViewData(
      settings: results[0] as AccountingSettings,
      reconciliation: results[1] as ReconciliationReport,
      profitLoss: results[2] as ProfitLossReport,
      balanceSheet: results[3] as BalanceSheetReport,
      trialBalance: results[4] as TrialBalanceReport,
      journals: results[5] as List<JournalSummary>,
      accounts: results[6] as List<AccountingAccount>,
      ledger: results[7] as List<LedgerRow>,
    );
  }

  void _setRange(Duration duration) {
    final now = DateTime.now();
    setState(() {
      _end = now;
      _start = now.subtract(duration);
      _ledgerAccountCode = null;
      _reload();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Accounting Centre'),
          actions: [
            IconButton(
              tooltip: 'Refresh accounting',
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
              Tab(text: 'Chart of Accounts'),
            ],
          ),
        ),
        body: FutureBuilder<_AccountingViewData>(
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
                _OverviewTab(
                  data: data,
                  start: _start,
                  end: _end,
                  on30Days: () => _setRange(const Duration(days: 30)),
                  on90Days: () => _setRange(const Duration(days: 90)),
                  on365Days: () => _setRange(const Duration(days: 365)),
                ),
                _ProfitLossTab(report: data.profitLoss, start: _start, end: _end),
                _BalanceSheetTab(report: data.balanceSheet, asOf: _end),
                _TrialBalanceTab(report: data.trialBalance, asOf: _end),
                _LedgerTab(
                  rows: data.ledger,
                  accounts: data.accounts,
                  selectedAccountCode: _ledgerAccountCode,
                  start: _start,
                  end: _end,
                  onAccountChanged: (value) => setState(() => _ledgerAccountCode = value),
                ),
                _JournalsTab(journals: data.journals),
                _AccountsTab(accounts: data.accounts),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AccountingViewData {
  const _AccountingViewData({
    required this.settings,
    required this.reconciliation,
    required this.profitLoss,
    required this.balanceSheet,
    required this.trialBalance,
    required this.journals,
    required this.accounts,
    required this.ledger,
  });

  final AccountingSettings settings;
  final ReconciliationReport reconciliation;
  final ProfitLossReport profitLoss;
  final BalanceSheetReport balanceSheet;
  final TrialBalanceReport trialBalance;
  final List<JournalSummary> journals;
  final List<AccountingAccount> accounts;
  final List<LedgerRow> ledger;
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.start,
    required this.end,
    required this.on30Days,
    required this.on90Days,
    required this.on365Days,
  });

  final _AccountingViewData data;
  final DateTime start;
  final DateTime end;
  final VoidCallback on30Days;
  final VoidCallback on90Days;
  final VoidCallback on365Days;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ListView(
          padding: EdgeInsets.all(wide ? 28 : 16),
          children: [
            _AccountingHero(
              healthy: data.reconciliation.healthy,
              start: start,
              end: end,
              currency: data.settings.baseCurrency,
              on30Days: on30Days,
              on90Days: on90Days,
              on365Days: on365Days,
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: wide ? 4 : 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: wide ? 1.75 : 1.3,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                _MetricCard('Net profit', data.profitLoss.netProfitMinor, Icons.account_balance_wallet_outlined),
                _MetricCard('Gross profit', data.profitLoss.grossProfitMinor, Icons.trending_up),
                _MetricCard('Total assets', data.balanceSheet.assetsMinor, Icons.account_balance_outlined),
                _MetricCard('Liabilities', data.balanceSheet.liabilitiesMinor, Icons.receipt_long_outlined),
                _MetricCard('Sales revenue', data.profitLoss.salesRevenueMinor, Icons.point_of_sale_outlined),
                _MetricCard('Cost of sales', data.profitLoss.costOfSalesMinor, Icons.inventory_2_outlined),
                _MetricCard('Operating expenses', data.profitLoss.operatingExpensesMinor, Icons.payments_outlined),
                _MetricCard('Equity + earnings', data.balanceSheet.equityIncludingEarningsMinor, Icons.savings_outlined),
              ],
            ),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _ReconciliationCard(report: data.reconciliation)),
                  const SizedBox(width: 14),
                  Expanded(child: _AccountingControlsCard(settings: data.settings)),
                ],
              )
            else ...[
              _ReconciliationCard(report: data.reconciliation),
              const SizedBox(height: 14),
              _AccountingControlsCard(settings: data.settings),
            ],
          ],
        );
      },
    );
  }
}

class _AccountingHero extends StatelessWidget {
  const _AccountingHero({
    required this.healthy,
    required this.start,
    required this.end,
    required this.currency,
    required this.on30Days,
    required this.on90Days,
    required this.on365Days,
  });

  final bool healthy;
  final DateTime start;
  final DateTime end;
  final String currency;
  final VoidCallback on30Days;
  final VoidCallback on90Days;
  final VoidCallback on365Days;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [KhanyaBrand.forestDark, KhanyaBrand.forest]),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 14,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.account_balance_outlined, color: Colors.white, size: 44),
          SizedBox(
            width: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Financial control centre',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${_date(start)} – ${_date(end)}  •  $currency  •  ${healthy ? 'Ledger reconciled' : 'Reconciliation attention required'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          OutlinedButton(onPressed: on30Days, style: _heroButtonStyle(), child: const Text('30 days')),
          OutlinedButton(onPressed: on90Days, style: _heroButtonStyle(), child: const Text('90 days')),
          OutlinedButton(onPressed: on365Days, style: _heroButtonStyle(), child: const Text('12 months')),
        ],
      ),
    );
  }

  ButtonStyle _heroButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
      );
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
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Loti.formatMinor(valueMinor),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ReconciliationCard extends StatelessWidget {
  const _ReconciliationCard({required this.report});
  final ReconciliationReport report;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(report.healthy ? Icons.verified_outlined : Icons.warning_amber_rounded,
                    color: report.healthy ? KhanyaBrand.forest : scheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    report.healthy ? 'Ledger health: reconciled' : 'Ledger health: attention required',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _CheckRow('Trial balance difference', report.trialBalanceDifferenceMinor),
            _CheckRow('Inventory vs GL', report.inventoryDifferenceMinor),
            _CheckRow('Stock in transit vs GL', report.stockInTransitDifferenceMinor),
            _CheckRow('Accounts payable vs GL', report.accountsPayableDifferenceMinor),
            _CheckRow('Supplier advances vs GL', report.supplierAdvancesDifferenceMinor),
            const Divider(height: 24),
            Text(
              'Missing source journals: sales ${report.missingSaleJournals}, purchases ${report.missingPurchaseJournals}, expenses ${report.missingExpenseJournals}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow(this.label, this.differenceMinor);
  final String label;
  final int differenceMinor;

  @override
  Widget build(BuildContext context) {
    final ok = differenceMinor == 0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
          size: 20, color: ok ? KhanyaBrand.forest : Theme.of(context).colorScheme.error),
      title: Text(label),
      trailing: Text(Loti.formatMinor(differenceMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _AccountingControlsCard extends StatelessWidget {
  const _AccountingControlsCard({required this.settings});
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
              leading: const Icon(Icons.currency_exchange_outlined),
              title: const Text('Base currency'),
              trailing: Text(settings.baseCurrency),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Fiscal year starts'),
              trailing: Text(_monthName(settings.fiscalYearStartMonth)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lock_clock_outlined),
              title: const Text('Period locked through'),
              subtitle: settings.lockReason == null ? null : Text(settings.lockReason!),
              trailing: Text(settings.lockedThrough == null ? 'Open' : _date(settings.lockedThrough!)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfitLossTab extends StatelessWidget {
  const _ProfitLossTab({required this.report, required this.start, required this.end});
  final ProfitLossReport report;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    return _StatementList(
      title: 'Profit & Loss',
      subtitle: '${_date(start)} – ${_date(end)}',
      rows: [
        _StatementRowData('Sales revenue', report.salesRevenueMinor),
        _StatementRowData('Other income', report.otherIncomeMinor),
        _StatementRowData('Cost of sales', -report.costOfSalesMinor),
        _StatementRowData('Gross profit', report.grossProfitMinor, emphasized: true),
        _StatementRowData('Operating expenses', -report.operatingExpensesMinor),
        _StatementRowData('Net profit', report.netProfitMinor, emphasized: true),
      ],
      detail: report.accounts
          .map((row) => _StatementRowData('${row.code}  ${row.name}', row.amountMinor))
          .toList(growable: false),
      detailTitle: 'Account detail',
    );
  }
}

class _BalanceSheetTab extends StatelessWidget {
  const _BalanceSheetTab({required this.report, required this.asOf});
  final BalanceSheetReport report;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    return _StatementList(
      title: 'Balance Sheet',
      subtitle: 'As at ${_date(asOf)}',
      rows: [
        _StatementRowData('Assets', report.assetsMinor, emphasized: true),
        _StatementRowData('Liabilities', report.liabilitiesMinor),
        _StatementRowData('Equity before current earnings', report.equityMinor),
        _StatementRowData('Current earnings', report.currentEarningsMinor),
        _StatementRowData('Equity including current earnings', report.equityIncludingEarningsMinor, emphasized: true),
        _StatementRowData('Liabilities + equity', report.liabilitiesAndEquityMinor, emphasized: true),
        _StatementRowData('Balance sheet difference', report.differenceMinor),
      ],
      statusText: report.balances ? 'Balanced' : 'Out of balance',
      statusOk: report.balances,
    );
  }
}

class _TrialBalanceTab extends StatelessWidget {
  const _TrialBalanceTab({required this.report, required this.asOf});
  final TrialBalanceReport report;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatementHeader(
          title: 'Trial Balance',
          subtitle: 'As at ${_date(asOf)}',
          statusText: report.balances ? 'Balanced' : 'Out of balance',
          statusOk: report.balances,
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
                DataColumn(label: Text('Debit'), numeric: true),
                DataColumn(label: Text('Credit'), numeric: true),
                DataColumn(label: Text('Balance'), numeric: true),
              ],
              rows: [
                for (final row in report.accounts)
                  DataRow(cells: [
                    DataCell(Text(row.code)),
                    DataCell(Text(row.name)),
                    DataCell(Text(Loti.formatMinor(row.debitsMinor))),
                    DataCell(Text(Loti.formatMinor(row.creditsMinor))),
                    DataCell(Text(Loti.formatMinor(row.balanceMinor))),
                  ]),
                DataRow(cells: [
                  const DataCell(Text('')),
                  const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900))),
                  DataCell(Text(Loti.formatMinor(report.totalDebitsMinor), style: const TextStyle(fontWeight: FontWeight.w900))),
                  DataCell(Text(Loti.formatMinor(report.totalCreditsMinor), style: const TextStyle(fontWeight: FontWeight.w900))),
                  DataCell(Text(Loti.formatMinor(report.differenceMinor), style: const TextStyle(fontWeight: FontWeight.w900))),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _LedgerTab extends StatelessWidget {
  const _LedgerTab({
    required this.rows,
    required this.accounts,
    required this.selectedAccountCode,
    required this.start,
    required this.end,
    required this.onAccountChanged,
  });

  final List<LedgerRow> rows;
  final List<AccountingAccount> accounts;
  final String? selectedAccountCode;
  final DateTime start;
  final DateTime end;
  final ValueChanged<String?> onAccountChanged;

  @override
  Widget build(BuildContext context) {
    final visible = selectedAccountCode == null
        ? rows
        : rows.where((row) => row.accountCode == selectedAccountCode).toList(growable: false);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatementHeader(title: 'General Ledger', subtitle: '${_date(start)} – ${_date(end)}'),
        const SizedBox(height: 14),
        DropdownButtonFormField<String?>(
          initialValue: selectedAccountCode,
          decoration: const InputDecoration(labelText: 'Account filter'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All accounts')),
            for (final account in accounts.where((account) => account.isActive))
              DropdownMenuItem<String?>(value: account.code, child: Text('${account.code} — ${account.name}')),
          ],
          onChanged: onAccountChanged,
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No ledger entries in this period.')))
        else
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
                rows: [
                  for (final row in visible)
                    DataRow(cells: [
                      DataCell(Text(_date(row.occurredAt))),
                      DataCell(Text(row.entryNumber)),
                      DataCell(Text('${row.accountCode} ${row.accountName}')),
                      DataCell(SizedBox(width: 280, child: Text(row.description, overflow: TextOverflow.ellipsis))),
                      DataCell(Text(Loti.formatMinor(row.debitMinor))),
                      DataCell(Text(Loti.formatMinor(row.creditMinor))),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _JournalsTab extends StatelessWidget {
  const _JournalsTab({required this.journals});
  final List<JournalSummary> journals;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StatementHeader(
          title: 'Journal Entries',
          subtitle: 'Immutable source-linked accounting entries. Operational journals are corrected from their source transaction.',
        ),
        const SizedBox(height: 14),
        if (journals.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No journal entries recorded yet.')))
        else
          for (final journal in journals)
            Card(
              child: ExpansionTile(
                title: Text('${journal.entryNumber}  •  ${journal.description}'),
                subtitle: Text('${_dateTime(journal.occurredAt)}  •  ${_sourceLabel(journal.sourceType)}  •  ${Loti.formatMinor(journal.totalDebitMinor)}'),
                children: [
                  for (final line in journal.lines)
                    ListTile(
                      dense: true,
                      title: Text('${line.accountCode}  ${line.accountName}'),
                      subtitle: line.memo == null ? null : Text(line.memo!),
                      trailing: Text(
                        line.debitMinor > 0
                            ? 'Dr ${Loti.formatMinor(line.debitMinor)}'
                            : 'Cr ${Loti.formatMinor(line.creditMinor)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  if (journal.reversalReason != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Text('Reversal: ${journal.reversalReason}', style: Theme.of(context).textTheme.bodySmall),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({required this.accounts});
  final List<AccountingAccount> accounts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _StatementHeader(
          title: 'Chart of Accounts',
          subtitle: 'System and reporting accounts used by automatic and accountant postings.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Column(
            children: [
              for (final account in accounts)
                ListTile(
                  leading: CircleAvatar(child: Text(account.code.substring(0, account.code.length.clamp(0, 2)))),
                  title: Text('${account.code}  ${account.name}'),
                  subtitle: Text('${_titleCase(account.accountType)} • ${account.reportGroup ?? 'General'} • ${account.normalBalance} normal'),
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      if (account.isSystem) const Chip(label: Text('System')),
                      if (!account.isActive) const Chip(label: Text('Inactive')),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatementList extends StatelessWidget {
  const _StatementList({
    required this.title,
    required this.subtitle,
    required this.rows,
    this.detail = const [],
    this.detailTitle,
    this.statusText,
    this.statusOk,
  });

  final String title;
  final String subtitle;
  final List<_StatementRowData> rows;
  final List<_StatementRowData> detail;
  final String? detailTitle;
  final String? statusText;
  final bool? statusOk;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatementHeader(title: title, subtitle: subtitle, statusText: statusText, statusOk: statusOk),
        const SizedBox(height: 14),
        _StatementCard(rows: rows),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(detailTitle ?? 'Detail', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _StatementCard(rows: detail),
        ],
      ],
    );
  }
}

class _StatementHeader extends StatelessWidget {
  const _StatementHeader({required this.title, required this.subtitle, this.statusText, this.statusOk});

  final String title;
  final String subtitle;
  final String? statusText;
  final bool? statusOk;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.description_outlined, color: KhanyaBrand.forest),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (statusText != null)
              Chip(
                avatar: Icon(statusOk == true ? Icons.check_circle_outline : Icons.error_outline, size: 18),
                label: Text(statusText!),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatementCard extends StatelessWidget {
  const _StatementCard({required this.rows});
  final List<_StatementRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        row.label,
                        style: TextStyle(fontWeight: row.emphasized ? FontWeight.w900 : FontWeight.w500),
                      ),
                    ),
                    Text(
                      Loti.formatMinor(row.amountMinor),
                      style: TextStyle(fontWeight: row.emphasized ? FontWeight.w900 : FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatementRowData {
  const _StatementRowData(this.label, this.amountMinor, {this.emphasized = false});
  final String label;
  final int amountMinor;
  final bool emphasized;
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
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Accounting data could not be loaded. This workspace requires a connection to the business ledger.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _sourceLabel(String source) => source
    .split('_')
    .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

String _titleCase(String value) => value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

String _monthName(int month) => switch (month) {
      1 => 'January',
      2 => 'February',
      3 => 'March',
      4 => 'April',
      5 => 'May',
      6 => 'June',
      7 => 'July',
      8 => 'August',
      9 => 'September',
      10 => 'October',
      11 => 'November',
      12 => 'December',
      _ => 'Month $month',
    };
