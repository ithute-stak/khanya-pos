import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/inventory/presentation/bloc/inventory_bloc.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => InventoryBloc(context.read<ProductRepository>())..add(const InventoryStarted()),
      child: const _InventoryView(),
    );
  }
}

class _InventoryView extends StatelessWidget {
  const _InventoryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Stocktake, transfers and movement history',
            onPressed: () => context.push('/inventory/controls'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Refresh inventory',
            onPressed: () => context.read<InventoryBloc>().add(const InventoryRefreshRequested()),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: BlocBuilder<InventoryBloc, InventoryState>(
        builder: (context, state) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        label: 'Products',
                        value: state.products.length.toString(),
                        icon: Icons.inventory_2_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _MetricCard(
                        label: 'Low stock',
                        value: state.lowStockCount.toString(),
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      label: const Text('Low stock only'),
                      selected: state.showLowStockOnly,
                      onSelected: (value) => context.read<InventoryBloc>().add(InventoryLowStockFilterChanged(value)),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push('/inventory/controls'),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Stock controls'),
                    ),
                    if (state.isRefreshing) ...[
                      const SizedBox(width: 12),
                      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ],
                ),
              ),
              if (state.lastError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(state.lastError!, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: state.visibleProducts.isEmpty
                    ? const Center(child: Text('No inventory rows to show.'))
                    : LayoutBuilder(
                        builder: (context, constraints) => GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: constraints.maxWidth >= 900 ? 430 : 520,
                            mainAxisExtent: 150,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: state.visibleProducts.length,
                          itemBuilder: (context, index) => _StockCard(product: state.visibleProducts[index]),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(label)),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final onHand = product.onHandMilli == null ? '—' : ScaledDecimal.fromMilli(product.onHandMilli!);
    final reorder = ScaledDecimal.fromMilli(product.reorderLevelMilli);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: product.isLowStock
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Icon(product.isLowStock ? Icons.warning_amber_rounded : Icons.inventory_2_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('${product.sku} • Reorder at $reorder ${product.unit}', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(onHand, style: Theme.of(context).textTheme.headlineSmall),
                Text(product.unit, style: Theme.of(context).textTheme.bodySmall),
                if (product.isLowStock)
                  Text('LOW', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.error)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
