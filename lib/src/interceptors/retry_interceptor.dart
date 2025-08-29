import 'package:dio/dio.dart';

class RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final Duration delay;

  RetryInterceptor({
    required this.dio,
    this.retries = 3,
    this.delay = const Duration(milliseconds: 500),
  });

  @override
  Future onError(DioException err, ErrorInterceptorHandler handler) async {
    var attempt = (err.requestOptions.extra['x-retry_attempt'] ?? 0) as int;
    while (attempt < retries) {
      attempt++;
      err.requestOptions.extra['x-retry_attempt'] = attempt;
      print('Retrying... Attempt: $attempt');
      print(err.message);
      await Future.delayed(delay * (1 << attempt));
      try {
        final response = await dio.fetch(err.requestOptions);
        return handler.resolve(response);
      } catch (_) {}
    }
    return super.onError(err, handler);
  }
}
