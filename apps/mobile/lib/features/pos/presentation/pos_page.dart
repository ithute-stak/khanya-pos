import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/catalog/presentation/bloc/product_catalog_bloc.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/cart_bloc.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/checkout_bloc.dart';

class PosPage extends StatelessWidget {
  const PosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ProductCatalogBloc(context.read<ProductRepository>())
            ..add(const ProductCatalogStarted()),
        ),
        BlocProvider(create: (_) => CartBloc()),
        BlocProvider(create: (_) => CheckoutBloc(context.read<SalesRepository>())),
      ],
      child: const _PosView(),
    );
  }
}

class _PosView extends StatelessWidget {
  const _PosView();

  @override
  Widget build(BuildContext context) {
    return BlocListener<CheckoutBloc, CheckoutState>(
      listener: (context, state) {
        if (state.status == CheckoutStatus.completed && state.submission != null) {
          context.read<CartBloc>().add(const CartCleared());
          context.read<SyncBloc>().add(const SyncRequested());
          final status = state.submission!.status;
          final message = switch (status) {
            SaleSubmissionStatus.synced => 'Sale completed and synced.',
            SaleSubmissionStatus.queued => 'Sale saved offline and queued for sync.',
            SaleSubmissionStatus.conflict => 'Sale saved locally but needs sync review.',
          };
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        } else if (state.status == CheckoutStatus.failed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.errorMessage ?? 'Sale failed.')),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New Sale'),
          actions: [
            BlocBuilder<SyncBloc, SyncStatusState>(
              builder: (context, state) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Badge(
                    isLabelVisible: state.pendingCount > 0,
                    label: Text(state.pendingCount.toString()),
                    child: Icon(state.isSyncing ? Icons.sync : Icons.cloud_sync_outlined),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 900) {
              return Row(
                children: [
                  const Expanded(flex: 3, child: _ProductBrowser()),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 400, child: _CartPanel(closeOnComplete: false)),
                ],
              );
            }
            return const Column(
              children: [
                Expanded(child: _ProductBrowser()),
                _MobileCartBar(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductBrowser extends StatelessWidget {
  const _ProductBrowser();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductCatalogBloc, ProductCatalogState>(
      builder: (context, state) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(
                onChanged: (value) => context.read<ProductCatalogBloc>().add(ProductCatalogQueryChanged(value)),
                decoration: const InputDecoration(
                  hintText: 'Scan barcode or search product',
                  prefixIcon: Icon(Icons.qr_code_scanner),
                  suffixIcon: Icon(Icons.search),
                ),
              ),
            ),
            if (state.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(state.lastError!, style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
            Expanded(
              child: state.visibleProducts.isEmpty
                  ? Center(
                      child: state.isRefreshing
                          ? const CircularProgressIndicator()
                          : const Text('No products available. Add or sync products first.'),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return GridView.builder(
                          padding: const EdgeInsets.all(14),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: constraints.maxWidth >= 700 ? 220 : 190,
                            mainAxisExtent: 176,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                          ),
                          itemCount: state.visibleProducts.length,
                          itemBuilder: (context, index) => _SellableProductCard(product: state.visibleProducts[index]),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SellableProductCard extends StatelessWidget {
  const _SellableProductCard({required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final available = product.tracksStock ? product.availableWholeUnits : null;
    final soldOut = available != null && available <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: soldOut
            ? null
            : () => context.read<CartBloc>().add(CartProductAdded(product.toPosProduct())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: soldOut ? Colors.grey : Theme.of(context).colorScheme.primary),
                  const Spacer(),
                  if (soldOut)
                    const Chip(label: Text('Out'), visualDensity: VisualDensity.compact)
                  else if (product.isLowStock)
                    const Chip(label: Text('Low'), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 10),
              Text(product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(product.sku, style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(Loti.formatMinor(product.sellingPriceMinor), style: Theme.of(context).textTheme.titleMedium),
              Text(
                available == null ? 'Stock not tracked' : '$available available',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartBloc, CartState>(
      builder: (context, state) => SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${state.itemCount} item${state.itemCount == 1 ? '' : 's'}'),
                      Text(Loti.formatMinor(state.totalMinor), style: Theme.of(context).textTheme.titleLarge),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: state.lines.isEmpty ? null : () => _showCart(context),
                  icon: const Icon(Icons.shopping_cart_checkout),
                  label: const Text('Review'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCart(BuildContext context) {
    final cartBloc = context.read<CartBloc>();
    final checkoutBloc = context.read<CheckoutBloc>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cartBloc),
          BlocProvider.value(value: checkoutBloc),
        ],
        child: const FractionallySizedBox(
          heightFactor: 0.88,
          child: _CartPanel(closeOnComplete: true),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.closeOnComplete});
  final bool closeOnComplete;

  @override
  Widget build(BuildContext context) {
    return BlocListener<CheckoutBloc, CheckoutState>(
      listener: (context, state) {
        if (closeOnComplete && state.status == CheckoutStatus.completed && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Cart', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                BlocBuilder<CartBloc, CartState>(
                  builder: (context, state) => TextButton(
                    onPressed: state.lines.isEmpty ? null : () => context.read<CartBloc>().add(const CartCleared()),
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: BlocBuilder<CartBloc, CartState>(
                builder: (context, state) {
                  if (state.lines.isEmpty) {
                    return const Center(child: Text('Scan or tap a product to start a sale.'));
                  }
                  return ListView.separated(
                    itemCount: state.lines.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = state.lines[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(line.product.name),
                        subtitle: Text(Loti.formatMinor(line.lineTotalMinor)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => context.read<CartBloc>().add(
                                    CartQuantityChanged(productId: line.product.id, quantity: line.quantity - 1),
                                  ),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(line.quantity.toString(), style: Theme.of(context).textTheme.titleMedium),
                            IconButton(
                              onPressed: () => context.read<CartBloc>().add(
                                    CartQuantityChanged(productId: line.product.id, quantity: line.quantity + 1),
                                  ),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CartBloc, CartState>(
              builder: (context, state) => DropdownButtonFormField<PaymentMethod>(
                initialValue: state.paymentMethod,
                decoration: const InputDecoration(labelText: 'Payment method'),
                items: [
                  for (final method in PaymentMethod.values)
                    DropdownMenuItem(value: method, child: Text(method.label)),
                ],
                onChanged: (method) {
                  if (method != null) context.read<CartBloc>().add(CartPaymentMethodChanged(method));
                },
              ),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CartBloc, CartState>(
              builder: (context, cart) => BlocBuilder<CheckoutBloc, CheckoutState>(
                builder: (context, checkout) {
                  final submitting = checkout.status == CheckoutStatus.submitting;
                  return FilledButton.icon(
                    onPressed: cart.lines.isEmpty || submitting
                        ? null
                        : () => context.read<CheckoutBloc>().add(
                              CheckoutSaleRequested(
                                lines: List<CartLine>.unmodifiable(cart.lines),
                                paymentMethod: cart.paymentMethod,
                              ),
                            ),
                    icon: submitting
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline),
                    label: Text(submitting ? 'Saving sale…' : 'Pay ${Loti.formatMinor(cart.totalMinor)}'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
