class AppConfig {
  const AppConfig._();

  static const productionApiBaseUrl =
      'https://api.khanya.ithute.co.ls/api/v1';

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'KHANYA_API_BASE_URL',
    defaultValue: productionApiBaseUrl,
  );

  static String get apiBaseUrl {
    final configured = _configuredApiBaseUrl.trim();
    return configured.isEmpty ? productionApiBaseUrl : configured;
  }

  static Uri tenantWebSocketUri({
    required String tenantId,
    required String accessToken,
  }) {
    final apiUri = Uri.parse(apiBaseUrl);
    final normalizedPath = apiUri.path.endsWith('/')
        ? apiUri.path.substring(0, apiUri.path.length - 1)
        : apiUri.path;
    return apiUri.replace(
      scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
      path: '$normalizedPath/ws/tenants/$tenantId',
      queryParameters: {'access_token': accessToken},
    );
  }
}
