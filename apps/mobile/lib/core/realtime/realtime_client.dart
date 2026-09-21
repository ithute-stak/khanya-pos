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
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      if (identical(_channel, channel)) channel.sink.add('ping');
    });
    return channel.stream.map(
      (message) => jsonDecode(message as String) as Map<String, dynamic>,
    );
  }

  Future<void> close() async {
    final channel = _channel;
    _channel = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await channel?.sink.close();
  }
}
