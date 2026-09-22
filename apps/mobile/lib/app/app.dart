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
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/business_context_page.dart';
import 'package:khanya_pos/features/auth/presentation/login_page.dart';
import 'package:khanya_pos/features/customers/data/customer_repository.dart';
import 'package:khanya_pos/features/inventory/data/inventory_control_repository.dart';
import 'package:khanya_pos/features/pos/data/held_sales_repository.dart';
import 'package:khanya_pos/features/pos/data/till_repository.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';
import 'package:khanya_pos/features/reports/data/reports_repository.dart';
import 'package:khanya_pos/features/settings/data/business_settings_repository.dart';
import 'package:khanya_pos/features/staff/data/staff_repository.dart';

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
        RepositoryProvider<StaffRepository>.value(value: dependencies.staffRepository),
        RepositoryProvider<AccountingRepository>.value(value: dependencies.accountingRepository),
        RepositoryProvider<BusinessSettingsRepository>.value(value: dependencies.businessSettingsRepository),
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
              context.read<SyncBloc>().add(const SyncRequested());
              context.read<RealtimeBloc>().add(const RealtimeActivated());
            } else if (state is SessionUnauthenticated) {
              context.read<RealtimeBloc>().add(const RealtimeStopped());
            }
          },
        ),
        BlocListener<ConnectivityBloc, ConnectivityState>(
          listenWhen: (previous, current) =>
              previous.isNetworkAvailable != current.isNetworkAvailable && current.isNetworkAvailable,
          listener: (context, state) {
            if (context.read<SessionBloc>().state is SessionAuthenticated) {
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
          if (state.session.selectedTenantId == null || state.session.selectedBranchId == null) {
            return BusinessContextPage(state: state);
          }
          return child;
        }
        return const LoginPage();
      },
    );
  }
}
