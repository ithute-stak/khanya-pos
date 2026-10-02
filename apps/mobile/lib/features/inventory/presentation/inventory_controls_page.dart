import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/inventory/data/inventory_control_repository.dart';

class InventoryControlsPage extends StatefulWidget {
  const InventoryControlsPage({super.key});

  @override
  State<InventoryControlsPage> createState() => _InventoryControlsPageState();
}

class _InventoryControlsPageState extends State<InventoryControlsPage> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  List<ProductSummary> _products = const [];
  List<InventoryBranch> _branches = const [];
  List<InventoryMovementSummary> _movements = const [];

  InventoryControlRepository get _controls => context.read<InventoryControlRepository>();
  ProductRepository get _productsRepository => context.read<ProductRepository>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      try {
        await _productsRepository.refresh();
      } catch (_) {
        // The saved catalogue remains usable when connectivity is unavailable.
      }
      final products = (await _productsRepository.cachedCurrentCatalog())
          .where((product) => product.tracksStock)
          .toList(growable: false);
      final branches = await _controls.branches();
      final movements = await _controls.movements();
      if (!mounted) return;
      setState(() {
        _products = products;
        _branches = branches;
        _movements = movements;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Advanced inventory controls require an online connection. ${error.toString()}';
      });
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success)));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Inventory operation failed: $error')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openTransfer() async {
    final result = await Navigator.of(context).push<_TransferDraft>(
      MaterialPageRoute(
        builder: (_) => TransferStockPage(products: _products, branches: _branches),
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _controls.transfer(
        destinationBranchId: result.destinationBranchId,
        reason: result.reason,
        reference: result.reference,
        productQuantitiesMilli: {result.product.id: result.quantityMilli},
      ),
      'Stock transferred successfully.',
    );
  }

  Future<void> _openStocktake() async {
    final result = await Navigator.of(context).push<_CountDraft>(
      MaterialPageRoute(
        builder: (_) => StocktakePage(products: _products),
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _controls.stocktake(
        reason: result.reason,
        reference: result.reference,
        countedQuantitiesMilli: {result.product.id: result.quantityMilli},
      ),
      'Physical count posted and inventory reconciled.',
    );
  }

  Future<void> _openWriteOff() async {
    final result = await Navigator.of(context).push<_WriteOffDraft>(
      MaterialPageRoute(
        builder: (_) => WriteOffStockPage(products: _products),
      ),
    );
    if (result == null || !mounted) return;
    await _run(
      () => _controls.adjust(
        productId: result.product.id,
        quantityDeltaMilli: -result.quantityMilli,
        adjustmentType: result.type,
        reason: result.reason,
      ),
      result.type == 'damage' ? 'Damaged stock written off.' : 'Expired stock written off.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Controls'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _submitting ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _FailureView(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _InventoryHero(productCount: _products.length, movementCount: _movements.length),
                      const SizedBox(height: 16),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >= 760;
                          final cards = [
                            _ActionCard(
                              title: 'Transfer Stock',
                              description: 'Move available stock from this branch to another branch without changing the business inventory GL.',
                              icon: Icons.swap_horiz_rounded,
                              onTap: _submitting ? null : _openTransfer,
                            ),
                            _ActionCard(
                              title: 'Physical Stocktake',
                              description: 'Post a counted quantity, preserve the variance and create the required gain/loss accounting entry.',
                              icon: Icons.fact_check_outlined,
                              onTap: _submitting ? null : _openStocktake,
                            ),
                            _ActionCard(
                              title: 'Damage / Expiry',
                              description: 'Write unusable stock out of inventory with a reason and immutable movement trail.',
                              icon: Icons.delete_sweep_outlined,
                              onTap: _submitting ? null : _openWriteOff,
                            ),
                          ];
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < cards.length; i++) ...[
                                      Expanded(child: cards[i]),
                                      if (i < cards.length - 1) const SizedBox(width: 12),
                                    ],
                                  ],
                                )
                              : Column(
                                  children: [
                                    for (final card in cards) ...[card, const SizedBox(height: 10)],
                                  ],
                                );
                        },
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Recent stock movements', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          if (_submitting) const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_movements.isEmpty)
                        const Card(child: Padding(padding: EdgeInsets.all(24), child: Text('No stock movements recorded yet.')))
                      else
                        for (final movement in _movements.take(50))
                          Card(
                            child: ListTile(
                              leading: CircleAvatar(child: Icon(_movementIcon(movement.movementType))),
                              title: Text(movement.productName),
                              subtitle: Text('${movement.sku} • ${_movementLabel(movement.movementType)}${movement.reason == null ? '' : ' • ${movement.reason}'}'),
                              trailing: Text(
                                '${movement.quantityMilli > 0 ? '+' : ''}${ScaledDecimal.fromMilli(movement.quantityMilli)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: movement.quantityMilli < 0 ? Theme.of(context).colorScheme.error : KhanyaBrand.forest,
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

class _InventoryHero extends StatelessWidget {
  const _InventoryHero({required this.productCount, required this.movementCount});
  final int productCount;
  final int movementCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [KhanyaBrand.forestDark, KhanyaBrand.forest]),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: [
            const Icon(Icons.warehouse_outlined, color: Colors.white, size: 42),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Control physical stock', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text('$productCount tracked products • $movementCount recent movements', style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.title, required this.description, required this.icon, required this.onTap});
  final String title;
  final String description;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: KhanyaBrand.forest, size: 30),
                const SizedBox(height: 12),
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(description),
              ],
            ),
          ),
        ),
      );
}

