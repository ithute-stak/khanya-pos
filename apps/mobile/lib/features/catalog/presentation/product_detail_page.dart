import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/inventory/data/inventory_control_repository.dart';

class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key, required this.product});

  final ProductSummary product;

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  bool _loading = true;
  String? _error;
  ProductDetail? _detail;
  List<InventoryMovementSummary> _movements = const [];

  ProductRepository get _products => context.read<ProductRepository>();
  InventoryControlRepository get _inventory => context.read<InventoryControlRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detailFuture = _products.productDetail(widget.product.id);
      final movementFuture = _inventory.movements(productId: widget.product.id);
      final detail = await detailFuture;
      final movements = await movementFuture;
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _movements = movements;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Product details could not be loaded. Check the connection and try again.';
      });
    }
  }

  Future<void> _edit() async {
    final detail = _detail;
    if (detail == null) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EditProductPage(detail: detail),
      ),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.name ?? widget.product.name),
        actions: [
          if (detail != null)
            IconButton(
              tooltip: 'Edit product',
              onPressed: _loading ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _Failure(message: _error!, onRetry: _load)
                : detail == null
                    ? const Center(child: Text('Product not found.'))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final horizontal = constraints.maxWidth >= 900 ? 28.0 : 16.0;
                            return ListView(
                              padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 40),
                              children: [
                                _ProductHero(detail: detail),
                                const SizedBox(height: 16),
                                LayoutBuilder(
                                  builder: (context, inner) {
                                    final wide = inner.maxWidth >= 760;
                                    final overview = _OverviewCard(detail: detail);
                                    final pricing = _PricingStockCard(detail: detail);
                                    if (wide) {
                                      return Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(child: overview),
                                          const SizedBox(width: 12),
                                          Expanded(child: pricing),
                                        ],
                                      );
                                    }
                                    return Column(
                                      children: [
                                        overview,
                                        const SizedBox(height: 12),
                                        pricing,
                                      ],
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    const Icon(Icons.history),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Stock history',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                    Text('${_movements.length} movements'),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (_movements.isEmpty)
                                  const Card(
                                    child: Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Text('No stock movements recorded for this product yet.'),
                                    ),
                                  )
                                else
                                  for (final movement in _movements)
                                    _MovementCard(movement: movement),
                              ],
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

class _ProductHero extends StatelessWidget {
  const _ProductHero({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 30,
              child: const Icon(Icons.inventory_2_outlined, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'SKU ${detail.sku}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Badge(
                        icon: detail.isActive ? Icons.check_circle_outline : Icons.pause_circle_outline,
                        label: detail.isActive ? 'Active' : 'Inactive',
                      ),
                      if (detail.isLowStock)
                        const _Badge(
                          icon: Icons.warning_amber_rounded,
                          label: 'Low stock',
                          warning: true,
                        ),
                      if (detail.tracksStock)
                        const _Badge(
                          icon: Icons.track_changes,
                          label: 'Stock tracked',
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              Loti.formatMinor(detail.sellingPriceMinor),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Product information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Category', value: detail.categoryName ?? 'Not set'),
            _InfoRow(label: 'Brand', value: detail.brandName ?? 'Not set'),
            _InfoRow(label: 'Unit', value: detail.unitName ?? detail.unit),
            _InfoRow(label: 'Barcode', value: detail.barcode ?? 'Not set'),
          ],
        ),
      ),
    );
  }
}

