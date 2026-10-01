import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/customers/domain/customer_models.dart';
import 'package:khanya_pos/features/pos/domain/checkout_benefits.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/pos_credit_cubit.dart';
import 'package:khanya_pos/features/retail/data/retail_repository.dart';

class PosCustomerCreditPanel extends StatelessWidget {
  const PosCustomerCreditPanel({super.key, required this.totalMinor});

  final int totalMinor;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PosCreditCubit, PosCreditState>(
      builder: (context, state) {
        final customer = state.customer;
        final effectiveTotal = state.effectiveTotalMinorFor(totalMinor);
        final discountMinor = state.discountMinorFor(totalMinor);
        final paidMinor = state.paidMinorFor(totalMinor);
        final creditMinor = state.creditMinorFor(totalMinor);
        final creditAllowed = state.canSubmit(totalMinor);
        final benefits = CheckoutBenefitsStore.validFor(
          subtotalMinor: totalMinor,
          customerId: customer?.id,
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.48),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      customer == null ? Icons.person_outline : Icons.person_pin_circle_outlined,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer?.name ?? 'Walk-in customer',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            customer == null
                                ? 'Select a customer for credit or loyalty-point redemption.'
                                : '${customer.code} • Available credit ${Loti.formatMinor(customer.availableCreditMinor)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => _chooseCustomer(context),
                      child: Text(customer == null ? 'Select' : 'Change'),
                    ),
                    if (customer != null)
                      IconButton(
                        tooltip: 'Remove customer',
                        onPressed: context.read<PosCreditCubit>().clearCustomer,
                        icon: const Icon(Icons.close),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: totalMinor <= 0 ? null : () => _configureBenefits(context, state),
                  icon: const Icon(Icons.local_offer_outlined),
                  label: Text(
                    discountMinor > 0
                        ? 'Discount ${Loti.formatMinor(discountMinor)} • Total ${Loti.formatMinor(effectiveTotal)}'
                        : 'Promotion / loyalty points',
                  ),
                ),
                if (benefits != null && discountMinor > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    [
                      if (benefits.promotionCode != null) 'Promo ${benefits.promotionCode}',
                      if (benefits.loyaltyPointsToRedeem > 0) '${benefits.loyaltyPointsToRedeem} points',
                    ].join(' • '),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (customer != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Pay full'),
                        selected: state.immediatePaymentMinor == null,
                        onSelected: (_) => context.read<PosCreditCubit>().payFull(),
                      ),
                      ChoiceChip(
                        label: const Text('Part payment'),
                        selected: state.immediatePaymentMinor != null &&
                            state.immediatePaymentMinor! > 0 &&
                            state.immediatePaymentMinor! < effectiveTotal,
                        onSelected: (_) => _setPartialPayment(context, state),
                      ),
                      ChoiceChip(
                        label: const Text('On credit'),
                        selected: state.immediatePaymentMinor == 0,
                        onSelected: (_) => context.read<PosCreditCubit>().payOnCredit(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _AmountCell(
                          label: 'Pay now',
                          value: Loti.formatMinor(paidMinor),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _AmountCell(
                          label: 'Credit',
                          value: Loti.formatMinor(creditMinor),
                        ),
                      ),
                    ],
                  ),
                  if (creditMinor > 0 && !creditAllowed) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Credit exceeds the customer’s currently available limit.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _configureBenefits(BuildContext context, PosCreditState state) async {
    final current = CheckoutBenefitsStore.validFor(
      subtotalMinor: totalMinor,
      customerId: state.customer?.id,
    );
    final promo = TextEditingController(text: current?.promotionCode ?? '');
    final points = TextEditingController(
      text: current?.loyaltyPointsToRedeem == null || current!.loyaltyPointsToRedeem == 0
          ? ''
          : current.loyaltyPointsToRedeem.toString(),
    );
    final apply = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Promotion & loyalty'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Cart subtotal: ${Loti.formatMinor(totalMinor)}'),
              const SizedBox(height: 12),
              TextField(
                controller: promo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Promotion code',
                  hintText: 'e.g. WEEKEND10',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: points,
                keyboardType: TextInputType.number,
                enabled: state.customer != null,
                decoration: InputDecoration(
                  labelText: 'Loyalty points to redeem',
                  helperText: state.customer == null ? 'Select a customer to redeem points.' : null,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The server validates the code, dates, minimum spend, usage limit and available points before the payment amount changes.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              CheckoutBenefitsStore.clear();
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Clear'),
          ),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Validate & apply')),
        ],
      ),
    );
    if (!context.mounted) {
      promo.dispose();
      points.dispose();
      return;
    }
    if (apply == false) {
      context.read<PosCreditCubit>().benefitsUpdated();
      promo.dispose();
      points.dispose();
      return;
    }
    if (apply != true) {
      promo.dispose();
      points.dispose();
      return;
    }

