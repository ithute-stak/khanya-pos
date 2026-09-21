import 'package:flutter/material.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';

Future<String?> showHoldSaleDialog(BuildContext context) async {
  final controller = TextEditingController(text: _defaultHoldLabel());
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.pause_circle_outline, size: 38),
        title: const Text('Hold this sale'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) {
              final label = value.trim();
              if (label.isNotEmpty) Navigator.of(dialogContext).pop(label);
            },
            decoration: const InputDecoration(
              labelText: 'Reference / customer name',
              helperText: 'Use something the cashier can recognise later.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              final label = controller.text.trim();
              if (label.isNotEmpty) Navigator.of(dialogContext).pop(label);
            },
            icon: const Icon(Icons.pause),
            label: const Text('Hold sale'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<HeldSale?> showHeldSalesDialog(
  BuildContext context, {
  required HeldSalesRepository repository,
}) {
  return showDialog<HeldSale>(
    context: context,
    builder: (_) => _HeldSalesDialog(repository: repository),
  );
}

class _HeldSalesDialog extends StatefulWidget {
  const _HeldSalesDialog({required this.repository});

  final HeldSalesRepository repository;

  @override
  State<_HeldSalesDialog> createState() => _HeldSalesDialogState();
}

class _HeldSalesDialogState extends State<_HeldSalesDialog> {
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
    return AlertDialog(
      icon: const Icon(Icons.pause_circle_filled_outlined, size: 38),
      title: const Text('Held sales'),
      content: SizedBox(
        width: 620,
        height: 430,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : _sales.isEmpty
                    ? const Center(child: Text('There are no held sales for this branch.'))
                    : ListView.separated(
                        itemCount: _sales.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final sale = _sales[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            leading: const CircleAvatar(child: Icon(Icons.shopping_cart_outlined)),
                            title: Text(sale.label),
                            subtitle: Text(
                              '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} • '
                              '${Loti.formatMinor(sale.totalMinor)} • ${_formatHeldTime(sale.createdAt)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
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
                          );
                        },
                      ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
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
