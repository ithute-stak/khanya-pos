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

  Future<void> _showAddProductDialog(BuildContext context) async {
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AddProductDialog(
        repository: context.read<ProductRepository>(),
      ),
    );

    if (created == true && context.mounted) {
      context.read<ProductCatalogBloc>().add(const ProductCatalogRefreshRequested());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product added successfully.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            tooltip: 'Add product',
            onPressed: () => _showAddProductDialog(context),
            icon: const Icon(Icons.add_box_outlined),
          ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProductDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add product'),
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

class _AddProductDialog extends StatefulWidget {
  const _AddProductDialog({required this.repository});

  final ProductRepository repository;

  @override
  State<_AddProductDialog> createState() => _AddProductDialogState();
}

class _AddProductDialogState extends State<_AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _sku = TextEditingController();
  final _barcode = TextEditingController();
  final _unit = TextEditingController(text: 'unit');
  final _sellingPrice = TextEditingController();
  final _costPrice = TextEditingController(text: '0.00');
  final _reorderLevel = TextEditingController(text: '0');
  bool _trackStock = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _sku.dispose();
    _barcode.dispose();
    _unit.dispose();
    _sellingPrice.dispose();
    _costPrice.dispose();
    _reorderLevel.dispose();
    super.dispose();
  }

  String? _requiredText(String? value, String label, {int minLength = 1}) {
    final text = value?.trim() ?? '';
    if (text.length < minLength) return '$label is required';
    return null;
  }

  String? _nonNegativeNumber(String? value, String label) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Enter a valid $label';
    if (parsed < 0) return '$label cannot be negative';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.repository.createProduct(
        name: _name.text,
        sku: _sku.text,
        barcode: _barcode.text,
        unit: _unit.text,
        sellingPrice: _sellingPrice.text,
        costPrice: _costPrice.text,
        reorderLevel: _reorderLevel.text,
        trackStock: _trackStock,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to add product. Check the details, connection, and that the SKU/barcode is unique.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add product'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Product name'),
                  validator: (value) => _requiredText(value, 'Product name', minLength: 2),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sku,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'SKU'),
                  validator: (value) => _requiredText(value, 'SKU'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _barcode,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Barcode (optional)'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _unit,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        validator: (value) => _requiredText(value, 'Unit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _sellingPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Selling price (M)'),
                        validator: (value) => _nonNegativeNumber(value, 'selling price'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _costPrice,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Cost price (M)'),
                        validator: (value) => _nonNegativeNumber(value, 'cost price'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderLevel,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _save(),
                        decoration: const InputDecoration(labelText: 'Reorder level'),
                        validator: (value) => _nonNegativeNumber(value, 'reorder level'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Track stock for this product'),
                  value: _trackStock,
                  onChanged: _saving ? null : (value) => setState(() => _trackStock = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ],
            ),
          ),
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
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Saving...' : 'Save product'),
        ),
      ],
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
            if (!refreshing) ...[
              const SizedBox(height: 8),
              const Text('Use “Add product” to create the first product.'),
            ],
          ],
        ),
      ),
    );
  }
}
