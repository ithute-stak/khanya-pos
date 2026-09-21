import 'dart:async';

class SessionContext {
  String? _accessToken;
  String? _tenantId;
  String? _branchId;
  Future<bool> Function()? _refreshCallback;
  Future<bool>? _refreshInFlight;

  String? get accessToken => _accessToken;
  String? get tenantId => _tenantId;
  String? get branchId => _branchId;
  bool get hasBusinessContext => _tenantId != null && _branchId != null;

  void apply({
    required String accessToken,
    required String? tenantId,
    required String? branchId,
  }) {
    _accessToken = accessToken;
    _tenantId = tenantId;
    _branchId = branchId;
  }

  void updateAccessToken(String accessToken) {
    _accessToken = accessToken;
  }

  void selectBusiness({required String tenantId, String? branchId}) {
    _tenantId = tenantId;
    _branchId = branchId;
  }

  void setRefreshCallback(Future<bool> Function() callback) {
    _refreshCallback = callback;
  }

  Future<bool> refreshAccessToken() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final callback = _refreshCallback;
    if (callback == null) return Future<bool>.value(false);
    final future = callback();
    _refreshInFlight = future;
    future.whenComplete(() => _refreshInFlight = null);
    return future;
  }

  Future<Map<String, String>> requestHeaders() async {
    final headers = <String, String>{};
    if (_accessToken case final token?) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (_tenantId case final tenantId?) {
      headers['X-Tenant-ID'] = tenantId;
    }
    if (_branchId case final branchId?) {
      headers['X-Branch-ID'] = branchId;
    }
    return headers;
  }

  void clear() {
    _accessToken = null;
    _tenantId = null;
    _branchId = null;
  }
}
