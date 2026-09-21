import 'package:flutter_test/flutter_test.dart';
import 'package:khanya_pos/core/sync/sync_state.dart';

void main() {
  test('sync state exposes pending offline operations', () {
    const state = SyncState(
      phase: SyncPhase.offline,
      pendingOperations: 3,
      message: 'Waiting for connectivity',
    );

    expect(state.phase, SyncPhase.offline);
    expect(state.pendingOperations, 3);
    expect(state.message, 'Waiting for connectivity');
  });
}
