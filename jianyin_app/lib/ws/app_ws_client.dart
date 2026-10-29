import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';
import 'ws_events.dart';

enum AppWsState { idle, connecting, open, reconnecting, closed }

/// `/ws/app` client: heartbeat, drop-old landmarks uplink, downlink routing.
class AppWsClient {
  AppWsClient();

  final _events = StreamController<WsEvent>.broadcast();
  Stream<WsEvent> get events => _events.stream;

  AppWsState state = AppWsState.idle;
  String? sessionId;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _deadTimer;
  Timer? _reconnectTimer;

  String? _token;
  String? _deviceId;
  String? _wsUrl;
  bool _allowReconnect = false;
  bool _disposed = false;
  int _reconnectAttempt = 0;

  /// Pending audio.header waiting for the next binary frame.
  WsAudioHeader? _pendingAudioHeader;

  /// Drop-old: keep only the newest landmarks while a send is in flight / backlog.
  Map<String, dynamic>? _pendingLandmarks;
  bool _sendingLandmarks = false;

  bool get isOpen => state == AppWsState.open;

  Future<void> connect({
    required String token,
    required String deviceId,
    required String sessionId,
    String? wsUrl,
  }) async {
    _token = token;
    _deviceId = deviceId;
    this.sessionId = sessionId;
    _wsUrl = wsUrl;
    _allowReconnect = true;
    _reconnectAttempt = 0;
    await _open();
  }

