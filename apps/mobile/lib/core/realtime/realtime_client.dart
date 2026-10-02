import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeClient {
  WebSocketChannel? _channel;
  Timer? _heartbeat;

  Stream<Map<String, dynamic>> connect(Uri uri) {
    final previous = _channel;
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    if (previous != null) unawaited(previous.sink.close());

    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!identical(_channel, channel)) return;
      channel.sink.add(
        jsonEncode({
          'type': 'ping',
          'sent_at': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    });

    return channel.stream.expand<Map<String, dynamic>>((message) {
      try {
        final decoded = jsonDecode(message as String);
        if (decoded is Map<String, dynamic>) return [decoded];
        if (decoded is Map) return [decoded.cast<String, dynamic>()];
      } catch (_) {
        // Ignore malformed socket frames rather than terminating realtime.
      }
      return const <Map<String, dynamic>>[];
    });
  }

  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await channel?.sink.close();
  }
}