class _PricingStockCard extends StatelessWidget {
  const _PricingStockCard({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context) {
    final stock = detail.onHandMilli == null
        ? 'Not available'
        : '${ScaledDecimal.fromMilli(detail.onHandMilli!)} ${detail.unit}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pricing & stock',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Selling price', value: Loti.formatMinor(detail.sellingPriceMinor)),
            _InfoRow(label: 'Cost price', value: Loti.formatMinor(detail.costPriceMinor)),
            _InfoRow(label: 'On hand', value: stock),
            _InfoRow(
              label: 'Reorder level',
              value: '${ScaledDecimal.fromMilli(detail.reorderLevelMilli)} ${detail.unit}',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.movement});

  final InventoryMovementSummary movement;

  @override
  Widget build(BuildContext context) {
    final positive = movement.quantityMilli >= 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Icon(positive ? Icons.add_rounded : Icons.remove_rounded),
        ),
        title: Text(_movementLabel(movement.movementType)),
        subtitle: Text(
          '${_formatDate(movement.occurredAt)}${movement.reason == null ? '' : ' • ${movement.reason}'}',
        ),
        trailing: Text(
          '${positive ? '+' : ''}${ScaledDecimal.fromMilli(movement.quantityMilli)}',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: positive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, this.warning = false});

  final IconData icon;
  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = warning ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final foreground = warning ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: foreground)),
        ],
      ),
    );
  }
}

class EditProductPage extends StatefulWidget {
  const EditProductPage({super.key, required this.detail});

  final ProductDetail detail;

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _sku;
  late final TextEditingController _barcode;
  late final TextEditingController _unit;
  late final TextEditingController _sellingPrice;
  late final TextEditingController _costPrice;
  late final TextEditingController _reorderLevel;

  List<CatalogMasterItem> _categories = const [];
  List<CatalogMasterItem> _brands = const [];
  List<CatalogMasterItem> _units = const [];
  late String _categoryId;
  late String _brandId;
  late String _unitId;
  late bool _trackStock;
  late bool _isActive;
  bool _loadingMasters = true;
  bool _saving = false;
  String? _error;

  ProductRepository get _repository => context.read<ProductRepository>();

  @override
  void initState() {
    super.initState();
    final detail = widget.detail;
    _name = TextEditingController(text: detail.name);
    _sku = TextEditingController(text: detail.sku);
    _barcode = TextEditingController(text: detail.barcode ?? '');
    _unit = TextEditingController(text: detail.unit);
    _sellingPrice = TextEditingController(text: ScaledDecimal.fromMinor(detail.sellingPriceMinor));
    _costPrice = TextEditingController(text: ScaledDecimal.fromMinor(detail.costPriceMinor));
    _reorderLevel = TextEditingController(text: ScaledDecimal.fromMilli(detail.reorderLevelMilli));
    _categoryId = detail.categoryId ?? '';
    _brandId = detail.brandId ?? '';
    _unitId = detail.unitId ?? '';
    _trackStock = detail.tracksStock;
    _isActive = detail.isActive;
    _loadMasters();
  }

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

  Future<void> _loadMasters() async {
    try {
      final results = await Future.wait([
        _repository.categories(),
        _repository.brands(),
        _repository.units(),
      ]);
      if (!mounted) return;
      setState(() {
        _categories = results[0];
        _brands = results[1];
        _units = results[2];
        _loadingMasters = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMasters = false;
        _error = 'Catalog lists could not be loaded. You can still edit the existing text fields.';
      });
    }
  }

  String? _required(String? value, String label) {
    if ((value?.trim() ?? '').isEmpty) return '$label is required.';
    return null;
  }

