import 'package:go_router/go_router.dart';
import 'package:khanya_pos/app/desktop_shell.dart';
import 'package:khanya_pos/features/catalog/presentation/products_page.dart';
import 'package:khanya_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:khanya_pos/features/documents/presentation/receipt_vault_page.dart';
import 'package:khanya_pos/features/expenses/presentation/add_expense_page.dart';
import 'package:khanya_pos/features/expenses/presentation/expenses_page.dart';
import 'package:khanya_pos/features/inventory/presentation/inventory_page.dart';
import 'package:khanya_pos/features/pos/presentation/hardware_settings_page.dart';
import 'package:khanya_pos/features/pos/presentation/pos_page.dart';
import 'package:khanya_pos/features/pos/presentation/till_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/new_purchase_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/purchases_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/suppliers_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => DesktopShell(
        location: state.uri.path,
        child: child,
      ),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
        GoRoute(path: '/pos', builder: (context, state) => const PosPage()),
        GoRoute(path: '/till', builder: (context, state) => const TillPage()),
        GoRoute(path: '/products', builder: (context, state) => const ProductsPage()),
        GoRoute(path: '/inventory', builder: (context, state) => const InventoryPage()),
        GoRoute(path: '/purchases', builder: (context, state) => const PurchasesPage()),
        GoRoute(path: '/purchases/new', builder: (context, state) => const NewPurchasePage()),
        GoRoute(path: '/suppliers', builder: (context, state) => const SuppliersPage()),
        GoRoute(path: '/receipts', builder: (context, state) => const ReceiptVaultPage()),
        GoRoute(path: '/expenses', builder: (context, state) => const ExpensesPage()),
        GoRoute(path: '/expenses/new', builder: (context, state) => const AddExpensePage()),
        GoRoute(
          path: '/settings/hardware',
          builder: (context, state) => const HardwareSettingsPage(),
        ),
      ],
    ),
  ],
);
