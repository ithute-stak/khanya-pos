import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/documents/data/document_repository.dart';
import 'package:khanya_pos/features/documents/data/receipt_picker.dart';
import 'package:khanya_pos/features/documents/presentation/bloc/receipt_capture_bloc.dart';
import 'package:khanya_pos/features/documents/presentation/receipt_capture_buttons.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/domain/purchasing_models.dart';
import 'package:khanya_pos/features/purchasing/presentation/bloc/purchase_draft_bloc.dart';

class NewPurchasePage extends StatelessWidget {
  const NewPurchasePage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => PurchaseDraftBloc(
            purchasingRepository: context.read<PurchasingRepository>(),
            productRepository: context.read<ProductRepository>(),
          )..add(const PurchaseDraftStarted()),
        ),
        BlocProvider(
          create: (_) => ReceiptCaptureBloc(repository: context.read<DocumentRepository>()),
        ),
      ],
      child: const _NewPurchaseView(),
    );
  }
}

class _NewPurchaseView extends StatelessWidget {
  const _NewPurchaseView();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ReceiptCaptureBloc, ReceiptCaptureState>(
          listenWhen: (previous, current) =>
              previous.selected?.id != current.selected?.id && current.selected != null,
          listener: (context, state) {
            context.read<PurchaseDraftBloc>().add(PurchaseDraftReceiptAttached(state.selected!));
          },
        ),
        BlocListener<PurchaseDraftBloc, PurchaseDraftState>(
          listenWhen: (previous, current) => previous.status != current.status,
          listener: (context, state) {
            if (state.status == PurchaseDraftStatus.success) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message ?? 'Purchase saved.')),
              );
              context.pop();
            }
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(title: const Text('New Purchase')),
        body: BlocBuilder<PurchaseDraftBloc, PurchaseDraftState>(
          builder: (context, state) {
            if (state.status == PurchaseDraftStatus.loading ||
                state.status == PurchaseDraftStatus.initial) {
              return const Center(child: CircularProgressIndicator());
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
                final details = _PurchaseDetails(state: state);
                final side = _ReceiptPaymentSummary(state: state);
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(padding, 16, padding, 32),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1300),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: details),
                                const SizedBox(width: 18),
                                Expanded(flex: 2, child: side),
                              ],
                            )
                          : Column(
                              children: [details, const SizedBox(height: 16), side],
                            ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PurchaseDetails extends StatelessWidget {
  const _PurchaseDetails({required this.state});
  final PurchaseDraftState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supplier & invoice', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: state.supplierId,
                  decoration: const InputDecoration(labelText: 'Supplier (optional)'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Cash / one-off supplier'),
                    ),
                    ...state.suppliers.map(
                      (supplier) => DropdownMenuItem<String?>(
                        value: supplier.id,
                        child: Text(supplier.name, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                  onChanged: (value) => context
                      .read<PurchaseDraftBloc>()
                      .add(PurchaseDraftSupplierSelected(value)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: state.invoiceNumber,
                  decoration: const InputDecoration(
                    labelText: 'Supplier invoice / receipt number',
                  ),
                  onChanged: (value) => context
                      .read<PurchaseDraftBloc>()
                      .add(PurchaseDraftInvoiceChanged(value)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Stock items', style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    FilledButton.tonalIcon(
                      onPressed: () => _pickProduct(context, state),
                      icon: const Icon(Icons.add),
                      label: const Text('Add item'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (state.lines.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Add the products purchased. Stock is updated only after the purchase is confirmed.',
                    ),
                  )
                else
                  ...state.lines.map((line) => _PurchaseLineTile(line: line)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickProduct(BuildContext context, PurchaseDraftState state) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text('Choose product', style: Theme.of(sheetContext).textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: state.products.length,
                  itemBuilder: (context, index) {
                    final product = state.products[index];
                    final alreadyAdded = state.lines.any((line) => line.product.id == product.id);
                    return ListTile(
                      enabled: !alreadyAdded,
                      title: Text(product.name),
                      subtitle: Text(
                        '${product.sku} • Current cost ${Loti.formatMinor(product.costPriceMinor)}',
                      ),
                      trailing: alreadyAdded ? const Icon(Icons.check) : const Icon(Icons.add),
                      onTap: alreadyAdded
                          ? null
                          : () => Navigator.pop(sheetContext, product.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !context.mounted) return;
    final product = state.products.firstWhere((item) => item.id == selected);
    context.read<PurchaseDraftBloc>().add(PurchaseDraftProductAdded(product));
  }
}

class _PurchaseLineTile extends StatelessWidget {
  const _PurchaseLineTile({required this.line});
  final PurchaseDraftLine line;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(line.product.name, style: Theme.of(context).textTheme.titleSmall),
                  ),
                  IconButton(
                    tooltip: 'Remove',
                    onPressed: () => context
                        .read<PurchaseDraftBloc>()
                        .add(PurchaseDraftLineRemoved(line.product.id)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('qty-${line.product.id}'),
                      initialValue: ScaledDecimal.fromMilli(line.quantityMilli),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Quantity (${line.product.unit})'),
                      onChanged: (value) => context.read<PurchaseDraftBloc>().add(
                            PurchaseDraftQuantityChanged(
                              productId: line.product.id,
                              value: value,
                            ),
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      key: ValueKey('cost-${line.product.id}'),
                      initialValue: ScaledDecimal.fromMinor(line.unitCostMinor),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Unit cost (M)'),
                      onChanged: (value) => context.read<PurchaseDraftBloc>().add(
                            PurchaseDraftCostChanged(
                              productId: line.product.id,
                              value: value,
                            ),
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Line total ${Loti.formatMinor(line.lineTotalMinor)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReceiptPaymentSummary extends StatelessWidget {
  const _ReceiptPaymentSummary({required this.state});
  final PurchaseDraftState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shopping receipt', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'Attach the supplier receipt or invoice so it stays with this purchase.',
                ),
                const SizedBox(height: 14),
                const ReceiptCaptureButtons(purpose: ReceiptPurpose.purchase),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payment', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: state.paymentMethod,
                  decoration: const InputDecoration(labelText: 'Payment method'),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'mobile_money', child: Text('Mobile money')),
                    DropdownMenuItem(value: 'bank_transfer', child: Text('Bank transfer')),
                    DropdownMenuItem(value: 'supplier_credit', child: Text('Supplier credit')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      context
                          .read<PurchaseDraftBloc>()
                          .add(PurchaseDraftPaymentMethodChanged(value));
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  enabled: state.paymentMethod != 'supplier_credit',
                  initialValue: ScaledDecimal.fromMinor(state.amountPaidMinor),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount paid now (M)'),
                  onChanged: (value) => context
                      .read<PurchaseDraftBloc>()
                      .add(PurchaseDraftAmountPaidChanged(value)),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: state.notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  onChanged: (value) => context
                      .read<PurchaseDraftBloc>()
                      .add(PurchaseDraftNotesChanged(value)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _SummaryRow(label: 'Purchase total', value: Loti.formatMinor(state.totalMinor)),
                const SizedBox(height: 8),
                _SummaryRow(label: 'Paid now', value: Loti.formatMinor(state.amountPaidMinor)),
                const Divider(height: 24),
                _SummaryRow(
                  label: 'Supplier balance',
                  value: Loti.formatMinor(state.balanceDueMinor < 0 ? 0 : state.balanceDueMinor),
                  bold: true,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.canSubmit
                        ? () => context
                            .read<PurchaseDraftBloc>()
                            .add(const PurchaseDraftSubmitted())
                        : null,
                    icon: state.status == PurchaseDraftStatus.submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      state.status == PurchaseDraftStatus.submitting
                          ? 'Saving...'
                          : 'Confirm Purchase',
                    ),
                  ),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 10),
                  Text(state.message!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}
