import 'package:go_router/go_router.dart';
import 'package:khanya_pos/app/desktop_shell.dart';
import 'package:khanya_pos/features/accounting/presentation/accounting_page.dart';
import 'package:khanya_pos/features/accounting/presentation/financial_statements_page.dart';
import 'package:khanya_pos/features/accounting/presentation/management_reports_page.dart';
import 'package:khanya_pos/features/catalog/presentation/products_page.dart';
import 'package:khanya_pos/features/customers/presentation/customer_detail_page.dart';
import 'package:khanya_pos/features/customers/presentation/customer_statement_page.dart';
import 'package:khanya_pos/features/customers/presentation/customers_page.dart';
import 'package:khanya_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:khanya_pos/features/documents/presentation/receipt_vault_page.dart';
import 'package:khanya_pos/features/expenses/presentation/add_expense_page.dart';
import 'package:khanya_pos/features/expenses/presentation/expenses_page.dart';
import 'package:khanya_pos/features/inventory/presentation/inventory_controls_page.dart';
import 'package:khanya_pos/features/inventory/presentation/inventory_page.dart';
import 'package:khanya_pos/features/pos/presentation/hardware_settings_page.dart';
import 'package:khanya_pos/features/pos/presentation/pos_page.dart';
import 'package:khanya_pos/features/pos/presentation/sales_history_page.dart';
import 'package:khanya_pos/features/pos/presentation/till_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/new_purchase_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/purchases_page.dart';
import 'package:khanya_pos/features/purchasing/presentation/suppliers_page.dart';
import 'package:khanya_pos/features/reports/presentation/reports_page.dart';
import 'package:khanya_pos/features/staff/presentation/staff_page.dart';

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
        GoRoute(path: '/sales', builder: (context, state) => const SalesHistoryPage()),
        GoRoute(
          path: '/sales/:saleId',
          builder: (context, state) => SaleDetailPage(
            saleId: state.pathParameters['saleId']!,
          ),
        ),
        GoRoute(path: '/till', builder: (context, state) => const TillPage()),
        GoRoute(path: '/reports', builder: (context, state) => const ReportsPage()),
        GoRoute(path: '/accounting', builder: (context, state) => const AccountingPage()),
        GoRoute(
          path: '/accounting/statements',
          builder: (context, state) => const FinancialStatementsPage(),
        ),
        GoRoute(
          path: '/accounting/management',
          builder: (context, state) => const ManagementReportsPage(),
        ),
        GoRoute(path: '/staff', builder: (context, state) => const StaffPage()),
        GoRoute(path: '/products', builder: (context, state) => const ProductsPage()),
        GoRoute(path: '/customers', builder: (context, state) => const CustomersPage()),
        GoRoute(
          path: '/customers/:customerId',
          builder: (context, state) => CustomerDetailPage(
            customerId: state.pathParameters['customerId']!,
          ),
        ),
        GoRoute(
          path: '/customers/:customerId/statement',
          builder: (context, state) => CustomerStatementPage(
            customerId: state.pathParameters['customerId']!,
          ),
        ),
        GoRoute(path: '/inventory', builder: (context, state) => const InventoryPage()),
        GoRoute(path: '/inventory/controls', builder: (context, state) => const InventoryControlsPage()),
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
