import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:khanya_pos/app/router.dart';
import 'package:khanya_pos/core/connectivity/connectivity_bloc.dart';
import 'package:khanya_pos/features/auth/presentation/bloc/session_bloc.dart';

class KhanyaPosApp extends StatelessWidget {
  const KhanyaPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => ConnectivityBloc()..add(const ConnectivityStarted())),
        BlocProvider(create: (_) => SessionBloc()..add(const SessionStarted())),
      ],
      child: MaterialApp.router(
        title: 'Khanya POS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0B4AA2)),
          scaffoldBackgroundColor: const Color(0xFFF8FAFD),
        ),
        routerConfig: appRouter,
      ),
    );
  }
}
