import 'package:go_router/go_router.dart';
import 'package:khanya_pos/features/dashboard/presentation/dashboard_page.dart';

final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const DashboardPage(),
    ),
  ],
);
