// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/core/money/scaled_decimal.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/catalog/data/product_repository.dart';
import 'package:khanya_pos/features/catalog/domain/product_summary.dart';
import 'package:khanya_pos/features/catalog/presentation/bloc/product_catalog_bloc.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';
import 'package:khanya_pos/features/pos/data/sales_repository.dart';
import 'package:khanya_pos/features/pos/domain/cart.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_service.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/cart_bloc.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/checkout_bloc.dart';
import 'package:khanya_pos/features/pos/presentation/bloc/pos_credit_cubit.dart';
import 'package:khanya_pos/features/pos/presentation/cash_tender_dialog.dart';
import 'package:khanya_pos/features/pos/presentation/held_sales_dialog.dart';
import 'package:khanya_pos/features/pos/presentation/pos_customer_credit_panel.dart';
import 'package:khanya_pos/features/pos/printing/receipt_printer.dart';
import 'package:khanya_pos/features/pos/printing/sale_receipt.dart';

Future<void> _submitCheckout(BuildContext context, CartState cart) async {
  final checkout = context.read<CheckoutBloc>().state;
  if (cart.lines.isEmpty || checkout.status == CheckoutStatus.submitting) return;

  final credit = context.read<PosCreditCubit>().state;
  final paidMinor = credit.paidMinorFor(cart.totalMinor);
  if (!credit.canSubmit(cart.totalMinor)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('The requested credit exceeds the selected customer’s available limit.')),
    );
    return;
  }

  int? cashTenderedMinor;
  if (cart.paymentMethod == PaymentMethod.cash && paidMinor > 0) {
    cashTenderedMinor = await showCashTenderDialog(context, totalMinor: paidMinor);
    if (cashTenderedMinor == null || !context.mounted) return;
  }

  context.read<CheckoutBloc>().add(
        CheckoutSaleRequested(
          lines: List<CartLine>.unmodifiable(cart.lines),
          paymentMethod: cart.paymentMethod,
          customer: credit.customer,
          immediatePaymentMinor: paidMinor,
          cashTenderedMinor: cashTenderedMinor,
        ),
      );
}

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
        BlocProvider(create: (_) => PosCreditCubit()),
      ],
      child: const _PosView(),
    );
  }
}

class _PosView extends StatefulWidget {
  const _PosView();

  @override
  State<_PosView> createState() => _PosViewState();
}

