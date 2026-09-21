import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _profileKey = 'khanya.session_profile';
  final FlutterSecureStorage _storage;

  Future<AuthSession?> readProfile({
    required String accessToken,
    required String refreshToken,
  }) async {
    final raw = await _storage.read(key: _profileKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return AuthSession.fromProfileJson(
        jsonDecode(raw) as Map<String, dynamic>,
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeProfile(AuthSession session) => _storage.write(
        key: _profileKey,
        value: jsonEncode(session.toProfileJson()),
      );

  Future<void> clear() => _storage.delete(key: _profileKey);
}
