import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late Future<CustomerDetail> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = context.read<CustomerRepository>().getCustomer(widget.customerId);
  }

  Future<void> _refresh() async {
    try {
      await context.read<CustomerRepository>().refresh();
    } catch (_) {
      // getCustomer below falls back to the saved local projection.
    }
    if (!mounted) return;
    setState(_reload);
  }

  Future<void> _recordPayment(CustomerDetail detail) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CustomerPaymentDialog(
        repository: context.read<CustomerRepository>(),
        customer: detail.summary,
      ),
    );
    if (saved == true && mounted) {
      context.read<SyncBloc>().add(const SyncRequested());
      setState(_reload);
    }
  }

  Future<void> _editCreditTerms(CustomerDetail detail) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _CreditTermsDialog(
        repository: context.read<CustomerRepository>(),
        customer: detail.summary,
      ),
    );
    if (saved == true && mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Credit'),
        actions: [
          IconButton(
            tooltip: 'Refresh customer',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<CustomerDetail>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || snapshot.data == null) {
            return _ErrorState(onRetry: _refresh);
          }
          final detail = snapshot.data!;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: [
                _CustomerHeader(
                  detail: detail,
                  onRecordPayment: () => _recordPayment(detail),
                  onEditTerms: () => _editCreditTerms(detail),
                  onStatement: () => context.go('/customers/${detail.summary.id}/statement'),
                ),
                if (detail.isCachedOnly) ...[
                  const SizedBox(height: 12),
                  Material(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(Icons.cloud_off_outlined, size: 20),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Offline view — totals include saved local credit projections. Invoice ageing will refresh when online.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Text('Ageing', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                _AgeingGrid(ageing: detail.ageingMinor),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Open invoices',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text('${detail.openInvoices.length} open'),
                  ],
                ),
                const SizedBox(height: 10),
                if (detail.openInvoices.isEmpty)
                  const _EmptyInvoices()
                else
                  ...detail.openInvoices.map((invoice) => _InvoiceCard(invoice: invoice)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({
    required this.detail,
    required this.onRecordPayment,
    required this.onEditTerms,
    required this.onStatement,
  });

  final CustomerDetail detail;
  final VoidCallback onRecordPayment;
  final VoidCallback onEditTerms;
  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    final customer = detail.summary;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  child: Text(
                    customer.name.trim().isEmpty ? '?' : customer.name.trim()[0].toUpperCase(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                SizedBox(
                  width: 340,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      Text('${customer.code} • ${customer.phone ?? 'No phone'}'),
                      if (customer.email != null) Text(customer.email!),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onRecordPayment,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record payment'),
                ),
                OutlinedButton.icon(
                  onPressed: onStatement,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Statement'),
                ),
                TextButton.icon(
                  onPressed: onEditTerms,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Credit terms'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final items = [
                  _PositionMetric(
                    label: 'Outstanding',
                    value: Loti.formatMinor(customer.outstandingMinor),
                    icon: Icons.account_balance_wallet_outlined,
                  ),
                  _PositionMetric(
                    label: 'Available credit',
                    value: Loti.formatMinor(customer.availableCreditMinor),
                    icon: Icons.credit_score_outlined,
                  ),
                  _PositionMetric(
                    label: 'Credit limit',
                    value: Loti.formatMinor(customer.creditLimitMinor),
                    icon: Icons.price_check_outlined,
                  ),
                  _PositionMetric(
                    label: 'Customer advance',
                    value: Loti.formatMinor(detail.unallocatedAdvanceMinor),
                    icon: Icons.savings_outlined,
                  ),
                ];
                final width = constraints.maxWidth;
                final columns = width >= 900
                    ? 4
                    : width >= 520
                        ? 2
                        : 1;
                return GridView.count(
                  crossAxisCount: columns,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: columns == 1 ? 4.2 : 2.6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: items,
                );
              },
            ),
            const SizedBox(height: 10),
            Text(
              customer.creditLimitMinor == 0
                  ? 'No credit facility configured.'
                  : '${customer.paymentTermsDays} day payment terms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _PositionMetric extends StatelessWidget {
  const _PositionMetric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelSmall),
                  Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AgeingGrid extends StatelessWidget {
  const _AgeingGrid({required this.ageing});

  final Map<String, int> ageing;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, String)>[
      ('current', 'Current'),
      ('1_30', '1–30 days'),
      ('31_60', '31–60 days'),
      ('61_90', '61–90 days'),
      ('over_90', 'Over 90 days'),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 5
            : constraints.maxWidth >= 560
                ? 3
                : 2;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.85,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final entry in entries)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.$2, style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Text(
                        Loti.formatMinor(ageing[entry.$1] ?? 0),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final CustomerInvoice invoice;

  @override
  Widget build(BuildContext context) {
    final overdue = invoice.dueAt != null && invoice.dueAt!.isBefore(DateTime.now());
    return Card(
      child: ListTile(
        leading: Icon(
          overdue ? Icons.warning_amber_rounded : Icons.receipt_long_outlined,
          color: overdue ? Theme.of(context).colorScheme.error : null,
        ),
        title: Text(invoice.saleNumber),
        subtitle: Text(
          'Sale ${_date(invoice.completedAt)}${invoice.dueAt == null ? '' : ' • Due ${_date(invoice.dueAt!)}'}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Loti.formatMinor(invoice.balanceDueMinor),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
            ),
            Text(invoice.paymentStatus),
          ],
        ),
      ),
    );
  }
}

class _EmptyInvoices extends StatelessWidget {
  const _EmptyInvoices();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(child: Text('No open invoices. This customer has no unpaid completed sales.')),
          ],
        ),
      ),
    );
  }
}

