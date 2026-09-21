import 'package:dio/dio.dart';
import 'package:khanya_pos/core/network/api_client.dart';
import 'package:khanya_pos/core/security/session_store.dart';
import 'package:khanya_pos/core/security/token_store.dart';
import 'package:khanya_pos/core/session/session_context.dart';
import 'package:khanya_pos/features/auth/domain/auth_session.dart';

class AuthRepository {
  AuthRepository({
    required ApiClient apiClient,
    required TokenStore tokenStore,
    required SessionStore sessionStore,
    required SessionContext sessionContext,
  })  : _apiClient = apiClient,
        _tokenStore = tokenStore,
        _sessionStore = sessionStore,
        _sessionContext = sessionContext;

  final ApiClient _apiClient;
  final TokenStore _tokenStore;
  final SessionStore _sessionStore;
  final SessionContext _sessionContext;

  Future<AuthSession> login({required String identifier, required String password}) async {
    final response = await _apiClient.dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'identifier': identifier.trim(), 'password': password},
      options: Options(extra: {'skipAuthRefresh': true}),
    );
    final pair = _tokenPair(response.data!);
    await _tokenStore.write(pair);
    _sessionContext.updateAccessToken(pair.accessToken);
    final session = await _loadSession(pair);
    await _sessionStore.writeProfile(session);
    return session;
  }

  Future<AuthSession?> restore() async {
    final pair = await _tokenStore.read();
    if (pair == null) return null;
    _sessionContext.updateAccessToken(pair.accessToken);
    try {
      final session = await _loadSession(pair);
      await _sessionStore.writeProfile(session);
      return session;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) rethrow;
      final currentPair = await _tokenStore.read() ?? pair;
      final cached = await _sessionStore.readProfile(
        accessToken: currentPair.accessToken,
        refreshToken: currentPair.refreshToken,
      );
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<bool> refreshAccessToken() async {
    final pair = await _tokenStore.read();
    if (pair == null) return false;
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': pair.refreshToken},
        options: Options(extra: {'skipAuthRefresh': true}),
      );
      final refreshed = _tokenPair(response.data!);
      await _tokenStore.write(refreshed);
      _sessionContext.updateAccessToken(refreshed.accessToken);
      final cached = await _sessionStore.readProfile(
        accessToken: refreshed.accessToken,
        refreshToken: refreshed.refreshToken,
      );
      if (cached != null) await _sessionStore.writeProfile(cached);
      return true;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await clearLocalSession();
      }
      return false;
    }
  }

  Future<void> rememberSession(AuthSession session) => _sessionStore.writeProfile(session);

  Future<void> logout() async {
    try {
      await _apiClient.dio.post<void>('/auth/logout');
    } catch (_) {
      // Local sign-out must remain possible if the server is unavailable.
    }
    await clearLocalSession();
  }

  Future<void> clearLocalSession() async {
    await _tokenStore.clear();
    await _sessionStore.clear();
    _sessionContext.clear();
  }

  Future<AuthSession> _loadSession(TokenPair requestedPair) async {
    final response = await _apiClient.dio.get<Map<String, dynamic>>(
      '/auth/me',
      options: Options(headers: {'Authorization': 'Bearer ${requestedPair.accessToken}'}),
    );
    final data = response.data!;
    final memberships = (data['memberships'] as List<dynamic>? ?? const [])
        .map((value) => BusinessMembership.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);

    // The 401 interceptor may have rotated the token pair while /auth/me was
    // in flight. Always build the restored session from the latest secure pair.
    final currentPair = await _tokenStore.read() ?? requestedPair;
    final userId = data['user_id'].toString();
    final cached = await _sessionStore.readProfile(
      accessToken: currentPair.accessToken,
      refreshToken: currentPair.refreshToken,
    );
    final previous = cached?.userId == userId ? cached : null;

    BusinessMembership? selectedMembership;
    final previousTenantId = previous?.selectedTenantId;
    if (previousTenantId != null) {
      for (final membership in memberships) {
        if (membership.tenantId == previousTenantId) {
          selectedMembership = membership;
          break;
        }
      }
    }
    selectedMembership ??= memberships.isEmpty ? null : memberships.first;

    final previousBranchId = previous?.selectedBranchId;
    final selectedBranchId = previousBranchId != null &&
            selectedMembership != null &&
            selectedMembership.branchIds.contains(previousBranchId)
        ? previousBranchId
        : selectedMembership != null && selectedMembership.branchIds.isNotEmpty
            ? selectedMembership.branchIds.first
            : null;

    return AuthSession(
      userId: userId,
      displayName: data['display_name'].toString(),
      email: data['email'].toString(),
      accessToken: currentPair.accessToken,
      refreshToken: currentPair.refreshToken,
      memberships: memberships,
      selectedTenantId: selectedMembership?.tenantId,
      selectedBranchId: selectedBranchId,
    );
  }

  TokenPair _tokenPair(Map<String, dynamic> data) => TokenPair(
        accessToken: data['access_token'].toString(),
        refreshToken: data['refresh_token'].toString(),
      );
}
