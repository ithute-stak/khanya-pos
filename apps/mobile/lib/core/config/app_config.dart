import 'dart:io';

class AppConfig {
  const AppConfig._();

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'KHANYA_API_BASE_URL',
    defaultValue: '',
  );

  static String get apiBaseUrl {
    final configured = _configuredApiBaseUrl.trim();
    if (configured.isNotEmpty) return configured;

    // Android emulators reach the host through 10.0.2.2. Native desktop
    // clients can use the normal loopback address during local development.
    if (Platform.isAndroid) return 'http://10.0.2.2:8000/api/v1';
    return 'http://127.0.0.1:8000/api/v1';
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
