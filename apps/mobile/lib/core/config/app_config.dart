class AppConfig {
  const AppConfig._();

  static const apiBaseUrl = String.fromEnvironment(
    'KHANYA_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

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
