import 'package:dio/dio.dart';

typedef RequestHeadersProvider = Future<Map<String, String>> Function();
typedef UnauthorizedHandler = Future<bool> Function();

class ApiClient {
  ApiClient({required String baseUrl, RequestHeadersProvider? requestHeadersProvider})
      : _requestHeadersProvider = requestHeadersProvider,
        dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
          ),
        ) {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          await _applyContextHeaders(options.headers);
          handler.next(options);
        },
        onError: (error, handler) async {
          final alreadyRetried = error.requestOptions.extra['khanyaAuthRetried'] == true;
          final skipRefresh = error.requestOptions.extra['skipAuthRefresh'] == true;
          final shouldRefresh = error.response?.statusCode == 401 &&
              !alreadyRetried &&
              !skipRefresh &&
              _unauthorizedHandler != null;
          if (!shouldRefresh) {
            handler.next(error);
            return;
          }

          final refreshed = await _unauthorizedHandler!();
          if (!refreshed) {
            handler.next(error);
            return;
          }

          final request = error.requestOptions;
          request.extra['khanyaAuthRetried'] = true;
          await _applyContextHeaders(request.headers);
          try {
            final response = await dio.fetch<dynamic>(request);
            handler.resolve(response);
          } on DioException catch (retryError) {
            handler.next(retryError);
          }
        },
      ),
    );
  }

  final Dio dio;
  final RequestHeadersProvider? _requestHeadersProvider;
  UnauthorizedHandler? _unauthorizedHandler;

  Future<void> _applyContextHeaders(Map<String, dynamic> target) async {
    final provider = _requestHeadersProvider;
    if (provider == null) return;
    final contextual = await provider();
    for (final entry in contextual.entries) {
      if (entry.key.toLowerCase() == 'authorization') {
        // Authentication must always follow the latest refreshed access token.
        target[entry.key] = entry.value;
      } else {
        // A caller may deliberately pin tenant/branch headers, notably when
        // replaying an offline operation created under an earlier context.
        target.putIfAbsent(entry.key, () => entry.value);
      }
    }
  }

  void setUnauthorizedHandler(UnauthorizedHandler handler) {
    _unauthorizedHandler = handler;
  }
}
