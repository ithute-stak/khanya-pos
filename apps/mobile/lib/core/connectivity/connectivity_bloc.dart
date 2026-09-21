import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

sealed class ConnectivityEvent extends Equatable {
  const ConnectivityEvent();

  @override
  List<Object?> get props => [];
}

final class ConnectivityStarted extends ConnectivityEvent {
  const ConnectivityStarted();
}

final class ConnectivityChanged extends ConnectivityEvent {
  const ConnectivityChanged(this.results);

  final List<ConnectivityResult> results;

  @override
  List<Object?> get props => [results];
}

class ConnectivityState extends Equatable {
  const ConnectivityState({required this.isNetworkAvailable});

  const ConnectivityState.initial() : isNetworkAvailable = true;

  final bool isNetworkAvailable;

  @override
  List<Object?> get props => [isNetworkAvailable];
}

class ConnectivityBloc extends Bloc<ConnectivityEvent, ConnectivityState> {
  ConnectivityBloc() : super(const ConnectivityState.initial()) {
    on<ConnectivityStarted>(_onStarted);
    on<ConnectivityChanged>(_onChanged);
  }

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  Future<void> _onStarted(
    ConnectivityStarted event,
    Emitter<ConnectivityState> emit,
  ) async {
    final results = await Connectivity().checkConnectivity();
    add(ConnectivityChanged(results));
    await _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen(
      (results) => add(ConnectivityChanged(results)),
    );
  }

  void _onChanged(
    ConnectivityChanged event,
    Emitter<ConnectivityState> emit,
  ) {
    final available = event.results.any((result) => result != ConnectivityResult.none);
    emit(ConnectivityState(isNetworkAvailable: available));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
