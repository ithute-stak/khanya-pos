import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/features/pos/data/till_repository.dart';
import 'package:khanya_pos/features/pos/domain/till_shift.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/till_bloc.dart';

class TillPage extends StatelessWidget {
  const TillPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TillBloc(repository: context.read<TillRepository>())
        ..add(const TillStarted()),
      child: const _TillView(),
    );
  }
}

class _TillView extends StatelessWidget {
  const _TillView();

  @override
  Widget build(BuildContext context) {
    final connected = context.watch<ConnectivityBloc>().state.isNetworkAvailable;
    return BlocConsumer<TillBloc, TillState>(
      listenWhen: (previous, current) =>
          previous.errorMessage != current.errorMessage || previous.notice != current.notice,
      listener: (context, state) {
        final message = state.errorMessage ?? state.notice;
        if (message == null || message.isEmpty) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Till & Shift'),
            actions: [
              IconButton(
                tooltip: 'Refresh till totals',
                onPressed: state.busy
                    ? null
                    : () => context.read<TillBloc>().add(const TillRefreshed()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (state.status == TillLoadStatus.initial ||
                  (state.status == TillLoadStatus.loading &&
                      state.current == null &&
                      state.history.isEmpty)) {
                return const Center(child: CircularProgressIndicator());
              }

              final horizontalPadding = constraints.maxWidth >= 1100 ? 30.0 : 16.0;
              return RefreshIndicator(
                onRefresh: () => _refresh(context),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 40),
                  children: [
                    if (state.status == TillLoadStatus.submitting)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (!connected) ...[
                      const _OfflineTillNotice(),
                      const SizedBox(height: 16),
                    ],
                    if (constraints.maxWidth >= 980)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _CurrentTillSection(
                              state: state,
                              connected: connected,
                            ),
                          ),
                          const SizedBox(width: 18),
                          Expanded(
                            flex: 5,
                            child: _HistorySection(history: state.history),
                          ),
                        ],
                      )
                    else ...[
                      _CurrentTillSection(state: state, connected: connected),
                      const SizedBox(height: 18),
                      _HistorySection(history: state.history),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refresh(BuildContext context) async {
    final bloc = context.read<TillBloc>();
    bloc.add(const TillRefreshed());
    await bloc.stream.firstWhere((state) => state.status != TillLoadStatus.loading);
  }
}

class _OfflineTillNotice extends StatelessWidget {
  const _OfflineTillNotice();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer.withValues(alpha: 0.45),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_outlined),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Till opening, cash movements and closing require a connection so drawer reconciliation cannot be duplicated or lost. Sales can continue using the POS offline queue.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentTillSection extends StatelessWidget {
  const _CurrentTillSection({required this.state, required this.connected});

  final TillState state;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final current = state.current;
    if (current == null) {
      return _NoOpenTillCard(
        busy: state.busy,
        connected: connected,
        onOpen: () => _openTill(context),
      );
    }
    return _OpenTillCard(
      shift: current,
      busy: state.busy,
      connected: connected,
      onPaidIn: () => _cashMovement(context, 'paid_in'),
      onPaidOut: () => _cashMovement(context, 'paid_out'),
      onClose: () => _closeTill(context, current),
    );
  }

  Future<void> _openTill(BuildContext context) async {
    final openingFloat = await _showOpenTillDialog(context);
    if (openingFloat == null || !context.mounted) return;
    context.read<TillBloc>().add(TillOpened(openingFloat));
  }

  Future<void> _cashMovement(BuildContext context, String movementType) async {
    final request = await _showCashMovementDialog(context, movementType: movementType);
    if (request == null || !context.mounted) return;
    context.read<TillBloc>().add(
          TillCashMovementRecorded(
            movementType: movementType,
            amountMinor: request.amountMinor,
            reason: request.reason,
          ),
        );
  }

  Future<void> _closeTill(BuildContext context, TillShiftSummary shift) async {
    final request = await _showCloseTillDialog(context, shift: shift);
    if (request == null || !context.mounted) return;
    context.read<TillBloc>().add(
          TillClosed(countedCashMinor: request.countedCashMinor, note: request.note),
        );
  }
}

class _NoOpenTillCard extends StatelessWidget {
  const _NoOpenTillCard({
    required this.busy,
    required this.connected,
    required this.onOpen,
  });

  final bool busy;
  final bool connected;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: scheme.primaryContainer,
              child: Icon(Icons.point_of_sale_outlined, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(height: 16),
            Text('No open till shift', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'Open the drawer with its starting float before beginning a cashier shift. Khanya will then reconcile cash sales and drawer movements against the amount counted at closing.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy || !connected ? null : onOpen,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Open Till'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenTillCard extends StatelessWidget {
  const _OpenTillCard({
    required this.shift,
    required this.busy,
    required this.connected,
    required this.onPaidIn,
    required this.onPaidOut,
    required this.onClose,
  });

  final TillShiftSummary shift;
  final bool busy;
  final bool connected;
  final VoidCallback onPaidIn;
  final VoidCallback onPaidOut;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = !busy && connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.lock_open_outlined, color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Till is open', style: Theme.of(context).textTheme.titleLarge),
                      Text(
                        'Opened ${_formatDateTime(shift.openedAt)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.circle, size: 10),
                  label: const Text('OPEN'),
                  backgroundColor: scheme.primaryContainer.withValues(alpha: 0.65),
                ),
              ],
            ),
            const SizedBox(height: 20),
            DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expected drawer cash', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      Loti.formatMinor(shift.expectedCashMinor),
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Opening float + cash sales + paid in - paid out',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _TillMetric(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Opening float',
                  value: Loti.formatMinor(shift.openingFloatMinor),
                ),
                _TillMetric(
                  icon: Icons.shopping_cart_checkout_outlined,
                  label: 'Cash sales',
                  value: Loti.formatMinor(shift.cashSalesMinor),
                  detail: '${shift.cashSaleCount} sale${shift.cashSaleCount == 1 ? '' : 's'}',
                ),
                _TillMetric(
                  icon: Icons.add_circle_outline,
                  label: 'Cash paid in',
                  value: Loti.formatMinor(shift.paidInMinor),
                ),
                _TillMetric(
                  icon: Icons.remove_circle_outline,
                  label: 'Cash paid out',
                  value: Loti.formatMinor(shift.paidOutMinor),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: enabled ? onPaidIn : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Cash In'),
                ),
                FilledButton.tonalIcon(
                  onPressed: enabled ? onPaidOut : null,
                  icon: const Icon(Icons.remove),
                  label: const Text('Cash Out'),
                ),
                FilledButton.icon(
                  onPressed: enabled ? onClose : null,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Count & Close Till'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TillMetric extends StatelessWidget {
  const _TillMetric({
    required this.icon,
    required this.label,
    required this.value,
    this.detail,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 165, maxWidth: 230),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              if (detail != null) ...[
                const SizedBox(height: 2),
                Text(detail!, style: Theme.of(context).textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history});

  final List<TillShiftSummary> history;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 10),
                Text('Shift history', style: Theme.of(context).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 14),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 26),
                child: Text('No till shifts have been recorded for this cashier at this branch.'),
              )
            else
              for (final shift in history) ...[
                _HistoryTile(shift: shift),
                if (shift != history.last) const Divider(height: 1),
              ],
          ],
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.shift});