class _CustomerPaymentDialog extends StatefulWidget {
  const _CustomerPaymentDialog({required this.repository, required this.customer});

  final CustomerRepository repository;
  final CustomerSummary customer;

  @override
  State<_CustomerPaymentDialog> createState() => _CustomerPaymentDialogState();
}

class _CustomerPaymentDialogState extends State<_CustomerPaymentDialog> {
  late final TextEditingController _amount;
  final _reference = TextEditingController();
  String _method = 'cash';
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final suggested = widget.customer.outstandingMinor > 0 ? widget.customer.outstandingMinor : 0;
    _amount = TextEditingController(text: ScaledDecimal.fromMinor(suggested));
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amountMinor = ScaledDecimal.toMinor(_amount.text);
    if (amountMinor <= 0 || _saving) {
      setState(() => _message = 'Enter a payment amount greater than zero.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final result = await widget.repository.recordPayment(
        customerId: widget.customer.id,
        amountMinor: amountMinor,
        method: _method,
        reference: _reference.text,
      );
      if (!mounted) return;
      final text = switch (result.status) {
        CustomerPaymentSubmissionStatus.synced => 'Payment recorded and synced.',
        CustomerPaymentSubmissionStatus.queued => 'Payment saved offline and queued for sync.',
        CustomerPaymentSubmissionStatus.conflict => 'Payment needs sync review.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = 'The payment could not be saved.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Record payment • ${widget.customer.name}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Outstanding: ${Loti.formatMinor(widget.customer.outstandingMinor)}'),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Amount received (M)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Payment method'),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                DropdownMenuItem(value: 'card', child: Text('Card')),
                DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
              ],
              onChanged: (value) => setState(() => _method = value ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reference,
              decoration: const InputDecoration(labelText: 'Reference (optional)'),
            ),
            const SizedBox(height: 10),
            Text(
              'When no invoice allocation is selected, Khanya applies the receipt to the oldest open invoices first. Any excess becomes a customer advance.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.payments_outlined),
          label: Text(_saving ? 'Saving…' : 'Record payment'),
        ),
      ],
    );
  }
}

class _CreditTermsDialog extends StatefulWidget {
  const _CreditTermsDialog({required this.repository, required this.customer});

  final CustomerRepository repository;
  final CustomerSummary customer;

  @override
  State<_CreditTermsDialog> createState() => _CreditTermsDialogState();
}

class _CreditTermsDialogState extends State<_CreditTermsDialog> {
  late final TextEditingController _limit;
  late final TextEditingController _terms;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _limit = TextEditingController(text: ScaledDecimal.fromMinor(widget.customer.creditLimitMinor));
    _terms = TextEditingController(text: widget.customer.paymentTermsDays.toString());
  }

  @override
  void dispose() {
    _limit.dispose();
    _terms.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limitMinor = ScaledDecimal.toMinor(_limit.text);
    final terms = int.tryParse(_terms.text.trim());
    if (limitMinor < 0 || terms == null || terms < 0 || terms > 365) {
      setState(() => _error = 'Use a non-negative limit and payment terms from 0 to 365 days.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.updateCreditTerms(
        customerId: widget.customer.id,
        creditLimitMinor: limitMinor,
        paymentTermsDays: terms,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Credit terms could not be updated. This action requires a live connection.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Credit terms'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _limit,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Credit limit (M)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _terms,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Payment terms (days)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save terms'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined, size: 52),
            const SizedBox(height: 12),
            const Text('Customer details are not available on this device yet.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

String _date(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}
