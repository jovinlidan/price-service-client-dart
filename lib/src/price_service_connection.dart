import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:price_service_client/src/interceptors/remove_null_query_interceptor.dart';
import 'package:price_service_client/src/interceptors/retry_interceptor.dart';
import 'package:price_service_sdk/price_service_sdk.dart';

import 'resillient_web_socket.dart';
import 'utils.dart';

class PriceFeedRequestConfig {
  /// Optional verbose to request for verbose information from the service
  final bool? verbose;

  /// Optional binary to include the price feeds binary update data
  final bool? binary;

  /// Optional config for the websocket subscription to receive out of order updates
  final bool? allowOutOfOrder;

  const PriceFeedRequestConfig({this.verbose, this.binary, this.allowOutOfOrder});
}

class PriceServiceConnectionConfig {
  /// Timeout of each request (for all of retries). Default: 5000ms
  final Duration? timeout;

  /// Number of times a HTTP request will be retried before the API returns a failure. Default: 3.
  ///
  /// The connection uses exponential back-off for the delay between retries. However,
  /// it will timeout regardless of the retries at the configured `timeout` time.
  final int? httpRetries;

  /// Optional logger (e.g: console or any logging library) to log internal events
  final Logger? logger;

  /// Deprecated: use [priceFeedRequestConfig.verbose]
  final bool? verbose;

  /// Configuration for the price feed requests
  final PriceFeedRequestConfig? priceFeedRequestConfig;

  const PriceServiceConnectionConfig({
    this.timeout,
    this.httpRetries,
    this.logger,
    this.verbose,
    this.priceFeedRequestConfig,
  });
}

typedef PriceFeedUpdateCallback = void Function(PriceFeed priceFeed);

class PriceServiceConnection {
  late final Dio _httpClient;
  late final Logger _logger;

  ResilientWebSocket? _wsClient;
  late final String? _wsEndpoint;
  late final PriceFeedRequestConfig _priceFeedRequestConfig;
  late final Map<String, Set<PriceFeedUpdateCallback>> _priceFeedCallbacks;

  /// Custom handler for web socket errors (connection and message parsing).
  ///
  /// Default handler only logs the errors.
  late void Function(Object error) onWsError;

  /// Constructs a new Connection.
  ///
  /// [endpoint] endpoint URL to the price service. Example: https://website/example/
  /// [config] Optional PriceServiceConnectionConfig for custom configurations.
  PriceServiceConnection(String endpoint, {PriceServiceConnectionConfig? config}) {
    final log =
        config?.logger ?? Logger(level: Level.warning, printer: PrettyPrinter(methodCount: 0));
    _httpClient = Dio(
      BaseOptions(
        baseUrl: endpoint,
        connectTimeout: (config?.timeout ?? const Duration(milliseconds: 5000)),
        receiveTimeout: (config?.timeout ?? const Duration(milliseconds: 5000)),
        sendTimeout: (config?.timeout ?? const Duration(milliseconds: 5000)),
      ),
    );
    _httpClient.interceptors.add(
      RetryInterceptor(dio: _httpClient, retries: config?.httpRetries ?? 3),
    );
    _httpClient.interceptors.add(RemoveNullQueryInterceptor());

    // @DEBUG: Enable request/response logging
    // _httpClient.interceptors.add(
    //   LogInterceptor(
    //     request: true,
    //     requestHeader: true,
    //     requestBody: true,
    //     responseHeader: true,
    //     responseBody: true,
    //     error: true,
    //     logPrint: (obj) => print(obj),
    //   ),
    // );
    _logger = log;
    _priceFeedRequestConfig = PriceFeedRequestConfig(
      binary: config?.priceFeedRequestConfig?.binary,
      verbose: config?.priceFeedRequestConfig?.verbose ?? config?.verbose,
      allowOutOfOrder: config?.priceFeedRequestConfig?.allowOutOfOrder,
    );
    _wsEndpoint = makeWebsocketUrl(endpoint);
    _priceFeedCallbacks = {};
    onWsError = ((error) {
      final logger = log;
      logger.e(error);
    });
  }