  final TillShiftSummary shift;

  @override
  Widget build(BuildContext context) {
    final variance = shift.varianceMinor;
    final scheme = Theme.of(context).colorScheme;
    final varianceText = variance == null
        ? null
        : variance == 0
            ? 'Balanced'
            : variance > 0
                ? 'Over ${Loti.formatMinor(variance)}'
                : 'Short ${Loti.formatMinor(-variance)}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                shift.isOpen ? Icons.lock_open_outlined : Icons.lock_outline,
                size: 19,
                color: shift.isOpen ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shift.isOpen ? 'Current open shift' : _formatDateTime(shift.openedAt),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(Loti.formatMinor(shift.expectedCashMinor)),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${shift.cashSaleCount} cash sale${shift.cashSaleCount == 1 ? '' : 's'} • '
            'Sales ${Loti.formatMinor(shift.cashSalesMinor)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (shift.closingCashCountedMinor != null) ...[
            const SizedBox(height: 4),
            Text(
              'Counted ${Loti.formatMinor(shift.closingCashCountedMinor!)}'
              '${varianceText == null ? '' : ' • $varianceText'}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: variance == null || variance == 0 ? scheme.onSurfaceVariant : scheme.error,
                    fontWeight: variance == null || variance == 0 ? null : FontWeight.w700,
                  ),
            ),
          ],
          if (shift.closedAt != null) ...[
            const SizedBox(height: 4),
            Text('Closed ${_formatDateTime(shift.closedAt!)}', style: Theme.of(context).textTheme.labelSmall),
          ],
          if (shift.closingNote?.isNotEmpty ?? false) ...[
            const SizedBox(height: 5),
            Text('Note: ${shift.closingNote}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _CashMovementRequest {
  const _CashMovementRequest({required this.amountMinor, required this.reason});

  final int amountMinor;
  final String reason;
}

class _CloseTillRequest {
  const _CloseTillRequest({required this.countedCashMinor, this.note});

  final int countedCashMinor;
  final String? note;
}

Future<int?> _showOpenTillDialog(BuildContext context) async {
  final controller = TextEditingController(text: '0.00');
  try {
    return await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          String? error;
          return AlertDialog(
            icon: const Icon(Icons.lock_open_outlined, size: 38),
            title: const Text('Open till shift'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Enter the physical cash already inside the drawer before sales begin.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      labelText: 'Opening float',
                      prefixText: 'M ',
                      errorText: error,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = _parseMoney(controller.text);
                  if (amount == null || amount < 0) {
                    setState(() => error = 'Enter a valid amount of zero or more.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(amount);
                },
                child: const Text('Open Till'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<_CashMovementRequest?> _showCashMovementDialog(
  BuildContext context, {
  required String movementType,
}) async {
  final amountController = TextEditingController();
  final reasonController = TextEditingController();
  final paidIn = movementType == 'paid_in';
  try {
    return await showDialog<_CashMovementRequest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          String? amountError;
          String? reasonError;
          return AlertDialog(
            icon: Icon(paidIn ? Icons.add_circle_outline : Icons.remove_circle_outline, size: 38),
            title: Text(paidIn ? 'Cash paid in' : 'Cash paid out'),
            content: SizedBox(
              width: 430,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      prefixText: 'M ',
                      errorText: amountError,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: reasonController,
                    maxLength: 240,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Reason',
                      hintText: paidIn ? 'e.g. Extra change float' : 'e.g. Petty cash purchase',
                      errorText: reasonError,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = _parseMoney(amountController.text);
                  final reason = reasonController.text.trim();
                  var valid = true;
                  if (amount == null || amount <= 0) {
                    amountError = 'Enter an amount greater than zero.';
                    valid = false;
                  }
                  if (reason.length < 2) {
                    reasonError = 'Enter a reason for this drawer movement.';
                    valid = false;
                  }
                  if (!valid) {
                    setState(() {});
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                        _CashMovementRequest(amountMinor: amount!, reason: reason),
                      );
                },
                child: Text(paidIn ? 'Record Cash In' : 'Record Cash Out'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    amountController.dispose();
    reasonController.dispose();
  }
}

Future<_CloseTillRequest?> _showCloseTillDialog(
  BuildContext context, {
  required TillShiftSummary shift,
}) async {
  final countController = TextEditingController(text: ScaledDecimal.fromMinor(shift.expectedCashMinor));
  final noteController = TextEditingController();
  var countedMinor = shift.expectedCashMinor;
  try {
    return await showDialog<_CloseTillRequest>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          final variance = countedMinor - shift.expectedCashMinor;
          String? error;
          return AlertDialog(
            icon: const Icon(Icons.fact_check_outlined, size: 38),
            title: const Text('Count & close till'),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DialogAmountRow(label: 'Expected cash', amountMinor: shift.expectedCashMinor),
                  const SizedBox(height: 14),
                  TextField(
                    controller: countController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    onChanged: (value) {
                      final parsed = _parseMoney(value);
                      setState(() {
                        countedMinor = parsed ?? 0;
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Physical cash counted',
                      prefixText: 'M ',
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DialogAmountRow(
                    label: variance == 0
                        ? 'Variance - balanced'
                        : variance > 0
                            ? 'Variance - over'
                            : 'Variance - short',
                    amountMinor: variance.abs(),
                    emphasize: variance != 0,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: noteController,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Closing note (optional)',
                      hintText: 'Explain any shortage, overage or handover detail.',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
                  final amount = _parseMoney(countController.text);
                  if (amount == null || amount < 0) {
                    setState(() => error = 'Enter the cash physically counted in the drawer.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(
                        _CloseTillRequest(
                          countedCashMinor: amount,
                          note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                        ),
                      );
                },
                icon: const Icon(Icons.lock_outline),
                label: const Text('Close Till'),
              ),
            ],
          );
        },
      ),
    );
  } finally {
    countController.dispose();
    noteController.dispose();
  }
}

class _DialogAmountRow extends StatelessWidget {
  const _DialogAmountRow({
    required this.label,
    required this.amountMinor,
    this.emphasize = false,
  });

  final String label;
  final int amountMinor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasize
            ? scheme.errorContainer.withValues(alpha: 0.42)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              Loti.formatMinor(amountMinor),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

int? _parseMoney(String value) {
  final normalized = value.replaceAll(',', '').replaceAll('M', '').replaceAll('m', '').trim();
  if (normalized.isEmpty) return null;
  try {
    return ScaledDecimal.toMinor(normalized);
  } catch (_) {
    return null;
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int part) => part.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
