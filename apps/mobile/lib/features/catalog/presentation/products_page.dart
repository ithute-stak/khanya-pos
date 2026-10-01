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

enum _ProductFilter { all, lowStock, tracked }

class _ProductsView extends StatefulWidget {
  const _ProductsView();

  @override
  State<_ProductsView> createState() => _ProductsViewState();
}

class _ProductsViewState extends State<_ProductsView> {
  _ProductFilter _filter = _ProductFilter.all;

  List<ProductSummary> _filteredProducts(ProductCatalogState state) {
    final products = state.visibleProducts;
    switch (_filter) {
      case _ProductFilter.all:
        return products;
      case _ProductFilter.lowStock:
        return products.where((product) => product.isLowStock).toList(growable: false);
      case _ProductFilter.tracked:
        return products.where((product) => product.tracksStock).toList(growable: false);
    }
  }

  Future<void> _showAddProduct(BuildContext context) async {
    final repository = context.read<ProductRepository>();
    final width = MediaQuery.sizeOf(context).width;
    final created = width < 700
        ? await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            showDragHandle: true,
            builder: (_) => _AddProductForm(repository: repository, asSheet: true),
          )
        : await showDialog<bool>(
            context: context,
            builder: (_) => Dialog(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 660),
                child: _AddProductForm(repository: repository),
              ),
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
      floatingActionButton: MediaQuery.sizeOf(context).width < 700
          ? FloatingActionButton.extended(
              onPressed: () => _showAddProduct(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add product'),
            )
          : null,
      body: SafeArea(
        child: BlocBuilder<ProductCatalogBloc, ProductCatalogState>(
          builder: (context, state) {
            final products = _filteredProducts(state);
            final total = state.products.length;
            final lowStock = state.products.where((product) => product.isLowStock).length;
            final tracked = state.products.where((product) => product.tracksStock).length;

            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                return Column(
                  children: [
                    _ProductsHeader(
                      compact: compact,
                      total: total,
                      lowStock: lowStock,
                      tracked: tracked,
                      refreshing: state.isRefreshing,
                      onAdd: () => _showAddProduct(context),
                      onRefresh: () => context
                          .read<ProductCatalogBloc>()
                          .add(const ProductCatalogRefreshRequested()),
                    ),
                    _ProductsToolbar(
                      filter: _filter,
                      onFilterChanged: (value) => setState(() => _filter = value),
                      onQueryChanged: (value) => context
                          .read<ProductCatalogBloc>()
                          .add(ProductCatalogQueryChanged(value)),
                    ),
                    if (state.lastError != null) _OfflineBanner(message: state.lastError!),
                    Expanded(
                      child: products.isEmpty
                          ? _EmptyProducts(
                              refreshing: state.isRefreshing,
                              filtered: state.products.isNotEmpty,
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                context
                                    .read<ProductCatalogBloc>()
                                    .add(const ProductCatalogRefreshRequested());
                              },
                              child: compact
                                  ? ListView.separated(
                                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 96),
                                      itemCount: products.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                                      itemBuilder: (_, index) =>
                                          _MobileProductCard(product: products[index]),
                                    )
                                  : GridView.builder(
                                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                        maxCrossAxisExtent: constraints.maxWidth >= 1200 ? 360 : 320,
                                        mainAxisExtent: 216,
                                        crossAxisSpacing: 14,
                                        mainAxisSpacing: 14,
                                      ),
                                      itemCount: products.length,
                                      itemBuilder: (_, index) =>
                                          _DesktopProductCard(product: products[index]),
                                    ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ProductsHeader extends StatelessWidget {
  const _ProductsHeader({
    required this.compact,
    required this.total,
    required this.lowStock,
    required this.tracked,
    required this.refreshing,
    required this.onAdd,
    required this.onRefresh,
  });

  final bool compact;
  final int total;
  final int lowStock;
  final int tracked;
  final bool refreshing;
  final VoidCallback onAdd;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Products', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your catalogue, pricing and stock visibility.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Refresh products',
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
            if (!compact) ...[
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add product'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _MetricPill(icon: Icons.inventory_2_outlined, label: 'Products', value: '$total'),
              const SizedBox(width: 8),
              _MetricPill(icon: Icons.warning_amber_rounded, label: 'Low stock', value: '$lowStock'),
              const SizedBox(width: 8),
              _MetricPill(icon: Icons.track_changes_rounded, label: 'Stock tracked', value: '$tracked'),
            ],
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 18, compact ? 16 : 22, 8),
      child: content,
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 7),
          Text('$label  ', style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _ProductsToolbar extends StatelessWidget {
  const _ProductsToolbar({
    required this.filter,
    required this.onFilterChanged,
    required this.onQueryChanged,
  });

  final _ProductFilter filter;
  final ValueChanged<_ProductFilter> onFilterChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final search = TextField(
          onChanged: onQueryChanged,
          decoration: InputDecoration(
            hintText: 'Search name, SKU or barcode',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        );
        final filters = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: filter == _ProductFilter.all,
                onTap: () => onFilterChanged(_ProductFilter.all),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Low stock',
                selected: filter == _ProductFilter.lowStock,
                onTap: () => onFilterChanged(_ProductFilter.lowStock),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: 'Tracked stock',
                selected: filter == _ProductFilter.tracked,
                onTap: () => onFilterChanged(_ProductFilter.tracked),
              ),
            ],
          ),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 6, compact ? 16 : 22, 8),
          child: compact
              ? Column(
                  children: [
                    search,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: filters),
                  ],
                )
              : Row(
                  children: [
                    Expanded(flex: 3, child: search),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: Align(alignment: Alignment.centerRight, child: filters)),
                  ],
                ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
    );
  }
}

class _MobileProductCard extends StatelessWidget {
  const _MobileProductCard({required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockText = product.onHandMilli == null
        ? 'Stock not tracked'
        : '${ScaledDecimal.fromMilli(product.onHandMilli!)} ${product.unit} on hand';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        Loti.formatMinor(product.sellingPriceMinor),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('SKU ${product.sku}', style: theme.textTheme.bodySmall),
                  if ((product.barcode ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Barcode ${product.barcode}', style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusBadge(
                        icon: product.tracksStock ? Icons.inventory_outlined : Icons.inventory_2_outlined,
                        text: stockText,
                      ),
                      if (product.isLowStock)
                        const _StatusBadge(
                          icon: Icons.warning_amber_rounded,
                          text: 'Low stock',
                          warning: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopProductCard extends StatelessWidget {
  const _DesktopProductCard({required this.product});
  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stockText = product.onHandMilli == null
        ? 'Not tracked'
        : '${ScaledDecimal.fromMilli(product.onHandMilli!)} ${product.unit}';

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.inventory_2_outlined, color: theme.colorScheme.onPrimaryContainer),
                ),
                const Spacer(),
                if (product.isLowStock)
                  const _StatusBadge(
                    icon: Icons.warning_amber_rounded,
                    text: 'Low stock',
                    warning: true,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('SKU ${product.sku}', style: theme.textTheme.bodySmall),
            if ((product.barcode ?? '').isNotEmpty)
              Text('Barcode ${product.barcode}', style: theme.textTheme.bodySmall),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stock', style: theme.textTheme.labelSmall),
                      const SizedBox(height: 2),
                      Text(stockText, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Selling price', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      Loti.formatMinor(product.sellingPriceMinor),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.icon,
    required this.text,
    this.warning = false,
  });

  final IconData icon;
  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = warning
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground = warning
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: foreground),
          const SizedBox(width: 5),
          Text(text, style: theme.textTheme.labelSmall?.copyWith(color: foreground)),
        ],
      ),
    );
  }
}