class _FailureView extends StatelessWidget {
  const _FailureView({required this.message, required this.onRetry});
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
              FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
            ],
          ),
        ),
      );
}

class _TransferDraft {
  const _TransferDraft(this.product, this.destinationBranchId, this.quantityMilli, this.reason, this.reference);
  final ProductSummary product;
  final String destinationBranchId;
  final int quantityMilli;
  final String reason;
  final String? reference;
}

class _CountDraft {
  const _CountDraft(this.product, this.quantityMilli, this.reason, this.reference);
  final ProductSummary product;
  final int quantityMilli;
  final String reason;
  final String? reference;
}

class _WriteOffDraft {
  const _WriteOffDraft(this.product, this.quantityMilli, this.type, this.reason);
  final ProductSummary product;
  final int quantityMilli;
  final String type;
  final String reason;
}

class TransferStockPage extends StatefulWidget {
  const TransferStockPage({super.key, required this.products, required this.branches});
  final List<ProductSummary> products;
  final List<InventoryBranch> branches;

  @override
  State<TransferStockPage> createState() => _TransferStockPageState();
}

class _TransferStockPageState extends State<TransferStockPage> {
  ProductSummary? product;
  InventoryBranch? branch;
  final quantity = TextEditingController();
  final reason = TextEditingController();
  final reference = TextEditingController();

  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    reference.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = ScaledDecimal.toMilli(quantity.text);
    if (product == null || branch == null || qty <= 0 || reason.text.trim().length < 2) return;
    Navigator.pop(
      context,
      _TransferDraft(
        product!,
        branch!.id,
        qty,
        reason.text.trim(),
        reference.text.trim().isEmpty ? null : reference.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _InventoryFormScaffold(
        title: 'Transfer stock',
        subtitle: 'Move tracked stock from the current branch to another branch.',
        icon: Icons.swap_horiz_rounded,
        actionLabel: 'Transfer stock',
        onSubmit: _submit,
        child: Column(
          children: [
            DropdownButtonFormField<ProductSummary>(
              initialValue: product,
              decoration: const InputDecoration(
                labelText: 'Product',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: widget.products
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text('${p.name} (${p.sku})'),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => product = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<InventoryBranch>(
              initialValue: branch,
              decoration: const InputDecoration(
                labelText: 'Destination branch',
                prefixIcon: Icon(Icons.store_outlined),
              ),
              items: widget.branches
                  .map((b) => DropdownMenuItem(
                        value: b,
                        child: Text('${b.name} (${b.code})'),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => branch = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Reference (optional)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
          ],
        ),
      );
}

class StocktakePage extends StatefulWidget {
  const StocktakePage({super.key, required this.products});
  final List<ProductSummary> products;

  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  ProductSummary? product;
  final count = TextEditingController();
  final reason = TextEditingController(text: 'Physical stock count');
  final reference = TextEditingController();

  @override
  void dispose() {
    count.dispose();
    reason.dispose();
    reference.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = ScaledDecimal.toMilli(count.text);
    if (product == null || qty < 0 || reason.text.trim().length < 2) return;
    Navigator.pop(
      context,
      _CountDraft(
        product!,
        qty,
        reason.text.trim(),
        reference.text.trim().isEmpty ? null : reference.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _InventoryFormScaffold(
        title: 'Physical stocktake',
        subtitle: 'Enter the counted quantity and let Khanya reconcile the variance.',
        icon: Icons.fact_check_outlined,
        actionLabel: 'Post count',
        onSubmit: _submit,
        child: Column(
          children: [
            DropdownButtonFormField<ProductSummary>(
              initialValue: product,
              decoration: const InputDecoration(
                labelText: 'Product',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: widget.products
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name} • System ${ScaledDecimal.fromMilli(p.onHandMilli ?? 0)}',
                        ),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => product = value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: count,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Physical count',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reference,
              decoration: const InputDecoration(
                labelText: 'Count reference (optional)',
                prefixIcon: Icon(Icons.tag_outlined),
              ),
            ),
          ],
        ),
      );
}

class WriteOffStockPage extends StatefulWidget {
  const WriteOffStockPage({super.key, required this.products});
  final List<ProductSummary> products;

  @override
  State<WriteOffStockPage> createState() => _WriteOffStockPageState();
}

class _WriteOffStockPageState extends State<WriteOffStockPage> {
  ProductSummary? product;
  String type = 'damage';
  final quantity = TextEditingController();
  final reason = TextEditingController();

  @override
  void dispose() {
    quantity.dispose();
    reason.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = ScaledDecimal.toMilli(quantity.text);
    if (product == null || qty <= 0 || reason.text.trim().length < 2) return;
    Navigator.pop(
      context,
      _WriteOffDraft(product!, qty, type, reason.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) => _InventoryFormScaffold(
        title: 'Damage / expiry',
        subtitle: 'Write unusable stock out with a clear reason and audit trail.',
        icon: Icons.delete_sweep_outlined,
        actionLabel: 'Write off stock',
        onSubmit: _submit,
        child: Column(
          children: [
            DropdownButtonFormField<ProductSummary>(
              initialValue: product,
              decoration: const InputDecoration(
                labelText: 'Product',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: widget.products
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                          '${p.name} (${ScaledDecimal.fromMilli(p.onHandMilli ?? 0)} ${p.unit})',
                        ),
                      ))
                  .toList(),
              onChanged: (value) => setState(() => product = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(
                labelText: 'Write-off type',
                prefixIcon: Icon(Icons.warning_amber_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'damage', child: Text('Damaged stock')),
                DropdownMenuItem(value: 'expiry', child: Text('Expired stock')),
              ],
              onChanged: (value) => setState(() => type = value ?? 'damage'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: quantity,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantity to remove',
                prefixIcon: Icon(Icons.numbers_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason / note',
                alignLabelWithHint: true,
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
          ],
        ),
      );
}

class _InventoryFormScaffold extends StatelessWidget {
  const _InventoryFormScaffold({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.actionLabel,
    required this.onSubmit,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onSubmit;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760 ? 28.0 : 16.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 110),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              child: Icon(icon),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        child,
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: onSubmit,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(actionLabel),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

IconData _movementIcon(String type) => switch (type) {
      'transfer_in' => Icons.call_received,
      'transfer_out' => Icons.call_made,
      'stocktake_gain' => Icons.add_chart,
      'stocktake_loss' => Icons.trending_down,
      'damage' || 'expiry' => Icons.delete_outline,
      'sale' => Icons.point_of_sale,
      'sale_return' => Icons.keyboard_return,
      _ => Icons.swap_vert,
    };

String _movementLabel(String type) => switch (type) {
      'transfer_in' => 'Transfer in',
      'transfer_out' => 'Transfer out',
      'stocktake_gain' => 'Stocktake gain',
      'stocktake_loss' => 'Stocktake loss',
      'damage' => 'Damaged stock',
      'expiry' => 'Expired stock',
      'sale_return' => 'Sales return',
      _ => type.replaceAll('_', ' '),
    };
