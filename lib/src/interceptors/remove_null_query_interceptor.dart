import 'package:dio/dio.dart';

class RemoveNullQueryInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.queryParameters.removeWhere((key, value) => value == null);

    options.headers.removeWhere((key, value) => value == null);

    super.onRequest(options, handler);
  }
}
