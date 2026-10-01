import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/app/app_theme.dart';
import 'package:khanya_pos/app/dependencies.dart';
import 'package:khanya_pos/app/router.dart';
import 'package:khanya_pos/core/branding/khanya_brand.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';
import 'package:khanya_pos/core/realtime/realtime_bloc.dart';
import 'package:khanya_pos/core/sync/sync_bloc.dart';
import 'package:khanya_pos/features/accounting/data/accounting_repository.dart';
import 'package:khanya_pos/features/auth/data/auth_repository.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/business_context_page.dart';
import 'package:khanya_pos/features/auth/presentation/landing_page.dart';
import 'package:khanya_pos/features/auth/presentation/login_page.dart';
import 'package:khanya_pos/features/auth/presentation/signup_page.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/devices/data/device_repository.dart';
import 'package:khanya_pos/features/growth/data/growth_repository.dart';
import 'package:khanya_pos/features/inventory/data/inventory_control_repository.dart';
import 'package:khanya_pos/features/platform/data/platform_repository.dart';
import 'package:khanya_pos/features/platform/presentation/platform_admin_shell_page.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';
import 'package:khanya_pos/features/pos/data/till_repository.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/purchasing/data/purchase_order_repository.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';
import 'package:khanya_pos/features/settings/data/business_settings_repository.dart';
import 'package:khanya_pos/features/staff/data/staff_repository.dart';
import 'package:khanya_pos/features/workforce/data/workforce_repository.dart';

class KhanyaPosApp extends StatefulWidget {
  const KhanyaPosApp({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  State<KhanyaPosApp> createState() => _KhanyaPosAppState();
}

class _KhanyaPosAppState extends State<KhanyaPosApp> {
  @override
  void dispose() {
    unawaited(widget.dependencies.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = widget.dependencies;
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AuthRepository>.value(value: dependencies.authRepository),
        RepositoryProvider<PlatformRepository>.value(value: dependencies.platformRepository),
        RepositoryProvider.value(value: dependencies.productRepository),
        RepositoryProvider<CustomerRepository>.value(value: dependencies.customerRepository),
        RepositoryProvider<InventoryControlRepository>.value(value: dependencies.inventoryControlRepository),
        RepositoryProvider.value(value: dependencies.salesRepository),
        RepositoryProvider<HeldSalesRepository>.value(value: dependencies.heldSalesRepository),
        RepositoryProvider<TillRepository>.value(value: dependencies.tillRepository),
        RepositoryProvider.value(value: dependencies.purchasingRepository),
        RepositoryProvider.value(value: dependencies.documentRepository),
        RepositoryProvider.value(value: dependencies.expenseRepository),
        RepositoryProvider<ReportsRepository>.value(value: dependencies.reportsRepository),
        RepositoryProvider<GrowthRepository>(
          create: (_) => GrowthRepository(apiClient: dependencies.apiClient),
        ),
        RepositoryProvider<WorkforceRepository>(
          create: (_) => WorkforceRepository(apiClient: dependencies.apiClient),
        ),
        RepositoryProvider<PurchaseOrderRepository>(
          create: (_) => PurchaseOrderRepository(apiClient: dependencies.apiClient),
        ),
        RepositoryProvider<StaffRepository>.value(value: dependencies.staffRepository),
        RepositoryProvider<AccountingRepository>.value(value: dependencies.accountingRepository),
        RepositoryProvider<BusinessSettingsRepository>.value(value: dependencies.businessSettingsRepository),
        RepositoryProvider<DeviceRepository>.value(value: dependencies.deviceRepository),
        RepositoryProvider<PosHardwareSettingsRepository>.value(
          value: dependencies.hardwareSettingsRepository,
        ),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => ConnectivityBloc()..add(const ConnectivityStarted())),
          BlocProvider(
            create: (_) => SessionBloc(
              authRepository: dependencies.authRepository,
              sessionContext: dependencies.sessionContext,
            )..add(const SessionStarted()),
          ),
          BlocProvider(
            create: (_) => SyncBloc(
              database: dependencies.database,
              customerDatabase: dependencies.customerDatabase,
              syncService: dependencies.syncService,
              productRepository: dependencies.productRepository,
              customerRepository: dependencies.customerRepository,
            )..add(const SyncStarted()),
          ),
          BlocProvider(
            create: (_) => RealtimeBloc(
              client: dependencies.realtimeClient,
              sessionContext: dependencies.sessionContext,
              productRepository: dependencies.productRepository,
            ),
          ),
        ],
        child: const _AppView(),
      ),
    );
  }
}

class _AppView extends StatelessWidget {
  const _AppView();

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<SessionBloc, SessionState>(
          listener: (context, state) {
            if (state is SessionAuthenticated) {
              if (!state.session.isPlatformAdmin && state.session.selectedTenantId != null) {
                context.read<SyncBloc>().add(const SyncRequested());
                context.read<RealtimeBloc>().add(const RealtimeActivated());
              } else {
                context.read<RealtimeBloc>().add(const RealtimeStopped());
              }
            } else if (state is SessionUnauthenticated) {
              context.read<RealtimeBloc>().add(const RealtimeStopped());
            }
          },
        ),
        BlocListener<ConnectivityBloc, ConnectivityState>(
          listenWhen: (previous, current) =>
              previous.isNetworkAvailable != current.isNetworkAvailable && current.isNetworkAvailable,
          listener: (context, state) {
            final sessionState = context.read<SessionBloc>().state;
            if (sessionState is SessionAuthenticated &&
                !sessionState.session.isPlatformAdmin &&
                sessionState.session.selectedTenantId != null) {
              context.read<SyncBloc>().add(const SyncRequested());
              context.read<RealtimeBloc>().add(const RealtimeActivated());
            }
          },
        ),
      ],
      child: MaterialApp.router(
        title: KhanyaBrand.appName,
        debugShowCheckedModeBanner: false,
        theme: KhanyaTheme.light,
        routerConfig: appRouter,
        builder: (context, child) => _SessionGate(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

class _SessionGate extends StatelessWidget {
  const _SessionGate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionBloc, SessionState>(
      builder: (context, state) {
        if (state is SessionInitial || state is SessionRestoring) {
          return const KhanyaLoadingView(message: 'Restoring your secure workspace…');
        }
        if (state is SessionAuthenticated) {
          if (state.session.isPlatformAdmin) {
            return const PlatformAdminShellPage();
          }
          if (state.session.selectedTenantId == null || state.session.selectedBranchId == null) {
            return BusinessContextPage(state: state);
          }
          return child;
        }
        return const _PublicGateway();
      },
    );
  }
}

enum _PublicView { landing, login, signup }

class _PublicGateway extends StatefulWidget {
  const _PublicGateway();

  @override
  State<_PublicGateway> createState() => _PublicGatewayState();
}

class _PublicGatewayState extends State<_PublicGateway> {
  _PublicView _view = _PublicView.landing;

  @override
  Widget build(BuildContext context) {
    switch (_view) {
      case _PublicView.landing:
        return LandingPage(
          onSignIn: () => setState(() => _view = _PublicView.login),
          onCreateAccount: () => setState(() => _view = _PublicView.signup),
        );
      case _PublicView.login:
        return Stack(
          children: [
            const LoginPage(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: IconButton.filledTonal(
                  onPressed: () => setState(() => _view = _PublicView.landing),
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back to home',
                ),
              ),
            ),
          ],
        );
      case _PublicView.signup:
        return SignupPage(
          onBackToSignIn: () => setState(() => _view = _PublicView.login),
        );
    }
  }
}