  /// Fetch Latest PriceFeeds of given price ids.
  /// This will throw an axios error if there is a network problem or the price service returns a non-ok response (e.g: Invalid price ids)
  Future<List<PriceFeed>?> getLatestPriceFeeds(List<String> priceIds) async {
    if (priceIds.isEmpty) return <PriceFeed>[];

    final resp = await _httpClient.get<List<dynamic>>(
      '/api/latest_price_feeds',
      queryParameters: {
        'ids[]': priceIds,
        'verbose': _priceFeedRequestConfig.verbose,
        'binary': _priceFeedRequestConfig.binary,
      },
    );
    final data = resp.data ?? [];
    return data.map((json) => PriceFeed.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Fetch latest VAA of given price ids.
  /// This will throw an axios error if there is a network problem or the price service returns a non-ok response (e.g: Invalid price ids)
  ///
  /// This function is coupled to wormhole implementation.
  Future<List<String>> getLatestVaas(List<String> priceIds) async {
    final resp = await _httpClient.get<List<dynamic>>(
      '/api/latest_vaas',
      queryParameters: {'ids[]': priceIds},
    );
    final data = resp.data ?? [];
    return data.cast<String>();
  }

  /// Fetch the earliest VAA of the given price id that is published since the given publish time.
  /// This will throw an error if the given publish time is in the future, or if the publish time
  /// is old and the price service endpoint does not have a db backend for historical requests.
  /// This will throw an axios error if there is a network problem or the price service returns a non-ok response (e.g: Invalid price id)
  ///
  /// This function is coupled to wormhole implemntation.
  Future<({String vaa, int publishTime})> getVaa(String priceId, int publishTime) async {
    final resp = await _httpClient.get<Map<String, dynamic>>(
      '/api/get_vaa',
      queryParameters: {'id': priceId, 'publish_time': publishTime},
    );
    final data = resp.data ?? const {};
    return (vaa: data['vaa'] as String, publishTime: (data['publishTime'] as num).toInt());
  }

  /// Fetch the PriceFeed of the given price id that is published since the given publish time.
  /// This will throw an error if the given publish time is in the future, or if the publish time
  /// is old and the price service endpoint does not have a db backend for historical requests.
  /// This will throw an axios error if there is a network problem or the price service returns a non-ok response (e.g: Invalid price id)
  Future<PriceFeed?> getPriceFeed(String priceId, int publishTime) async {
    final resp = await _httpClient.get<Map<String, dynamic>>(
      '/api/get_price_feed',
      queryParameters: {
        'id': priceId,
        'publish_time': publishTime,
        'verbose': _priceFeedRequestConfig.verbose,
        'binary': _priceFeedRequestConfig.binary,
      },
    );
    if (resp.data == null) return null;
    return PriceFeed.fromJson(resp.data!);
  }

  /// Fetch the list of available price feed ids.
  /// This will throw an axios error if there is a network problem or the price service returns a non-ok response.
  Future<List<String>> getPriceFeedIds() async {
    final resp = await _httpClient.get<List<dynamic>>('/api/price_feed_ids');
    return (resp.data ?? const <dynamic>[]).cast<String>();
  }

  /// Subscribe to updates for given price ids.
  ///
  /// It will start a websocket connection if it's not started yet.
  /// Also, it won't throw any exception if given price ids are invalid or connection errors. Instead,
  /// it calls `connection.onWsError`. If you want to handle the errors you should set the
  /// `onWsError` function to your custom error handler.
  Future<void> subscribePriceFeedUpdates(List<String> priceIds, PriceFeedUpdateCallback cb) async {
    if (_wsClient == null) {
      await startWebSocket();
    }
    priceIds = priceIds.map(removeLeading0xIfExists).toList();

    final List<String> newPriceIds = [];
    for (final id in priceIds) {
      if (!_priceFeedCallbacks.containsKey(id)) {
        _priceFeedCallbacks[id] = <PriceFeedUpdateCallback>{};
        newPriceIds.add(id);
      }
      _priceFeedCallbacks[id]!.add(cb);
    }

    if (newPriceIds.isNotEmpty) {
      final message = <String, dynamic>{
        'type': 'subscribe',
        'ids': newPriceIds,
        'verbose': _priceFeedRequestConfig.verbose,
        'binary': _priceFeedRequestConfig.binary,
        'allow_out_of_order': _priceFeedRequestConfig.allowOutOfOrder,
      };
      await _wsClient?.send(jsonEncode(message));
    }
  }

  /// Unsubscribe from updates for given price ids.
  ///
  /// It will close the websocket connection if it's not subscribed to any price feed updates anymore.
  /// Also, it won't throw any exception if given price ids are invalid or connection errors. Instead,
  /// it calls `connection.onWsError`. If you want to handle the errors you should set the
  /// `onWsError` function to your custom error handler.
  Future<void> unsubscribePriceFeedUpdates(
    List<String> priceIds, {
    PriceFeedUpdateCallback? cb,
  }) async {
    if (_wsClient == null) {
      await startWebSocket();
    }

    priceIds = priceIds.map(removeLeading0xIfExists).toList();
    final removedPriceIds = <String>[];

    for (final id in priceIds) {
      if (_priceFeedCallbacks.containsKey(id)) {
        bool isRemoved = false;

        if (cb == null) {
          _priceFeedCallbacks.remove(id);
          isRemoved = true;
        } else {
          _priceFeedCallbacks[id]!.remove(cb);
          if (_priceFeedCallbacks[id]!.isEmpty) {
            _priceFeedCallbacks.remove(id);
            isRemoved = true;
          }
        }

        if (isRemoved) {
          removedPriceIds.add(id);
        }
      }
    }

    if (removedPriceIds.isNotEmpty) {
      final message = <String, dynamic>{'type': 'unsubscribe', 'ids': removedPriceIds};
      await _wsClient?.send(jsonEncode(message));
    }

    if (_priceFeedCallbacks.isEmpty) {
      closeWebSocket();
    }
  }

  /// Starts connection websocket.
  ///
  /// This function is called automatically upon subscribing to price feed updates.
  Future<void> startWebSocket() async {
    if (_wsEndpoint == null) {
      throw StateError('Websocket endpoint is undefined.');
    }

    _wsClient = ResilientWebSocket(_wsEndpoint, _logger);

    _wsClient?.onError = (error) => onWsError(error);

    // resubscribe existing ids on reconnect
    _wsClient?.onReconnect = () {
      if (_priceFeedCallbacks.isNotEmpty) {
        final message = <String, dynamic>{
          'type': 'subscribe',
          'ids': _priceFeedCallbacks.keys.toList(),
          'verbose': _priceFeedRequestConfig.verbose,
          'binary': _priceFeedRequestConfig.binary,
          'allow_out_of_order': _priceFeedRequestConfig.allowOutOfOrder,
        };
        _logger.i('Resubscribing to existing price feeds.');
        _wsClient?.send(jsonEncode(message));
      }
    };

    _wsClient!.onMessage = (dynamic data) {
      final text = data is String ? data : utf8.decode((data as List<int>));
      _logger.i('Received message $text');

      Map<String, dynamic> message;
      try {
        message = jsonDecode(text) as Map<String, dynamic>;
      } catch (e, st) {
        _logger.e('Error parsing message as JSON: $text $e', stackTrace: st);
        onWsError(e);
        return;
      }

      final type = message['type'];
      if (type == 'response') {
        if (message['status'] == 'error') {
          final err = message['error'] ?? 'Unknown WS error';
          _logger.e('Error response from the websocket server $err');
          onWsError(StateError(err.toString()));
        }
      } else if (type == 'price_update') {
        try {
          final priceFeed = PriceFeed.fromJson(message['price_feed'] as Map<String, dynamic>);
          final cbs = _priceFeedCallbacks[priceFeed.id];
          if (cbs != null) {
            for (final cb in cbs) {
              cb(priceFeed);
            }
          }
        } catch (e, st) {
          _logger.e('Error parsing price_update payload $e', stackTrace: st);
          onWsError(e);
        }
      } else {
        _logger.w('Ignoring unsupported server response: $text');
      }
    };

    await _wsClient!.startWebSocket();
  }

  void closeWebSocket() {
    _wsClient?.closeWebSocket();
    _wsClient = null;
    _priceFeedCallbacks.clear();
  }
}
