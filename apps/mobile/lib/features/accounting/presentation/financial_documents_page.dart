import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/accounting/data/financial_statement_printer.dart';

class FinancialDocumentsPage extends StatefulWidget {
  const FinancialDocumentsPage({super.key});

  @override
  State<FinancialDocumentsPage> createState() => _FinancialDocumentsPageState();
}

class _FinancialDocumentsPageState extends State<FinancialDocumentsPage> {
  late DateTime _start;
  late DateTime _end;
  late Future<_FinancialDocumentsData> _future;
  bool _printing = false;

  AccountingRepository get _repository => context.read<AccountingRepository>();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = DateTime(now.year, 1, 1);
    _reload();
  }

  void _reload() {
    _future = _load();
  }

  Future<_FinancialDocumentsData> _load() async {
    final results = await Future.wait<Object>([
      _repository.profitLoss(start: _start, end: _end),
      _repository.balanceSheet(asOf: _end),
      _repository.trialBalance(asOf: _end),
      _repository.settings(),
    ]);
    return _FinancialDocumentsData(
      profitLoss: results[0] as ProfitLossReport,
      balanceSheet: results[1] as BalanceSheetReport,
      trialBalance: results[2] as TrialBalanceReport,
      settings: results[3] as AccountingSettings,
    );
  }

  Future<void> _pickStart() async {
    final value = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: _end,
      initialDate: _start,
    );
    if (value == null) return;
    setState(() {
      _start = value;
      _reload();
    });
  }

  Future<void> _pickEnd() async {
    final value = await showDatePicker(
      context: context,
      firstDate: _start,
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDate: _end,
    );
    if (value == null) return;
    setState(() {
      _end = DateTime(value.year, value.month, value.day, 23, 59, 59);
      _reload();
    });
  }

  Future<void> _print(Future<void> Function() action) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open the financial document: $error')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Statements'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _printing ? null : () => setState(_reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_FinancialDocumentsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _FailureView(onRetry: () => setState(_reload));
          }
          final data = snapshot.requireData;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 920;
              return ListView(
                padding: EdgeInsets.all(wide ? 28 : 16),
                children: [
                  _HeaderCard(
                    start: _start,
                    end: _end,
                    currency: data.settings.baseCurrency,
                    onStart: _printing ? null : _pickStart,
                    onEnd: _printing ? null : _pickEnd,
                  ),
                  const SizedBox(height: 18),
                  if (_printing) const LinearProgressIndicator(),
                  if (_printing) const SizedBox(height: 12),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _DocumentCard(
                            title: 'Profit & Loss Statement',
                            subtitle: '${_date(_start)} – ${_date(_end)}',
                            icon: Icons.trending_up,
                            primaryLabel: 'Net profit',
                            primaryValueMinor: data.profitLoss.netProfitMinor,
                            secondaryLabel: 'Sales revenue',
                            secondaryValueMinor: data.profitLoss.salesRevenueMinor,
                            onPrint: _printing
                                ? null
                                : () => _print(
                                      () => FinancialStatementPrinter.printProfitLoss(
                                        report: data.profitLoss,
                                        start: _start,
                                        end: _end,
                                      ),
                                    ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _DocumentCard(
                            title: 'Balance Sheet',
                            subtitle: 'As at ${_date(_end)}',
                            icon: Icons.account_balance_outlined,
                            primaryLabel: 'Total assets',
                            primaryValueMinor: data.balanceSheet.assetsMinor,
                            secondaryLabel: 'Difference',
                            secondaryValueMinor: data.balanceSheet.differenceMinor,
                            status: data.balanceSheet.balances ? 'Balanced' : 'Out of balance',
                            statusOk: data.balanceSheet.balances,
                            onPrint: _printing
                                ? null
                                : () => _print(
                                      () => FinancialStatementPrinter.printBalanceSheet(
                                        report: data.balanceSheet,
                                        asOf: _end,
                                      ),
                                    ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _DocumentCard(
                            title: 'Trial Balance',
                            subtitle: 'As at ${_date(_end)}',
                            icon: Icons.table_chart_outlined,
                            primaryLabel: 'Total debits',
                            primaryValueMinor: data.trialBalance.totalDebitsMinor,
                            secondaryLabel: 'Difference',
                            secondaryValueMinor: data.trialBalance.differenceMinor,
                            status: data.trialBalance.balances ? 'Balanced' : 'Out of balance',
                            statusOk: data.trialBalance.balances,
                            onPrint: _printing
                                ? null
                                : () => _print(
                                      () => FinancialStatementPrinter.printTrialBalance(
                                        report: data.trialBalance,
                                        asOf: _end,
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _DocumentCard(
                      title: 'Profit & Loss Statement',
                      subtitle: '${_date(_start)} – ${_date(_end)}',
                      icon: Icons.trending_up,
                      primaryLabel: 'Net profit',
                      primaryValueMinor: data.profitLoss.netProfitMinor,
                      secondaryLabel: 'Sales revenue',
                      secondaryValueMinor: data.profitLoss.salesRevenueMinor,
                      onPrint: _printing
                          ? null
                          : () => _print(
                                () => FinancialStatementPrinter.printProfitLoss(
                                  report: data.profitLoss,
                                  start: _start,
                                  end: _end,
                                ),
                              ),
                    ),
                    const SizedBox(height: 12),
                    _DocumentCard(
                      title: 'Balance Sheet',
                      subtitle: 'As at ${_date(_end)}',
                      icon: Icons.account_balance_outlined,
                      primaryLabel: 'Total assets',
                      primaryValueMinor: data.balanceSheet.assetsMinor,
                      secondaryLabel: 'Difference',
                      secondaryValueMinor: data.balanceSheet.differenceMinor,
                      status: data.balanceSheet.balances ? 'Balanced' : 'Out of balance',
                      statusOk: data.balanceSheet.balances,
                      onPrint: _printing
                          ? null
                          : () => _print(
                                () => FinancialStatementPrinter.printBalanceSheet(
                                  report: data.balanceSheet,
                                  asOf: _end,
                                ),
                              ),
                    ),
                    const SizedBox(height: 12),
                    _DocumentCard(
                      title: 'Trial Balance',
                      subtitle: 'As at ${_date(_end)}',
                      icon: Icons.table_chart_outlined,
                      primaryLabel: 'Total debits',
                      primaryValueMinor: data.trialBalance.totalDebitsMinor,
                      secondaryLabel: 'Difference',
                      secondaryValueMinor: data.trialBalance.differenceMinor,
                      status: data.trialBalance.balances ? 'Balanced' : 'Out of balance',
                      statusOk: data.trialBalance.balances,
                      onPrint: _printing
                          ? null
                          : () => _print(
                                () => FinancialStatementPrinter.printTrialBalance(
                                  report: data.trialBalance,
                                  asOf: _end,
                                ),
                              ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline, color: KhanyaBrand.navy),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Print / Save PDF opens the platform print workflow. On desktop you can print directly or choose a PDF printer. Values come from posted journal entries in the Khanya accounting ledger.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _FinancialDocumentsData {
  const _FinancialDocumentsData({
    required this.profitLoss,
    required this.balanceSheet,
    required this.trialBalance,
    required this.settings,
  });

  final ProfitLossReport profitLoss;
  final BalanceSheetReport balanceSheet;
  final TrialBalanceReport trialBalance;
  final AccountingSettings settings;
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.start,
    required this.end,
    required this.currency,
    required this.onStart,
    required this.onEnd,
  });

  final DateTime start;
  final DateTime end;
  final String currency;
  final VoidCallback? onStart;
  final VoidCallback? onEnd;

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
          const KhanyaMark(size: 58, radius: 14),
          SizedBox(
            width: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Branded financial documents',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Choose the reporting period, review the figures, then print or save the statement as PDF. Base currency: $currency.',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: onStart,
            style: _heroButtonStyle(),
            icon: const Icon(Icons.date_range_outlined),
            label: Text('From ${_date(start)}'),
          ),
          OutlinedButton.icon(
            onPressed: onEnd,
            style: _heroButtonStyle(),
            icon: const Icon(Icons.event_available_outlined),
            label: Text('To ${_date(end)}'),
          ),
        ],
      ),
    );
  }

  ButtonStyle _heroButtonStyle() => OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white54),
      );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.primaryLabel,
    required this.primaryValueMinor,
    required this.secondaryLabel,
    required this.secondaryValueMinor,
    required this.onPrint,
    this.status,
    this.statusOk,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String primaryLabel;
  final int primaryValueMinor;
  final String secondaryLabel;
  final int secondaryValueMinor;
  final VoidCallback? onPrint;
  final String? status;
  final bool? statusOk;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: KhanyaBrand.forest.withValues(alpha: 0.10),
                  child: Icon(icon, color: KhanyaBrand.forest),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(primaryLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                Loti.formatMinor(primaryValueMinor),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text(secondaryLabel)),
                Text(Loti.formatMinor(secondaryValueMinor), style: const TextStyle(fontWeight: FontWeight.w800)),
              ],
            ),
            if (status != null) ...[
              const SizedBox(height: 12),
              Chip(
                avatar: Icon(statusOk == true ? Icons.check_circle_outline : Icons.error_outline, size: 18),
                label: Text(status!),
              ),
            ],
            const SizedBox(height: 18),
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

class _FailureView extends StatelessWidget {
  const _FailureView({required this.onRetry});
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
              'Financial statements could not be loaded. Connect to the business ledger and try again.',
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