class _AddProductForm extends StatefulWidget {
  const _AddProductForm({required this.repository, this.asSheet = false});

  final ProductRepository repository;
  final bool asSheet;

  @override
  State<_AddProductForm> createState() => _AddProductFormState();
}

class _AddProductFormState extends State<_AddProductForm> {
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
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to add product. Check the details, connection, and that the SKU/barcode is unique.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, widget.asSheet ? 0 : 20, 20, 20 + keyboardInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Add product', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(
                          'Create a product for this business catalogue.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.asSheet)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
                validator: (value) => _requiredText(value, 'Product name', minLength: 2),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => _ResponsiveFields(
                  compact: constraints.maxWidth < 520,
                  left: TextFormField(
                    controller: _sku,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'SKU'),
                    validator: (value) => _requiredText(value, 'SKU'),
                  ),
                  right: TextFormField(
                    controller: _barcode,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Barcode (optional)'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => _ResponsiveFields(
                  compact: constraints.maxWidth < 520,
                  left: TextFormField(
                    controller: _unit,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Unit'),
                    validator: (value) => _requiredText(value, 'Unit'),
                  ),
                  right: TextFormField(
                    controller: _sellingPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Selling price (M)'),
                    validator: (value) => _nonNegativeNumber(value, 'selling price'),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) => _ResponsiveFields(
                  compact: constraints.maxWidth < 520,
                  left: TextFormField(
                    controller: _costPrice,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Cost price (M)'),
                    validator: (value) => _nonNegativeNumber(value, 'cost price'),
                  ),
                  right: TextFormField(
                    controller: _reorderLevel,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _save(),
                    decoration: const InputDecoration(labelText: 'Reorder level'),
                    validator: (value) => _nonNegativeNumber(value, 'reorder level'),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Track stock'),
                subtitle: const Text('Show on-hand quantity and low-stock warnings for this product.'),
                value: _trackStock,
                onChanged: _saving ? null : (value) => setState(() => _trackStock = value),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_saving ? 'Saving...' : 'Save product'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({
    required this.compact,
    required this.left,
    required this.right,
  });

  final bool compact;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        children: [
          left,
          const SizedBox(height: 12),
          right,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _EmptyProducts extends StatelessWidget {
  const _EmptyProducts({required this.refreshing, required this.filtered});
  final bool refreshing;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refreshing)
              const CircularProgressIndicator()
            else
              Icon(
                filtered ? Icons.filter_alt_off_outlined : Icons.inventory_2_outlined,
                size: 54,
              ),
            const SizedBox(height: 14),
            Text(
              refreshing
                  ? 'Loading products…'
                  : filtered
                      ? 'No products match this view'
                      : 'No products yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            if (!refreshing) ...[
              const SizedBox(height: 7),
              Text(
                filtered
                    ? 'Try another search or filter.'
                    : 'Use “Add product” to create your first catalogue item.',
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
