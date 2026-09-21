import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeClient {
  WebSocketChannel? _channel;
  Timer? _heartbeat;

  Stream<Map<String, dynamic>> connect(Uri uri) {
    close();
    _channel = WebSocketChannel.connect(uri);
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      _channel?.sink.add('ping');
    });
    return _channel!.stream.map(
      (message) => jsonDecode(message as String) as Map<String, dynamic>,
    );
  }

  Future<void> close() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
