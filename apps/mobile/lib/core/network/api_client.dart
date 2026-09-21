import 'package:dio/dio.dart';

typedef RequestHeadersProvider = Future<Map<String, String>> Function();

class ApiClient {
  ApiClient({required String baseUrl, RequestHeadersProvider? requestHeadersProvider})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
            headers: const {'Accept': 'application/json'},
          ),
        ) {
    if (requestHeadersProvider != null) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            options.headers.addAll(await requestHeadersProvider());
            handler.next(options);
          },
        ),
      );
    }
  }

  final Dio dio;
}
