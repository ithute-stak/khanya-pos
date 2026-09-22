import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/data/financial_report_pdf_service.dart';
import 'package:khanya_pos/features/accounting/domain/accounting_models.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class FinancialStatementsPage extends StatefulWidget {
  const FinancialStatementsPage({super.key});

  @override
  State<FinancialStatementsPage> createState() => _FinancialStatementsPageState();
}

class _FinancialStatementsPageState extends State<FinancialStatementsPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<AccountingWorkspaceData> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = now;
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

  Future<void> _pickStart() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: _end,
    );
    if (selected == null) return;
    setState(() {
      _start = DateTime(selected.year, selected.month, selected.day);
      _reload();
    });
  }

  Future<void> _pickEnd() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (selected == null) return;
    setState(() {
      _end = DateTime(selected.year, selected.month, selected.day, 23, 59, 59, 999);
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
    final canRead = const {'owner', 'admin', 'manager', 'accountant'}.contains(_role());
    if (!canRead) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Financial statements are available to authorised management and accounting roles.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Statements'),
        actions: [
          IconButton(
            tooltip: 'Refresh statements',
            onPressed: () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
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
            child: FutureBuilder<AccountingWorkspaceData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(onRetry: () => setState(_reload));
                }
                final data = snapshot.requireData;
                return _StatementList(data: data, start: _start, end: _end);
              },
            ),
          ),
        ],
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

class _StatementList extends StatelessWidget {
  const _StatementList({required this.data, required this.start, required this.end});

  final AccountingWorkspaceData data;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        _HeaderCard(data: data, start: start, end: end),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: wide ? 3 : 1,
          childAspectRatio: wide ? 1.2 : 1.75,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
          children: [
            _StatementCard(
              title: 'Profit & Loss',
              subtitle: '${_date(start)} – ${_date(end)}',
              icon: Icons.trending_up_outlined,
              primaryLabel: 'Net profit / (loss)',
              primaryValue: Loti.formatMinor(data.profitLoss.netProfitMinor),
              detail: 'Revenue ${Loti.formatMinor(data.profitLoss.salesRevenueMinor)} • Gross profit ${Loti.formatMinor(data.profitLoss.grossProfitMinor)}',
              onPrint: () => FinancialReportPdfService.printProfitLoss(
                report: data.profitLoss,
                start: start,
                end: end,
              ),
            ),
            _StatementCard(
              title: 'Balance Sheet',
              subtitle: 'As at ${_date(end)}',
              icon: Icons.account_balance_outlined,
              primaryLabel: 'Total assets',
              primaryValue: Loti.formatMinor(data.balanceSheet.assetsMinor),
              detail: data.balanceSheet.isBalanced
                  ? 'Balanced • Liabilities + equity ${Loti.formatMinor(data.balanceSheet.liabilitiesAndEquityMinor)}'
                  : 'Attention • Difference ${Loti.formatMinor(data.balanceSheet.differenceMinor)}',
              onPrint: () => FinancialReportPdfService.printBalanceSheet(
                report: data.balanceSheet,
                asOf: end,
              ),
            ),
            _StatementCard(
              title: 'Trial Balance',
              subtitle: 'As at ${_date(end)}',
              icon: Icons.balance_outlined,
              primaryLabel: 'Total debits',
              primaryValue: Loti.formatMinor(data.trialBalance.totalDebitsMinor),
              detail: data.trialBalance.isBalanced
                  ? 'Balanced • Credits ${Loti.formatMinor(data.trialBalance.totalCreditsMinor)}'
                  : 'Attention • Difference ${Loti.formatMinor(data.trialBalance.differenceMinor)}',
              onPrint: () => FinancialReportPdfService.printTrialBalance(
                report: data.trialBalance,
                asOf: end,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_outlined, color: KhanyaBrand.forest),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Statement integrity', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        data.reconciliation.healthy
                            ? 'The trial balance and core subledgers currently reconcile. Printed statements use the same server-calculated accounting snapshot displayed in the app.'
                            : 'The accounting reconciliation currently needs attention. Review Accounting before relying on printed statements for formal reporting.',
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.data, required this.start, required this.end});

  final AccountingWorkspaceData data;
  final DateTime start;
  final DateTime end;

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
          const Icon(Icons.description_outlined, size: 42, color: Colors.white),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Khanya Financial Statements',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_date(start)} – ${_date(end)} • ${data.settings.baseCurrency}',
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

class _StatementCard extends StatelessWidget {
  const _StatementCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryLabel,
    required this.primaryValue,
    required this.detail,
    required this.onPrint,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryLabel;
  final String primaryValue;
  final String detail;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: KhanyaBrand.forest, size: 30),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Text(primaryValue, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            Text(primaryLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print_outlined),
                label: const Text('Print / Save PDF'),
              ),
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
            const Icon(Icons.cloud_off_outlined, size: 46),
            const SizedBox(height: 12),
            const Text('Could not load financial statements. Check the connection and your accounting permissions.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
