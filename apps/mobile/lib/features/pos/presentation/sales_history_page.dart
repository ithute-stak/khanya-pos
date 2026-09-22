import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/sales_history.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/sales_history_bloc.dart';

class SalesHistoryPage extends StatelessWidget {
  const SalesHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SalesHistoryCubit(repository: context.read<SalesRepository>())..load(),
      child: const _SalesHistoryView(),
    );
  }
}

class _SalesHistoryView extends StatefulWidget {
  const _SalesHistoryView();

  @override
  State<_SalesHistoryView> createState() => _SalesHistoryViewState();
}

class _SalesHistoryViewState extends State<_SalesHistoryView> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales History'),
        actions: [
          BlocBuilder<SalesHistoryCubit, SalesHistoryState>(
            builder: (context, state) => IconButton(
              tooltip: 'Refresh sales',
              onPressed: state.status == SalesHistoryStatus.loading
                  ? null
                  : () => context.read<SalesHistoryCubit>().load(),
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: BlocBuilder<SalesHistoryCubit, SalesHistoryState>(
        builder: (context, state) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final padding = constraints.maxWidth >= 900 ? 28.0 : 16.0;
              return RefreshIndicator(
                onRefresh: () => context.read<SalesHistoryCubit>().load(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(padding, 16, padding, 36),
                  children: [
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: 'Search sale number',
                        hintText: 'Example: SL-20260921',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Search',
                          onPressed: () => context.read<SalesHistoryCubit>().load(
                                search: _searchController.text,
                              ),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                      onSubmitted: (value) => context.read<SalesHistoryCubit>().load(search: value),
                    ),
                    const SizedBox(height: 16),
                    if (state.status == SalesHistoryStatus.loading)
                      const LinearProgressIndicator(),
                    if (state.status == SalesHistoryStatus.failure) ...[
                      const SizedBox(height: 12),
                      _ErrorCard(
                        message: state.errorMessage ?? 'Sales history could not be loaded.',
                        onRetry: () => context.read<SalesHistoryCubit>().load(),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (state.status != SalesHistoryStatus.loading && state.sales.isEmpty)
                      const _EmptySalesCard()
                    else
                      for (final sale in state.sales) ...[
                        _SaleHistoryCard(
                          sale: sale,
                          onTap: () => context.push('/sales/${sale.id}'),
                        ),
                        const SizedBox(height: 10),
                      ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class SaleDetailPage extends StatelessWidget {
  const SaleDetailPage({super.key, required this.saleId});

  final String saleId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SaleDetailCubit(
        repository: context.read<SalesRepository>(),
        saleId: saleId,
      )..load(),
      child: const _SaleDetailView(),
    );
  }
}

class _SaleDetailView extends StatelessWidget {
  const _SaleDetailView();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SaleDetailCubit, SaleDetailState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage || previous.notice != current.notice,
      listener: (context, state) {
        final message = state.errorMessage ?? state.notice;
        if (message == null || message.isEmpty) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) {
        final sale = state.sale;
        return Scaffold(
          appBar: AppBar(
            title: Text(sale?.saleNumber ?? 'Sale Details'),
            actions: [
              IconButton(
                tooltip: 'Refresh sale',
                onPressed: state.busy ? null : () => context.read<SaleDetailCubit>().load(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Builder(
            builder: (context) {
              if (sale == null && state.status == SaleDetailStatus.loading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (sale == null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _ErrorCard(
                      message: state.errorMessage ?? 'Sale details are unavailable.',
                      onRetry: () => context.read<SaleDetailCubit>().load(),
                    ),
                  ),
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final padding = constraints.maxWidth >= 1000 ? 28.0 : 16.0;
                  final content = <Widget>[
                    if (state.status == SaleDetailStatus.submitting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    _SaleSummaryCard(sale: sale),
                    const SizedBox(height: 16),
                    _SaleLineItemsCard(sale: sale),
                    const SizedBox(height: 16),
                    _PaymentsCard(sale: sale),
                    const SizedBox(height: 16),
                    _ReturnHistoryCard(sale: sale),
                    const SizedBox(height: 18),
                    _ReturnActions(sale: sale, busy: state.busy),
                  ];
                  return RefreshIndicator(
                    onRefresh: () => context.read<SaleDetailCubit>().load(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(padding, 16, padding, 40),
                      children: content,
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _SaleHistoryCard extends StatelessWidget {
  const _SaleHistoryCard({required this.sale, required this.onTap});

  final SaleHistoryEntry sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: sale.hasReturns
                    ? scheme.tertiaryContainer
                    : scheme.primaryContainer,
                child: Icon(
                  sale.hasReturns ? Icons.assignment_return_outlined : Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            sale.saleNumber,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Text(
                          Loti.formatMinor(sale.totalMinor),
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Text(_formatDateTime(sale.completedAt)),
                        Text('Payment: ${_title(sale.paymentStatus)}'),
                        if (sale.returnedTotalMinor > 0)
                          Text('Returned: ${Loti.formatMinor(sale.returnedTotalMinor)}'),
                      ],
                    ),
                    if (sale.balanceDueMinor > 0) ...[
                      const SizedBox(height: 5),
                      Text(
                        'Outstanding ${Loti.formatMinor(sale.balanceDueMinor)}',
                        style: TextStyle(color: scheme.error, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleSummaryCard extends StatelessWidget {
  const _SaleSummaryCard({required this.sale});

  final SaleDetail sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 24,
          runSpacing: 14,
          children: [
            _SummaryMetric(label: 'Sale total', value: Loti.formatMinor(sale.totalMinor)),
            _SummaryMetric(label: 'Outstanding', value: Loti.formatMinor(sale.balanceDueMinor)),
            _SummaryMetric(label: 'Returned', value: Loti.formatMinor(sale.returnedTotalMinor)),
            _SummaryMetric(label: 'Still returnable', value: Loti.formatMinor(sale.refundableTotalMinor)),
            _SummaryMetric(label: 'Payment', value: _title(sale.paymentStatus)),
            _SummaryMetric(label: 'Completed', value: _formatDateTime(sale.completedAt)),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 140, maxWidth: 230),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 3),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SaleLineItemsCard extends StatelessWidget {
  const _SaleLineItemsCard({required this.sale});
  final SaleDetail sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Items', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (var index = 0; index < sale.lines.length; index++) ...[
              _SaleLineTile(line: sale.lines[index]),
              if (index != sale.lines.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _SaleLineTile extends StatelessWidget {
  const _SaleLineTile({required this.line});
  final SaleLineDetail line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text('${line.sku} • ${ScaledDecimal.fromMilli(line.quantityMilli)} × ${Loti.formatMinor(line.unitPriceMinor)}'),
                if (line.returnedQuantityMilli > 0) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Returned ${ScaledDecimal.fromMilli(line.returnedQuantityMilli)} • Remaining ${ScaledDecimal.fromMilli(line.returnableQuantityMilli)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            Loti.formatMinor(line.lineTotalMinor),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.sale});
  final SaleDetail sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Payments', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (sale.payments.isEmpty)
              const Text('No immediate payment was recorded; this sale was on customer credit.')
            else
              for (final payment in sale.payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.payments_outlined),
                  title: Text(_title(payment.method)),
                  subtitle: payment.reference == null ? null : Text(payment.reference!),
                  trailing: Text(
                    Loti.formatMinor(payment.amountMinor),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReturnHistoryCard extends StatelessWidget {
  const _ReturnHistoryCard({required this.sale});
  final SaleDetail sale;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Returns & voids', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (sale.returns.isEmpty)
              const Text('No returns or voids have been recorded for this sale.')
            else
              for (final item in sale.returns)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.kind == 'void' ? Icons.block_outlined : Icons.assignment_return_outlined),
                  title: Text('${item.returnNumber} • ${_title(item.kind)}'),
                  subtitle: Text(
                    '${item.reason}\n${_formatDateTime(item.processedAt)}'
                    '${item.refundMethod == null ? '' : ' • ${_title(item.refundMethod!)} refund'}',
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    Loti.formatMinor(item.totalMinor),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReturnActions extends StatelessWidget {
  const _ReturnActions({required this.sale, required this.busy});
  final SaleDetail sale;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (sale.fullyReturned) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline),
              SizedBox(width: 10),
              Expanded(child: Text('This sale has been fully returned or voided.')),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => _returnItems(context, sale),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Return Items'),
            ),
            OutlinedButton.icon(
              onPressed: busy || sale.returns.isNotEmpty ? null : () => _voidSale(context, sale),
              icon: const Icon(Icons.block_outlined),
              label: const Text('Void Entire Sale'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _returnItems(BuildContext context, SaleDetail sale) async {
    final request = await _showReturnDialog(context, sale);
    if (request == null || !context.mounted) return;
    await context.read<SaleDetailCubit>().returnItems(
          quantitiesMilliByLine: request.quantitiesMilliByLine,
          reason: request.reason,
          refundMethod: request.refundMethod,
          refundReference: request.refundReference,
        );
  }

  Future<void> _voidSale(BuildContext context, SaleDetail sale) async {
    final request = await _showVoidDialog(context, sale);
    if (request == null || !context.mounted) return;
    await context.read<SaleDetailCubit>().voidSale(
          reason: request.reason,
          refundMethod: request.refundMethod,
          refundReference: request.refundReference,
        );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _EmptySalesCard extends StatelessWidget {
  const _EmptySalesCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined, size: 42),
            SizedBox(height: 12),
            Text('No sales found for this branch.'),
          ],
        ),
      ),
    );
  }
}

class _ReturnFormResult {
  const _ReturnFormResult({
    required this.quantitiesMilliByLine,
    required this.reason,
    required this.refundMethod,
    this.refundReference,
  });

  final Map<String, int> quantitiesMilliByLine;
  final String reason;
  final String refundMethod;
  final String? refundReference;
}

class _VoidFormResult {
  const _VoidFormResult({
    required this.reason,
    required this.refundMethod,
    this.refundReference,
  });

  final String reason;
  final String refundMethod;
  final String? refundReference;
}

Future<_ReturnFormResult?> _showReturnDialog(BuildContext context, SaleDetail sale) async {
  final controllers = <String, TextEditingController>{
    for (final line in sale.lines.where((line) => line.canReturn)) line.id: TextEditingController(),
  };
  final reasonController = TextEditingController();
  final referenceController = TextEditingController();
  var refundMethod = 'cash';
  String? validation;

  final result = await showDialog<_ReturnFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Return sale items'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Enter the quantity being returned for each item. Returned stock is added back to inventory.'),
                const SizedBox(height: 14),
                for (final line in sale.lines.where((line) => line.canReturn)) ...[
                  Text(line.productName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: controllers[line.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      labelText: 'Quantity to return',
                      helperText: 'Available ${ScaledDecimal.fromMilli(line.returnableQuantityMilli)}',
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: reasonController,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Reason for return'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: refundMethod,
                  decoration: const InputDecoration(labelText: 'Refund method'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                  ],
                  onChanged: (value) => setState(() => refundMethod = value ?? 'cash'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: referenceController,
                  decoration: const InputDecoration(labelText: 'Refund reference (optional)'),
                ),
                if (validation != null) ...[
                  const SizedBox(height: 10),
                  Text(validation!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final quantities = <String, int>{};
              for (final line in sale.lines.where((line) => line.canReturn)) {
                final value = ScaledDecimal.toMilli(controllers[line.id]!.text);
                if (value > line.returnableQuantityMilli) {
                  setState(() => validation = '${line.productName} exceeds the returnable quantity.');
                  return;
                }
                if (value > 0) quantities[line.id] = value;
              }
              final reason = reasonController.text.trim();
              if (quantities.isEmpty) {
                setState(() => validation = 'Enter a quantity for at least one item.');
                return;
              }
              if (reason.length < 2) {
                setState(() => validation = 'Enter a reason for the return.');
                return;
              }
              Navigator.pop(
                dialogContext,
                _ReturnFormResult(
                  quantitiesMilliByLine: quantities,
                  reason: reason,
                  refundMethod: refundMethod,
                  refundReference: referenceController.text.trim().isEmpty
                      ? null
                      : referenceController.text.trim(),
                ),
              );
            },
            child: const Text('Process Return'),
          ),
        ],
      ),
    ),
  );

  for (final controller in controllers.values) {
    controller.dispose();
  }
  reasonController.dispose();
  referenceController.dispose();
  return result;
}

Future<_VoidFormResult?> _showVoidDialog(BuildContext context, SaleDetail sale) async {
  final reasonController = TextEditingController();
  final referenceController = TextEditingController();
  var refundMethod = 'cash';
  String? validation;

  final result = await showDialog<_VoidFormResult>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Void ${sale.saleNumber}?'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'This reverses the remaining ${Loti.formatMinor(sale.refundableTotalMinor)}, restores stock, and posts accounting reversal entries.',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonController,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Reason for void'),
              ),
              DropdownButtonFormField<String>(
                initialValue: refundMethod,
                decoration: const InputDecoration(labelText: 'Refund method'),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                  DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                ],
                onChanged: (value) => setState(() => refundMethod = value ?? 'cash'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(labelText: 'Refund reference (optional)'),
              ),
              if (validation != null) ...[
                const SizedBox(height: 10),
                Text(validation!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.length < 2) {
                setState(() => validation = 'Enter a reason for the void.');
                return;
              }
              Navigator.pop(
                dialogContext,
                _VoidFormResult(
                  reason: reason,
                  refundMethod: refundMethod,
                  refundReference: referenceController.text.trim().isEmpty
                      ? null
                      : referenceController.text.trim(),
                ),
              );
            },
            child: const Text('Void Sale'),
          ),
        ],
      ),
    ),
  );
  reasonController.dispose();
  referenceController.dispose();
  return result;
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _title(String value) {
  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}
