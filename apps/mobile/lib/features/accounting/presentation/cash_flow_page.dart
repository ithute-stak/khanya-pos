import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/data/financial_report_pdf_service.dart';
import 'package:khanya_pos/features/accounting/domain/cash_flow_report.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class CashFlowPage extends StatefulWidget {
  const CashFlowPage({super.key});

  @override
  State<CashFlowPage> createState() => _CashFlowPageState();
}

class _CashFlowPageState extends State<CashFlowPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<CashFlowReport> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = now;
    _reload();
  }

  void _reload() {
    _future = context.read<AccountingRepository>().cashFlow(start: _start, end: _end);
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
    final allowed = const {'owner', 'admin', 'manager', 'accountant'}.contains(_role());
    if (!allowed) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Cash flow statements are available to authorised management and accounting roles.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Flow Statement'),
        actions: [
          IconButton(
            tooltip: 'Refresh cash flow',
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
            child: FutureBuilder<CashFlowReport>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _ErrorView(onRetry: () => setState(_reload));
                }
                return _CashFlowBody(report: snapshot.requireData, start: _start, end: _end);
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

class _CashFlowBody extends StatelessWidget {
  const _CashFlowBody({required this.report, required this.start, required this.end});

  final CashFlowReport report;
  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.all(wide ? 28 : 16),
      children: [
        _Hero(report: report, start: start, end: end),
        const SizedBox(height: 16),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: wide ? 3 : 1,
          childAspectRatio: wide ? 1.65 : 2.2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          children: [
            _Metric('Operating activities', report.operatingCashFlowMinor, Icons.storefront_outlined),
            _Metric('Investing activities', report.investingCashFlowMinor, Icons.business_center_outlined),
            _Metric('Financing activities', report.financingCashFlowMinor, Icons.account_balance_outlined),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _RowValue('Opening cash & equivalents', report.openingCashMinor),
                _RowValue('Net change in cash', report.netChangeInCashMinor, emphasize: true),
                const Divider(),
                _RowValue('Closing cash & equivalents', report.closingCashMinor, emphasize: true),
                _RowValue('Reconciliation difference', report.differenceMinor),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(
                      report.reconciles ? Icons.verified_outlined : Icons.warning_amber_rounded,
                      color: report.reconciles ? KhanyaBrand.forest : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        report.reconciles
                            ? 'Opening cash plus this period’s cash movements reconciles exactly to closing cash.'
                            : 'Cash flow does not reconcile to the closing ledger balance. Review the underlying journals.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => FinancialReportPdfService.printCashFlow(
                      report: report,
                      start: start,
                      end: end,
                    ),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print / Save PDF'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text('Cash movement detail', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        if (report.activities.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No cash movements were posted in this period.')))
        else
          for (final activity in report.activities)
            Card(
              child: ListTile(
                leading: CircleAvatar(child: Icon(_categoryIcon(activity.category))),
                title: Text(activity.description),
                subtitle: Text('${_date(activity.occurredAt)} • ${_categoryLabel(activity.category)} • ${activity.entryNumber}'),
                trailing: Text(
                  '${activity.amountMinor > 0 ? '+' : ''}${Loti.formatMinor(activity.amountMinor)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: activity.amountMinor < 0 ? Theme.of(context).colorScheme.error : KhanyaBrand.forest,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.report, required this.start, required this.end});

  final CashFlowReport report;
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
          const Icon(Icons.waterfall_chart_outlined, color: Colors.white, size: 42),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cash Flow Statement',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_date(start)} – ${_date(end)} • Closing cash ${Loti.formatMinor(report.closingCashMinor)}',
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

class _RowValue extends StatelessWidget {
  const _RowValue(this.label, this.valueMinor, {this.emphasize = false});

  final String label;
  final int valueMinor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
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
            const Text('Could not load the cash flow statement. Check the connection and your accounting permissions.'),
            const SizedBox(height: 14),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

IconData _categoryIcon(String category) => switch (category) {
      'investing' => Icons.business_center_outlined,
      'financing' => Icons.account_balance_outlined,
      _ => Icons.storefront_outlined,
    };

String _categoryLabel(String category) => switch (category) {
      'investing' => 'Investing',
      'financing' => 'Financing',
      _ => 'Operating',
    };

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
