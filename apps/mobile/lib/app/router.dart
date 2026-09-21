import 'package:go_router/go_router.dart';
import 'package:khanya_pos/features/catalog/presentation/products_page.dart';
import 'package:khanya_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:khanya_pos/features/inventory/presentation/inventory_page.dart';
import 'package:khanya_pos/features/pos/presentation/pos_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const DashboardPage()),
    GoRoute(path: '/pos', builder: (context, state) => const PosPage()),
    GoRoute(path: '/products', builder: (context, state) => const ProductsPage()),
    GoRoute(path: '/inventory', builder: (context, state) => const InventoryPage()),
  ],
);