    final promotionCode = promo.text.trim().isEmpty ? null : promo.text.trim().toUpperCase();
    final loyaltyPoints = int.tryParse(points.text.trim()) ?? 0;
    promo.dispose();
    points.dispose();
    if (promotionCode == null && loyaltyPoints == 0) {
      CheckoutBenefitsStore.clear();
      context.read<PosCreditCubit>().benefitsUpdated();
      return;
    }

    try {
      final preview = await context.read<RetailRepository>().previewCheckoutBenefits(
            subtotalMinor: totalMinor,
            customerId: state.customer?.id,
            promotionCode: promotionCode,
            loyaltyPointsToRedeem: loyaltyPoints,
          );
      if (!context.mounted) return;
      final total = ScaledDecimal.toMinor(preview['total']);
      final discount = ScaledDecimal.toMinor(preview['discount_total']);
      CheckoutBenefitsStore.apply(
        CheckoutBenefitsSelection(
          subtotalMinor: totalMinor,
          totalMinor: total,
          discountMinor: discount,
          customerId: state.customer?.id,
          promotionCode: preview['promotion_code']?.toString(),
          loyaltyPointsToRedeem: loyaltyPoints,
        ),
      );
      context.read<PosCreditCubit>().benefitsUpdated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Discount applied. New sale total: ${Loti.formatMinor(total)}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      final message = context.read<RetailRepository>().errorMessage(error, 'Could not validate this promotion or loyalty redemption.');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _chooseCustomer(BuildContext context) async {
    final selected = await showDialog<CustomerSummary>(
      context: context,
      builder: (_) => _CustomerPickerDialog(
        repository: context.read<CustomerRepository>(),
      ),
    );
    if (selected != null && context.mounted) {
      context.read<PosCreditCubit>().selectCustomer(selected);
    }
  }

  Future<void> _setPartialPayment(BuildContext context, PosCreditState state) async {
    final effectiveTotal = state.effectiveTotalMinorFor(totalMinor);
    if (state.customer == null || effectiveTotal <= 1) return;
    final suggested = state.immediatePaymentMinor != null &&
            state.immediatePaymentMinor! > 0 &&
            state.immediatePaymentMinor! < effectiveTotal
        ? state.immediatePaymentMinor!
        : effectiveTotal ~/ 2;
    final controller = TextEditingController(text: ScaledDecimal.fromMinor(suggested));
    final value = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Part payment'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Sale total: ${Loti.formatMinor(effectiveTotal)}'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Amount paid now (M)'),
                onSubmitted: (_) {
                  final amount = ScaledDecimal.toMinor(controller.text);
                  if (amount > 0 && amount < effectiveTotal) Navigator.of(dialogContext).pop(amount);
                },
              ),
              const SizedBox(height: 8),
              Text(
                'The remaining balance will be posted to Accounts Receivable.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final amount = ScaledDecimal.toMinor(controller.text);
              if (amount <= 0 || amount >= effectiveTotal) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Part payment must be greater than zero and less than the sale total.')),
                );
                return;
              }
              Navigator.of(dialogContext).pop(amount);
            },
            child: const Text('Use amount'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && context.mounted) {
      context.read<PosCreditCubit>().setPartialPayment(value);
    }
  }
}

class _AmountCell extends StatelessWidget {
  const _AmountCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({required this.repository});

  final CustomerRepository repository;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _search = TextEditingController();
  late Future<List<CustomerSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CustomerSummary>> _load() async {
    try {
      await widget.repository.refresh();
    } catch (_) {
      // Saved customers remain available while offline.
    }
    return widget.repository.cachedCustomers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select customer'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search customer, code or phone',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<List<CustomerSummary>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final query = _search.text.trim().toLowerCase();
                  final customers = (snapshot.data ?? const <CustomerSummary>[])
                      .where((customer) =>
                          query.isEmpty ||
                          customer.name.toLowerCase().contains(query) ||
                          customer.code.toLowerCase().contains(query) ||
                          (customer.phone?.toLowerCase().contains(query) ?? false))
                      .toList(growable: false);
                  if (customers.isEmpty) {
                    return const Center(child: Text('No saved customers match this search.'));
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return ListTile(
                        title: Text(customer.name),
                        subtitle: Text(
                          '${customer.code} • Outstanding ${Loti.formatMinor(customer.outstandingMinor)}',
                        ),
                        trailing: Text(
                          Loti.formatMinor(customer.availableCreditMinor),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        onTap: () => Navigator.of(context).pop(customer),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
