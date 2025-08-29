import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart';

/// It is 30s on the server and 3s is added for delays.
const _kPingTimeout = Duration(milliseconds: 30000 + 3000);

class ResilientWebSocket {
  final String _endpoint;
  final Logger? _logger;

  WebSocket? _wsClient;
  bool _wsUserClosed;
  int _wsFailedAttempts;

  void Function(Object error) onError;
  void Function(dynamic data) onMessage;
  void Function() onReconnect;

  Timer? _pingTimeout;

  ResilientWebSocket(this._endpoint, [this._logger])
    : onError = ((error) => _logger?.e(error)),
      onMessage = ((_) {}),
      onReconnect = (() {}),
      _wsUserClosed = true,
      _wsFailedAttempts = 0;

  /// Sends data on the WebSocket connection. The data in [data] must be either a String, or a List&lt;int&gt; holding bytes
  Future<void> send(dynamic data) async {
    _logger?.i('Sending $data');
    await _waitForMaybeReadyWebSocket();

    final ws = _wsClient;
    if (ws == null) {
      _logger?.e("Couldn't connect to the websocket server. Error callback is called.");
      return;
    }
    ws.add(data);
  }

  /// Start the socket if not already started.
  Future<void> startWebSocket() async {
    if (_wsClient != null) return;

    _logger?.i('Creating WebSocket client');

    try {
      _wsClient = await WebSocket.connect(_endpoint);
      _wsUserClosed = false;
      _wsFailedAttempts = 0;

      if (_wsClient?.readyState != WebSocket.open || _wsClient == null) {
        _logger?.e(
          "Starting WebSocket failed: Couldn't connect to the websocket server. Error callback is called.",
        );
        return;
      }

      _startHeartbeatWatcher();

      _wsClient!.listen(
        (data) {
          onMessage(data);
        },
        onError: (err) {
          onError(err ?? 'WebSocket error');
        },
        onDone: () async {
          await _retryConnection();
        },
        cancelOnError: true,
      );
    } catch (err) {
      await _retryConnection(err);
    }
  }

  void closeWebSocket() {
    _wsClient?.close();
    _wsUserClosed = true;
    _stopHeartbeatWatcher();
    _wsClient = null;
    _logger?.i('Closed WebSocket client');
  }

  void _startHeartbeatWatcher() {
    _logger?.i('Heartbeat');

    _pingTimeout?.cancel();
    _pingTimeout = Timer.periodic(_kPingTimeout, (_) {
      _logger?.w('Connection timed out (no inbound activity). Reconnecting...');
      _wsClient?.close();
      _restartUnexpectedClosedWebSocket();
    });
  }

  void _stopHeartbeatWatcher() {
    _pingTimeout?.cancel();
    _pingTimeout = null;
  }

  Future<void> _waitForMaybeReadyWebSocket() async {
    var waited = 0;
    while (_wsClient == null && _wsClient?.readyState != WebSocket.open) {
      if (waited >= 5000) {
        _wsClient?.close();
        return;
      } else {
        waited += 10;
        await Future.delayed(const Duration(milliseconds: 10));
      }
    }
  }

  Future<void> _restartUnexpectedClosedWebSocket() async {
    if (_wsUserClosed) return;

    await startWebSocket();
    await _waitForMaybeReadyWebSocket();

    if (_wsClient == null) {
      _logger?.e("Couldn't reconnect to websocket. Error callback is called.");
      return;
    }

    onReconnect();
  }

  Future<void> _retryConnection([Object? e]) async {
    _stopHeartbeatWatcher();
    _wsClient?.close();
    _wsClient = null;

    if (_wsUserClosed) {
      _logger?.i('User requested close; will not reconnect.');
      return;
    }

    _wsFailedAttempts += 1;
    final waitMs = _expoBackoffMs(_wsFailedAttempts);
    _logger?.e('WebSocket connect failed. Reconnecting after ${waitMs}ms. Error: $e');

    await Future.delayed(Duration(milliseconds: waitMs));
    await _restartUnexpectedClosedWebSocket();
  }

  /// Exponential backoff: 2^attempts * 100 ms
  int _expoBackoffMs(int attempts) => (1 << attempts) * 100;
}