  String? _nonNegative(String? value, String label) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Enter a valid $label.';
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.updateProduct(
        productId: widget.detail.id,
        name: _name.text,
        sku: _sku.text,
        barcode: _barcode.text,
        categoryId: _categoryId.isEmpty ? null : _categoryId,
        brandId: _brandId.isEmpty ? null : _brandId,
        unitId: _unitId.isEmpty ? null : _unitId,
        unit: _unit.text,
        sellingPrice: _sellingPrice.text,
        costPrice: _costPrice.text,
        reorderLevel: _reorderLevel.text,
        trackStock: _trackStock,
        isActive: _isActive,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Product could not be updated. Check the values, connection, SKU and barcode.';
      });
    }
  }

  void _applyUnit(String value) {
    setState(() => _unitId = value);
    if (value.isEmpty) return;
    for (final unit in _units) {
      if (unit.id == value) {
        _unit.text = unit.name;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit product')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760 ? 28.0 : 16.0;
            return Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 100),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Product details',
                            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Update identification, classification, pricing and stock rules.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Product name',
                              prefixIcon: Icon(Icons.inventory_2_outlined),
                            ),
                            validator: (value) => _required(value, 'Product name'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _sku,
                            textCapitalization: TextCapitalization.characters,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'SKU',
                              prefixIcon: Icon(Icons.tag_outlined),
                            ),
                            validator: (value) => _required(value, 'SKU'),
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _barcode,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Barcode (optional)',
                              prefixIcon: Icon(Icons.qr_code_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingMasters)
                            const LinearProgressIndicator()
                          else ...[
                            DropdownButtonFormField<String>(
                              initialValue: _categoryId,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                                prefixIcon: Icon(Icons.category_outlined),
                              ),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('No category')),
                                ..._categories.map(
                                  (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
                                ),
                              ],
                              onChanged: _saving ? null : (value) => setState(() => _categoryId = value ?? ''),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _brandId,
                              decoration: const InputDecoration(
                                labelText: 'Brand',
                                prefixIcon: Icon(Icons.sell_outlined),
                              ),
                              items: [
                                const DropdownMenuItem(value: '', child: Text('No brand')),
                                ..._brands.map(
                                  (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
                                ),
                              ],
                              onChanged: _saving ? null : (value) => setState(() => _brandId = value ?? ''),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _unitId,
                              decoration: const InputDecoration(
                                labelText: 'Saved unit',
                                prefixIcon: Icon(Icons.straighten_outlined),
                              ),
                              items: [
                                DropdownMenuItem(value: '', child: Text('Manual: ${_unit.text}')),
                                ..._units.map(
                                  (item) => DropdownMenuItem(value: item.id, child: Text(item.name)),
                                ),
                              ],
                              onChanged: _saving ? null : (value) => _applyUnit(value ?? ''),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _unit,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Unit',
                              prefixIcon: Icon(Icons.straighten_outlined),
                            ),
                            validator: (value) => _required(value, 'Unit'),
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, inner) {
                              final stacked = inner.maxWidth < 560;
                              final sell = TextFormField(
                                controller: _sellingPrice,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Selling price (M)'),
                                validator: (value) => _nonNegative(value, 'selling price'),
                              );
                              final cost = TextFormField(
                                controller: _costPrice,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(labelText: 'Cost price (M)'),
                                validator: (value) => _nonNegative(value, 'cost price'),
                              );
                              if (stacked) {
                                return Column(children: [sell, const SizedBox(height: 12), cost]);
                              }
                              return Row(
                                children: [
                                  Expanded(child: sell),
                                  const SizedBox(width: 12),
                                  Expanded(child: cost),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _reorderLevel,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Reorder level'),
                            validator: (value) => _nonNegative(value, 'reorder level'),
                          ),
                          const SizedBox(height: 10),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Track stock'),
                            subtitle: const Text('Maintain quantities and low-stock warnings for this product.'),
                            value: _trackStock,
                            onChanged: _saving ? null : (value) => setState(() => _trackStock = value),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Active product'),
                            subtitle: const Text('Inactive products are hidden from the selling catalogue.'),
                            value: _isActive,
                            onChanged: _saving ? null : (value) => setState(() => _isActive = value),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Card(
                              color: theme.colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Saving…' : 'Save changes'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
}

String _movementLabel(String type) => switch (type) {
      'transfer_in' => 'Transfer in',
      'transfer_out' => 'Transfer out',
      'stocktake_gain' => 'Stocktake gain',
      'stocktake_loss' => 'Stocktake loss',
      'damage' => 'Damaged stock',
      'expiry' => 'Expired stock',
      'sale' => 'Sale',
      'sale_return' => 'Sales return',
      'opening_balance' => 'Opening balance',
      'correction' => 'Correction',
      _ => type.replaceAll('_', ' '),
    };

String _formatDate(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
