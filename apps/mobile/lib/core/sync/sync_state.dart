import 'package:equatable/equatable.dart';

enum SyncPhase { idle, syncing, offline, conflict, failed }

class SyncState extends Equatable {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pendingOperations = 0,
    this.message,
  });

  final SyncPhase phase;
  final int pendingOperations;
  final String? message;

  @override
  List<Object?> get props => [phase, pendingOperations, message];
}
