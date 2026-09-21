import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/catalog/presentation/bloc/product_catalog_bloc.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProductCatalogBloc(context.read<ProductRepository>())
        ..add(const ProductCatalogStarted()),
      child: const _ProductsView(),
    );
  }
}

class _ProductsView extends StatelessWidget {
  const _ProductsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          BlocBuilder<ProductCatalogBloc, ProductCatalogState>(
            buildWhen: (previous, current) => previous.isRefreshing != current.isRefreshing,
            builder: (context, state) => IconButton(
              tooltip: 'Refresh products',
              onPressed: state.isRefreshing
                  ? null
                  : () => context.read<ProductCatalogBloc>().add(const ProductCatalogRefreshRequested()),
              icon: state.isRefreshing
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
      body: BlocBuilder<ProductCatalogBloc, ProductCatalogState>(
        builder: (context, state) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: TextField(
                  onChanged: (value) => context.read<ProductCatalogBloc>().add(ProductCatalogQueryChanged(value)),
                  decoration: const InputDecoration(
                    hintText: 'Search product, SKU or barcode',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              if (state.lastError != null)
                _OfflineBanner(message: state.lastError!),
              Expanded(
                child: state.visibleProducts.isEmpty
                    ? _EmptyProducts(refreshing: state.isRefreshing)
                    : RefreshIndicator(
                        onRefresh: () async {
                          context.read<ProductCatalogBloc>().add(const ProductCatalogRefreshRequested());
                        },
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: constraints.maxWidth >= 900 ? 300 : 240,
                                mainAxisExtent: 178,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: state.visibleProducts.length,
                              itemBuilder: (context, index) => _ProductCard(product: state.visibleProducts[index]),
                            );
                          },
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

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final stockText = product.onHandMilli == null
        ? 'Stock not tracked'
        : '${ScaledDecimal.fromMilli(product.onHandMilli!)} ${product.unit}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(Icons.inventory_2_outlined),
                  ),
                ),
                const Spacer(),
                if (product.isLowStock)
                  const Chip(label: Text('Low stock'), visualDensity: VisualDensity.compact),
              ],
            ),
            const SizedBox(height: 12),
            Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 3),
            Text(product.sku, style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            Row(
              children: [
                Expanded(child: Text(stockText, style: Theme.of(context).textTheme.bodySmall)),
                Text(Loti.formatMinor(product.sellingPriceMinor), style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [const Icon(Icons.cloud_off_outlined, size: 18), const SizedBox(width: 8), Expanded(child: Text(message))]),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.refreshing});
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refreshing) const CircularProgressIndicator() else const Icon(Icons.inventory_2_outlined, size: 52),
            const SizedBox(height: 14),
            Text(refreshing ? 'Loading products…' : 'No products yet', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}
