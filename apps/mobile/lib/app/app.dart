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
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/business_context_page.dart';
import 'package:khanya_pos/features/auth/presentation/login_page.dart';
import 'package:khanya_pos/features/pos/hardware/pos_hardware_settings.dart';

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
        RepositoryProvider.value(value: dependencies.salesRepository),
        RepositoryProvider.value(value: dependencies.purchasingRepository),
        RepositoryProvider.value(value: dependencies.documentRepository),
        RepositoryProvider.value(value: dependencies.expenseRepository),
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
              syncService: dependencies.syncService,
              productRepository: dependencies.productRepository,
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
