import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

class RealtimeClient {
  WebSocketChannel? _channel;

  Stream<Map<String, dynamic>> connect(Uri uri) {
    _channel?.sink.close();
    _channel = WebSocketChannel.connect(uri);
    return _channel!.stream.map(
      (message) => jsonDecode(message as String) as Map<String, dynamic>,
    );
  }

  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
  }
}