  Future<void> _open() async {
    if (_disposed) return;
    _cancelTimers(keepReconnect: true);
    await _tearChannel();

    final token = _token;
    final deviceId = _deviceId;
    final sid = sessionId;
    if (token == null || deviceId == null || sid == null) return;

    state = _reconnectAttempt > 0 ? AppWsState.reconnecting : AppWsState.connecting;
    final uri = ApiConfig.appWsUri(
      wsUrl: _wsUrl,
      deviceId: deviceId,
      sessionId: sid,
    );

    try {
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
      );
      _channel = channel;
      await channel.ready;
      if (_disposed || _channel != channel) {
        await channel.sink.close();
        return;
      }
      state = AppWsState.open;
      _reconnectAttempt = 0;
      _armDeadWatch();
      _startPing();
      _sub = channel.stream.listen(
        _onData,
        onError: (Object e) => _onSocketLost('$e'),
        onDone: () => _onSocketLost('closed'),
        cancelOnError: true,
      );
      _events.add(WsConnected(sessionId: sid));
      _flushLandmarks();
    } catch (e) {
      debugPrint('WS connect failed: $e');
      _onSocketLost('$e');
    }
  }

  void sendLandmarks(Map<String, dynamic> payload) {
    if (!_allowReconnect && state != AppWsState.open) return;
    _pendingLandmarks = payload;
    _flushLandmarks();
  }

  void _flushLandmarks() {
    if (_sendingLandmarks || state != AppWsState.open) return;
    final next = _pendingLandmarks;
    if (next == null) return;
    _pendingLandmarks = null;
    _sendingLandmarks = true;
    try {
      _channel?.sink.add(jsonEncode(next));
      _touchAlive();
    } catch (e) {
      debugPrint('WS landmarks send failed: $e');
      _pendingLandmarks ??= next;
    } finally {
      _sendingLandmarks = false;
      if (_pendingLandmarks != null) {
        scheduleMicrotask(_flushLandmarks);
      }
    }
  }

  void _onData(dynamic data) {
    _touchAlive();
    if (data is List<int>) {
      final header = _pendingAudioHeader;
      _pendingAudioHeader = null;
      if (header != null) {
        _events.add(WsAudioBinary(header: header, bytes: data));
      }
      return;
    }

    if (data is! String) return;
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(data);
      if (decoded is! Map) return;
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = '${json['type'] ?? ''}';
    switch (type) {
      case 'pong':
        break;
      case 'recognition':
        _events.add(WsRecognition.fromJson(json));
        break;
      case 'speech':
        _events.add(WsSpeechMeta.fromJson(json));
        break;
      case 'audio.header':
        final header = WsAudioHeader.fromJson(json);
        _pendingAudioHeader = header;
        _events.add(header);
        break;
      case 'error':
        final err = WsErrorEvent.fromJson(json);
        _events.add(err);
        _handleFatalError(err);
        break;
      case 'session.started':
      case 'session.stopped':
        _events.add(
          WsSessionLifecycle(
            type: type,
            sessionId: '${json['sessionId'] ?? sessionId ?? ''}',
          ),
        );
        break;
      case 'device.online':
        break;
      default:
        break;
    }
  }

  void _handleFatalError(WsErrorEvent err) {
    switch (err.code) {
      case 'unauthorized':
      case 'session_replaced':
      case 'session_not_found':
        _allowReconnect = false;
        unawaited(close(reason: err.code));
      default:
        break;
    }
  }

  void _onSocketLost(String reason) {
    if (_disposed) return;
    final wasOpen = state == AppWsState.open ||
        state == AppWsState.connecting ||
        state == AppWsState.reconnecting;
    _cancelTimers(keepReconnect: true);
    unawaited(_tearChannel());
    if (!wasOpen && state == AppWsState.closed) return;

    state = AppWsState.closed;
    _pendingAudioHeader = null;
    _events.add(WsDisconnected(reason: reason));

    if (_allowReconnect && !_disposed) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempt += 1;
    final exp = _reconnectAttempt.clamp(1, 6);
    var ms = ApiConfig.reconnectInitialBackoff.inMilliseconds * (1 << (exp - 1));
    if (ms > ApiConfig.reconnectMaxBackoff.inMilliseconds) {
      ms = ApiConfig.reconnectMaxBackoff.inMilliseconds;
    }
    final delay = Duration(milliseconds: ms);
    state = AppWsState.reconnecting;
    _events.add(WsReconnecting(attempt: _reconnectAttempt, delay: delay));
    _reconnectTimer = Timer(delay, () {
      if (_allowReconnect && !_disposed) {
        unawaited(_open());
      }
    });
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(ApiConfig.heartbeatInterval, (_) {
      if (state != AppWsState.open) return;
      try {
        _channel?.sink.add(
          jsonEncode({
            'type': 'ping',
            'protocolVersion': ApiConfig.protocolVersion,
            'ts': DateTime.now().millisecondsSinceEpoch,
          }),
        );
      } catch (_) {
        _onSocketLost('ping failed');
      }
    });
  }

  void _armDeadWatch() {
    _deadTimer?.cancel();
    _deadTimer = Timer(ApiConfig.deadConnectionTimeout, () {
      _onSocketLost('dead connection');
    });
  }

  void _touchAlive() {
    if (state == AppWsState.open) {
      _armDeadWatch();
    }
  }

  /// Close socket. [allowReconnect]=false stops Home leave / stop paths.
  Future<void> close({String? reason, bool allowReconnect = false}) async {
    _allowReconnect = allowReconnect;
    _reconnectTimer?.cancel();
    _cancelTimers();
    await _tearChannel();
    state = AppWsState.closed;
    _pendingLandmarks = null;
    _pendingAudioHeader = null;
    if (!_events.isClosed) {
      _events.add(WsDisconnected(reason: reason ?? 'closed'));
    }
  }

  Future<void> _tearChannel() async {
    await _sub?.cancel();
    _sub = null;
    final ch = _channel;
    _channel = null;
    try {
      await ch?.sink.close();
    } catch (_) {}
  }

  void _cancelTimers({bool keepReconnect = false}) {
    _pingTimer?.cancel();
    _pingTimer = null;
    _deadTimer?.cancel();
    _deadTimer = null;
    if (!keepReconnect) {
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await close(reason: 'dispose', allowReconnect: false);
    await _events.close();
  }
}
