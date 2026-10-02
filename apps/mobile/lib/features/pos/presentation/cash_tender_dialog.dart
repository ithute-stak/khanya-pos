import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';

Future<int?> showCashTenderDialog(
  BuildContext context, {
  required int totalMinor,
}) {
  return Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CashTenderPage(totalMinor: totalMinor),
    ),
  );
}

class CashTenderPage extends StatefulWidget {
  const CashTenderPage({super.key, required this.totalMinor});

  final int totalMinor;

  @override
  State<CashTenderPage> createState() => _CashTenderPageState();
}

class _CashTenderPageState extends State<CashTenderPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late int _tenderedMinor;

  @override
  void initState() {
    super.initState();
    _tenderedMinor = widget.totalMinor;
    _controller = TextEditingController(text: ScaledDecimal.fromMinor(widget.totalMinor));
    _focusNode = FocusNode(debugLabel: 'Cash tender');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _canComplete => _tenderedMinor >= widget.totalMinor;
  int get _changeMinor => _canComplete ? _tenderedMinor - widget.totalMinor : 0;

  void _setTendered(int amountMinor) {
    setState(() => _tenderedMinor = amountMinor);
    _controller.text = ScaledDecimal.fromMinor(amountMinor);
    _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
    _focusNode.requestFocus();
  }

  void _onChanged(String value) {
    final normalized = value.replaceAll(',', '').replaceAll('M', '').replaceAll('m', '').trim();
    final parsed = normalized.isEmpty ? 0 : ScaledDecimal.toMinor(normalized);
    setState(() => _tenderedMinor = parsed < 0 ? 0 : parsed);
  }

  void _complete() {
    if (!_canComplete) return;
    Navigator.of(context).pop(_tenderedMinor);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final quickAmounts = buildQuickTenderAmounts(widget.totalMinor);
    final shortfall = widget.totalMinor - _tenderedMinor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash payment'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth >= 760 ? 28.0 : 16.0;
            return ListView(
              padding: EdgeInsets.fromLTRB(horizontal, 20, horizontal, 110),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Receive cash',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Enter the amount handed to the cashier and confirm the change before completing the sale.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                const Text('Amount due'),
                                const Spacer(),
                                Text(
                                  Loti.formatMinor(widget.totalMinor),
                                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                          onChanged: _onChanged,
                          onSubmitted: (_) => _complete(),
                          decoration: const InputDecoration(
                            labelText: 'Cash received',
                            prefixText: 'M ',
                            helperText: 'Enter the amount handed to the cashier.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final amount in quickAmounts)
                              ActionChip(
                                label: Text(
                                  amount == widget.totalMinor
                                      ? 'Exact ${Loti.formatMinor(amount)}'
                                      : Loti.formatMinor(amount),
                                ),
                                onPressed: () => _setTendered(amount),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Card(
                          color: _canComplete
                              ? scheme.secondaryContainer.withValues(alpha: 0.55)
                              : scheme.errorContainer.withValues(alpha: 0.45),
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(
                              children: [
                                Text(_canComplete ? 'Change due' : 'Still due'),
                                const Spacer(),
                                Text(
                                  Loti.formatMinor(_canComplete ? _changeMinor : shortfall),
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _canComplete ? _complete : null,
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text(
                            _canComplete
                                ? 'Complete sale • Change ${Loti.formatMinor(_changeMinor)}'
                                : 'Enter enough cash',
                          ),
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

List<int> buildQuickTenderAmounts(int totalMinor) {
  if (totalMinor <= 0) return const [0];
  final candidates = <int>[totalMinor];
  const steps = <int>[1000, 2000, 5000, 10000, 20000, 50000, 100000];
  for (final step in steps) {
    final rounded = ((totalMinor + step - 1) ~/ step) * step;
    if (rounded >= totalMinor && !candidates.contains(rounded)) candidates.add(rounded);
    if (candidates.length >= 5) break;
  }
  return List.unmodifiable(candidates);
}
