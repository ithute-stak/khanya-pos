import 'package:flutter/material.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';

Future<String?> showHoldSaleDialog(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const HoldSalePage(),
    ),
  );
}

Future<HeldSale?> showHeldSalesDialog(
  BuildContext context, {
  required HeldSalesRepository repository,
}) {
  return Navigator.of(context).push<HeldSale>(
    MaterialPageRoute(
      builder: (_) => HeldSalesPage(repository: repository),
    ),
  );
}

class HoldSalePage extends StatefulWidget {
  const HoldSalePage({super.key});

  @override
  State<HoldSalePage> createState() => _HoldSalePageState();
}

class _HoldSalePageState extends State<HoldSalePage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _defaultHoldLabel());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final label = _controller.text.trim();
    if (label.isEmpty) return;
    Navigator.of(context).pop(label);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Hold sale')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760 ? 28.0 : 16.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 100),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Hold this sale',
                          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Give the sale a clear reference so the cashier can identify it quickly when resuming.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: _controller,
                          autofocus: true,
                          maxLength: 60,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _save(),
                          decoration: const InputDecoration(
                            labelText: 'Reference / customer name',
                            helperText: 'Use something the cashier can recognise later.',
                            prefixIcon: Icon(Icons.pause_circle_outline),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.pause),
                          label: const Text('Hold sale'),
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

class HeldSalesPage extends StatefulWidget {
  const HeldSalesPage({super.key, required this.repository});

  final HeldSalesRepository repository;

  @override
  State<HeldSalesPage> createState() => _HeldSalesPageState();
}

class _HeldSalesPageState extends State<HeldSalesPage> {
  bool _loading = true;
  String? _error;
  List<HeldSale> _sales = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await widget.repository.listCurrentBranch();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Held sales could not be loaded.';
      });
    }
  }

  Future<void> _remove(HeldSale sale) async {
    await widget.repository.remove(sale.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Held sales'),
        actions: [
          IconButton(
            tooltip: 'Refresh held sales',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, size: 42),
                          const SizedBox(height: 12),
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 14),
                          FilledButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Try again'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _sales.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('There are no held sales for this branch.'),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                          itemCount: _sales.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final sale = _sales[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: const CircleAvatar(child: Icon(Icons.shopping_cart_outlined)),
                                title: Text(sale.label),
                                subtitle: Text(
                                  '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} • '
                                  '${Loti.formatMinor(sale.totalMinor)} • ${_formatHeldTime(sale.createdAt)}',
                                ),
                                trailing: Wrap(
                                  spacing: 4,
                                  children: [
                                    IconButton(
                                      tooltip: 'Delete held sale',
                                      onPressed: () => _remove(sale),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.of(context).pop(sale),
                                      child: const Text('Resume'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
      ),
    );
  }
}

String _defaultHoldLabel() {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Held ${two(now.hour)}:${two(now.minute)}';
}

String _formatHeldTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
