import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/purchasing/data/purchasing_repository.dart';
import 'package:khanya_pos/features/purchasing/presentation/bloc/purchases_bloc.dart';

class PurchasesPage extends StatelessWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PurchasesBloc(repository: context.read<PurchasingRepository>())
        ..add(const PurchasesRequested()),
      child: const _PurchasesView(),
    );
  }
}

class _PurchasesView extends StatelessWidget {
  const _PurchasesView();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PurchasesBloc>().state;
    final outstanding = state.items.fold<int>(0, (total, item) => total + item.balanceDueMinor);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          IconButton(
            tooltip: 'Receipt Vault',
            onPressed: () => context.push('/receipts'),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          IconButton(
            tooltip: 'Suppliers',
            onPressed: () => context.push('/suppliers'),
            icon: const Icon(Icons.local_shipping_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/purchases/new');
          if (context.mounted) context.read<PurchasesBloc>().add(const PurchasesRequested());
        },
        icon: const Icon(Icons.add),
        label: const Text('New Purchase'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = constraints.maxWidth >= 700 ? 28.0 : 16.0;
          return RefreshIndicator(
            onRefresh: () async {
              context.read<PurchasesBloc>().add(const PurchasesRequested());
              await context.read<PurchasesBloc>().stream.firstWhere((value) => !value.loading);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 100),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(label: 'Purchases', value: '${state.items.length}'),
                    _MetricCard(label: 'Supplier balance', value: Loti.formatMinor(outstanding)),
                  ],
                ),
                const SizedBox(height: 18),
                if (state.loading) const LinearProgressIndicator(),
                if (state.message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(state.message!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (!state.loading && state.items.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No stock purchases have been recorded yet.'),
                    ),
                  )
                else
                  ...state.items.map(
                    (purchase) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            purchase.balanceDueMinor > 0 ? Icons.schedule_outlined : Icons.check,
                          ),
                        ),
                        title: Text(purchase.purchaseNumber),
                        subtitle: Text(
                          '${purchase.supplierInvoiceNumber ?? 'No supplier invoice'} • '
                          '${purchase.purchaseDate.toLocal().toString().substring(0, 10)}\n'
                          '${purchase.status.replaceAll('_', ' ')}',
                        ),
                        isThreeLine: true,
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Loti.formatMinor(purchase.totalMinor), style: const TextStyle(fontWeight: FontWeight.w700)),
                            if (purchase.balanceDueMinor > 0)
                              Text('Owes ${Loti.formatMinor(purchase.balanceDueMinor)}', style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
        ),
      ),
    );
  }
}