class _PosViewState extends State<_PosView> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode(debugLabel: 'POS search');
  SaleReceipt? _lastReceipt;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
    _searchController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _searchController.text.length,
    );
  }

  void _clearSearch(BuildContext context) {
    _searchController.clear();
    context.read<ProductCatalogBloc>().add(const ProductCatalogQueryChanged(''));
    _searchFocusNode.requestFocus();
  }

  Future<void> _requestCheckout(BuildContext context) async {
    final cart = context.read<CartBloc>().state;
    await _submitCheckout(context, cart);
  }

  Future<void> _holdCurrentSale() async {
    final cart = context.read<CartBloc>().state;
    if (cart.lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add products before holding a sale.')),
      );
      return;
    }

    final label = await showHoldSaleDialog(context);
    if (label == null || !mounted) return;

    try {
      final heldSale = await context.read<HeldSalesRepository>().hold(
            lines: List<CartLine>.unmodifiable(cart.lines),
            paymentMethod: cart.paymentMethod,
            label: label,
          );
      if (!mounted) return;
      context.read<CartBloc>().add(const CartCleared());
      context.read<CheckoutBloc>().add(const CheckoutReset());
      context.read<PosCreditCubit>().reset();
      _clearSearch(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sale held as “${heldSale.label}”. Reselect a customer when resuming credit sales.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The sale could not be held. The current cart was kept.')),
      );
    }
  }

  Future<void> _resumeHeldSale() async {
    final repository = context.read<HeldSalesRepository>();
    final heldSale = await showHeldSalesDialog(context, repository: repository);
    if (heldSale == null || !mounted) return;

    final currentCart = context.read<CartBloc>().state;
    if (currentCart.lines.isNotEmpty) {
      final replace = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.swap_horiz, size: 38),
              title: const Text('Replace current cart?'),
              content: const Text(
                'Resuming this held sale will replace the products currently in the cart. You can hold the current cart first if you need to keep it.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Replace cart'),
                ),
              ],
            ),
          ) ??
          false;
      if (!replace || !mounted) return;
    }

    final products = context.read<ProductCatalogBloc>().state.products;
    final restoredLines = <CartLine>[];
    var adjusted = false;

    for (final heldLine in heldSale.lines) {
      ProductSummary? product;
      for (final candidate in products) {
        if (candidate.id == heldLine.productId) {
          product = candidate;
          break;
        }
      }
      if (product == null) {
        adjusted = true;
        continue;
      }

      var quantity = heldLine.quantity;
      final available = product.tracksStock ? product.availableWholeUnits : null;
      if (available != null) {
        if (available <= 0) {
          adjusted = true;
          continue;
        }
        if (quantity > available) {
          quantity = available;
          adjusted = true;
        }
      }
      if (quantity <= 0) {
        adjusted = true;
        continue;
      }
      restoredLines.add(CartLine(product: product.toPosProduct(), quantity: quantity));
    }

    if (restoredLines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('None of the held items are currently available. The held sale was kept.'),
        ),
      );
      return;
    }

    context.read<CartBloc>().add(
          CartReplaced(
            lines: List<CartLine>.unmodifiable(restoredLines),
            paymentMethod: heldSale.paymentMethod,
          ),
        );
    context.read<CheckoutBloc>().add(const CheckoutReset());
    context.read<PosCreditCubit>().reset();
    _clearSearch(context);

    var removed = true;
    try {
      await repository.remove(heldSale.id);
    } catch (_) {
      removed = false;
    }
    if (!mounted) return;

    final message = StringBuffer('Resumed “${heldSale.label}”.');
    if (adjusted) {
      message.write(' Some items were unavailable or quantities were reduced to current stock.');
    }
    if (!removed) {
      message.write(' Its held copy could not be removed, so it may still appear in Held Sales.');
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));
  }

  Future<PosHardwareSettings> _readHardwareSettings() async {
    final repository = context.read<PosHardwareSettingsRepository>();
    try {
      return await repository.read();
    } catch (_) {
      return const PosHardwareSettings();
    }
  }

  SaleReceipt _makeReceipt(BuildContext context, CheckoutState state) {
    var businessName = 'Khanya POS';
    String? branchId;
    String? cashierName;
    final sessionState = context.read<SessionBloc>().state;
    if (sessionState is SessionAuthenticated) {
      final session = sessionState.session;
      branchId = session.selectedBranchId;
      cashierName = session.displayName;
      for (final membership in session.memberships) {
        if (membership.tenantId == session.selectedTenantId) {
          businessName = membership.tenantName;
          break;
        }
      }
    }

    final submission = state.submission!;
    final syncStatus = switch (submission.status) {
      SaleSubmissionStatus.synced => 'Synced',
      SaleSubmissionStatus.queued => 'Queued for sync',
      SaleSubmissionStatus.conflict => 'Needs sync review',
    };

    return SaleReceipt(
      businessName: businessName,
      reference: submission.clientOperationId,
      issuedAt: DateTime.now(),
      branchId: branchId,
      cashierName: cashierName,
      customerName: state.customer?.name,
      lines: state.lines.map(SaleReceiptLine.fromCartLine).toList(growable: false),
      paymentMethod: state.paymentMethod ?? PaymentMethod.cash,
      paidNowMinor: state.paidMinor,
      balanceDueMinor: state.balanceDueMinor,
      syncStatus: syncStatus,
      cashTenderedMinor: state.cashTenderedMinor,
    );
  }

  Future<void> _handleCompleted(BuildContext context, CheckoutState state) async {
    final receipt = _makeReceipt(context, state);
    if (!mounted) return;
    setState(() => _lastReceipt = receipt);
    context.read<CartBloc>().add(const CartCleared());
    context.read<PosCreditCubit>().reset();
    context.read<SyncBloc>().add(const SyncRequested());
    _clearSearch(context);

    final status = state.submission!.status;
    final message = switch (status) {
      SaleSubmissionStatus.synced => 'Sale completed and synced.',
      SaleSubmissionStatus.queued => 'Sale saved offline and queued for sync.',
      SaleSubmissionStatus.conflict => 'Sale saved locally but needs sync review.',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

    final hardware = await _readHardwareSettings();
    if (!mounted) return;

    if (receipt.paymentMethod == PaymentMethod.cash &&
        receipt.paidMinor > 0 &&
        hardware.hasPrinter &&
        hardware.directThermalPrinting &&
        hardware.openCashDrawerOnCashSale) {
      try {
        final opened = await PosHardwareService.openCashDrawer(hardware);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sale saved, but the cash drawer did not open.')),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sale saved, but the cash drawer could not be opened.')),
          );
        }
      }
    }

    if (!mounted) return;
    if (hardware.autoPrintReceipts && hardware.hasPrinter) {
      try {
        final printed = await ReceiptPrinter.printReceipt(
          receipt,
          settings: hardware,
          showDialogWhenUnconfigured: false,
        );
        if (!mounted) return;
        if (printed) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Receipt sent to the configured printer.')),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Automatic receipt printing failed. You can print it manually.')),
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Automatic receipt printing failed. You can print it manually.')),
        );
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _showReceiptDialog(receipt);
  }

  Future<void> _printReceipt(SaleReceipt receipt) async {
    try {
      final hardware = await _readHardwareSettings();
      if (!mounted) return;
      final accepted = await ReceiptPrinter.printReceipt(
        receipt,
        settings: hardware,
        showDialogWhenUnconfigured: true,
      );
      if (!mounted) return;
      if (!accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt printing was cancelled.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the printer. Check the Windows printer installation and try again.'),
        ),
      );
    }
  }

  Future<void> _printLastReceipt() async {
    final receipt = _lastReceipt;
    if (receipt != null) await _printReceipt(receipt);
  }

  Future<void> _openDrawer() async {
    final hardware = await _readHardwareSettings();
    if (!mounted) return;
    if (!hardware.hasPrinter || !hardware.directThermalPrinting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configure an ESC/POS receipt printer in POS Hardware before opening the drawer.'),
        ),
      );
      return;
    }

    try {
      final opened = await PosHardwareService.openCashDrawer(hardware);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(opened ? 'Cash drawer opened.' : 'The cash drawer command was not accepted.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open the cash drawer. Check the printer and drawer cable.')),
      );
    }
  }

  Future<void> _showReceiptDialog(SaleReceipt receipt) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 38),
        title: Text(receipt.isCreditSale ? 'Credit sale completed' : 'Sale completed'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Total: ${Loti.formatMinor(receipt.totalMinor)}'),
              if (receipt.customerName != null) ...[
                const SizedBox(height: 6),
                Text('Customer: ${receipt.customerName}'),
              ],
              if (receipt.paidMinor > 0) ...[
                const SizedBox(height: 6),
                Text('Payment: ${receipt.paymentMethod.label}'),
              ],
              if (receipt.isCreditSale) ...[
                const SizedBox(height: 6),
                Text('Paid now: ${Loti.formatMinor(receipt.paidMinor)}'),
                const SizedBox(height: 6),
                Text(
                  'Balance due: ${Loti.formatMinor(receipt.creditBalanceMinor)}',
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
              if (receipt.cashTenderedMinor != null) ...[
                const SizedBox(height: 6),
                Text('Cash received: ${Loti.formatMinor(receipt.cashTenderedMinor!)}'),
                const SizedBox(height: 6),
                Text(
                  'Change due: ${Loti.formatMinor(receipt.cashChangeMinor ?? 0)}',
                  style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 6),
              Text('Reference: ${receipt.reference}'),
              const SizedBox(height: 6),
              Text('Status: ${receipt.syncStatus}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _printReceipt(receipt);
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print receipt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _focusSearch,
        const SingleActivator(LogicalKeyboardKey.f9): () {
          _requestCheckout(context);
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true): () {
          _holdCurrentSale();
        },
        const SingleActivator(LogicalKeyboardKey.keyH, control: true, shift: true): () {
          _resumeHeldSale();
        },
        const SingleActivator(LogicalKeyboardKey.f11): _openDrawer,
        const SingleActivator(LogicalKeyboardKey.f12): _printLastReceipt,
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _printLastReceipt,
        const SingleActivator(LogicalKeyboardKey.escape): () => _clearSearch(context),
      },
      child: Focus(
        autofocus: true,
        child: BlocListener<CheckoutBloc, CheckoutState>(
          listener: (context, state) {
            if (state.status == CheckoutStatus.completed && state.submission != null) {
              _handleCompleted(context, state);
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
                if (MediaQuery.sizeOf(context).width >= 1180)
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Center(
                      child: Text('Ctrl+F Search  •  F9 Pay  •  Ctrl+H Hold  •  F11 Drawer  •  F12 Print'),
                    ),
                  ),
                BlocBuilder<CartBloc, CartState>(
                  builder: (context, cart) => IconButton(
                    tooltip: 'Hold current sale (Ctrl+H)',
                    onPressed: cart.lines.isEmpty ? null : _holdCurrentSale,
                    icon: const Icon(Icons.pause_circle_outline),
                  ),
                ),
                IconButton(
                  tooltip: 'Held sales (Ctrl+Shift+H)',
                  onPressed: _resumeHeldSale,
                  icon: const Icon(Icons.restore_outlined),
                ),
                IconButton(
                  tooltip: 'Open cash drawer (F11)',
                  onPressed: _openDrawer,
                  icon: const Icon(Icons.point_of_sale_outlined),
                ),
                IconButton(
                  tooltip: 'Print last receipt (F12 / Ctrl+P)',
                  onPressed: _lastReceipt == null ? null : _printLastReceipt,
                  icon: const Icon(Icons.print_outlined),
                ),
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
                      Expanded(
                        flex: 3,
                        child: _ProductBrowser(
                          searchController: _searchController,
                          searchFocusNode: _searchFocusNode,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      const SizedBox(width: 420, child: _CartPanel(closeOnComplete: false)),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(
                      child: _ProductBrowser(
                        searchController: _searchController,
                        searchFocusNode: _searchFocusNode,
                      ),
                    ),
                    const _MobileCartBar(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductBrowser extends StatelessWidget {
  const _ProductBrowser({required this.searchController, required this.searchFocusNode});

  final TextEditingController searchController;
  final FocusNode searchFocusNode;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProductCatalogBloc, ProductCatalogState>(
      builder: (context, state) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              controller: searchController,
              focusNode: searchFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: (value) => context.read<ProductCatalogBloc>().add(ProductCatalogQueryChanged(value)),
              onSubmitted: (value) => _handleSubmitted(context, state, value),
              decoration: InputDecoration(
                hintText: 'Scan barcode or search product',
                prefixIcon: const Icon(Icons.qr_code_scanner),
                suffixIcon: searchController.text.isEmpty
                    ? const Icon(Icons.search)
                    : IconButton(
                        tooltip: 'Clear search (Esc)',
                        onPressed: () {
                          searchController.clear();
                          context.read<ProductCatalogBloc>().add(const ProductCatalogQueryChanged(''));
                          searchFocusNode.requestFocus();
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 900)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'USB scanner ready: scan a barcode and Enter adds the matching item to the cart.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
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
                    builder: (context, constraints) => GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: constraints.maxWidth >= 700 ? 220 : 190,
                        mainAxisExtent: 176,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                      ),
                      itemCount: state.visibleProducts.length,
                      itemBuilder: (context, index) => _SellableProductCard(product: state.visibleProducts[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _handleSubmitted(BuildContext context, ProductCatalogState state, String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return;

    ProductSummary? exactMatch;
    for (final product in state.products) {
      final barcode = product.barcode?.trim().toLowerCase();
      if (product.sku.trim().toLowerCase() == normalized || (barcode != null && barcode == normalized)) {
        exactMatch = product;
        break;
      }
    }
    if (exactMatch == null) return;

    final available = exactMatch.tracksStock ? exactMatch.availableWholeUnits : null;
    if (available != null && available <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${exactMatch.name} is out of stock.')),
      );
      searchFocusNode.requestFocus();
      return;
    }

    context.read<CartBloc>().add(CartProductAdded(exactMatch.toPosProduct()));
    searchController.clear();
    context.read<ProductCatalogBloc>().add(const ProductCatalogQueryChanged(''));
    searchFocusNode.requestFocus();
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
        onTap: soldOut ? null : () => context.read<CartBloc>().add(CartProductAdded(product.toPosProduct())),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    color: soldOut ? Colors.grey : Theme.of(context).colorScheme.primary,
                  ),
                  const Spacer(),
                  if (soldOut)
                    const Chip(label: Text('Out'), visualDensity: VisualDensity.compact)
                  else if (product.isLowStock)
                    const Chip(label: Text('Low'), visualDensity: VisualDensity.compact),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
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
    final creditCubit = context.read<PosCreditCubit>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => MultiBlocProvider(
        providers: [
          BlocProvider.value(value: cartBloc),
          BlocProvider.value(value: checkoutBloc),
          BlocProvider.value(value: creditCubit),
        ],
        child: const FractionallySizedBox(heightFactor: 0.92, child: _CartPanel(closeOnComplete: true)),
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
                    onPressed: state.lines.isEmpty
                        ? null
                        : () {
                            context.read<CartBloc>().add(const CartCleared());
                            context.read<CheckoutBloc>().add(const CheckoutReset());
                            context.read<PosCreditCubit>().reset();
                          },
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
              builder: (context, cart) => PosCustomerCreditPanel(totalMinor: cart.totalMinor),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CartBloc, CartState>(
              builder: (context, cart) => BlocBuilder<PosCreditCubit, PosCreditState>(
                builder: (context, credit) {
                  if (credit.paidMinorFor(cart.totalMinor) == 0) {
                    return InputDecorator(
                      decoration: const InputDecoration(labelText: 'Payment method'),
                      child: const Text('No immediate payment • customer credit'),
                    );
                  }
                  return DropdownButtonFormField<PaymentMethod>(
                    initialValue: cart.paymentMethod,
                    decoration: const InputDecoration(labelText: 'Payment method'),
                    items: [
                      for (final method in PaymentMethod.values)
                        DropdownMenuItem(value: method, child: Text(method.label)),
                    ],
                    onChanged: (method) {
                      if (method != null) context.read<CartBloc>().add(CartPaymentMethodChanged(method));
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            BlocBuilder<CartBloc, CartState>(
              builder: (context, cart) => BlocBuilder<CheckoutBloc, CheckoutState>(
                builder: (context, checkout) => BlocBuilder<PosCreditCubit, PosCreditState>(
                  builder: (context, credit) {
                    final submitting = checkout.status == CheckoutStatus.submitting;
                    final paidMinor = credit.paidMinorFor(cart.totalMinor);
                    final creditMinor = credit.creditMinorFor(cart.totalMinor);
                    final allowed = credit.canSubmit(cart.totalMinor);
                    final label = submitting
                        ? 'Saving sale…'
                        : creditMinor <= 0
                            ? 'Pay ${Loti.formatMinor(cart.totalMinor)}  [F9]'
                            : paidMinor == 0
                                ? 'Charge ${Loti.formatMinor(creditMinor)} to customer  [F9]'
                                : 'Pay ${Loti.formatMinor(paidMinor)} • Credit ${Loti.formatMinor(creditMinor)}  [F9]';
                    return FilledButton.icon(
                      onPressed: cart.lines.isEmpty || submitting || !allowed
                          ? null
                          : () => _submitCheckout(context, cart),
                      icon: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(creditMinor > 0 ? Icons.credit_score_outlined : Icons.check_circle_outline),
                      label: Text(label),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
