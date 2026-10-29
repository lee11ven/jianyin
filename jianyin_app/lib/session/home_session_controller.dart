import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/home/sense_status.dart';
import '../ws/app_ws_client.dart';
import '../ws/ws_events.dart';
import 'api_client.dart';
import 'auth_store.dart';
import 'session_models.dart';

/// Home lifecycle: REST session + `/ws/app` + caption state.
///
/// Enter Home → (camera ready) → token → POST /sessions → WS.
/// Leave Home → close WS (no reconnect) → REST stop.
class HomeSessionController extends ChangeNotifier {
  HomeSessionController({
    AuthStore? authStore,
    ApiClient? apiClient,
    AppWsClient? wsClient,
  })  : _auth = authStore ?? AuthStore(),
        _api = apiClient ?? ApiClient(),
        _ws = wsClient ?? AppWsClient();

  final AuthStore _auth;
  final ApiClient _api;
  final AppWsClient _ws;

  StreamSubscription<WsEvent>? _wsSub;
  Timer? _retryTimer;

  bool _homeActive = false;
  bool _cameraReady = false;
  bool _starting = false;
  bool _stopping = false;

  String? _sessionId;
  String? _token;
  String? _lastErrorHint;
  int _startAttempt = 0;

  SenseStatus sense = SenseStatus.offline;
  VoiceStatus voice = VoiceStatus.idle;
  String currentCaption = '';
  List<String> captionHistory = [];

  String? get sessionId => _sessionId;
  bool get wsOpen => _ws.isOpen;

  SenseMeta get meta {
    if (_lastErrorHint != null && sense == SenseStatus.offline) {
      return SenseMeta(
        label: '掉线',
        hint: _lastErrorHint!,
        hintTone: HintTone.warn,
      );
    }
    return senseStates[sense]!;
  }

  bool get vpOffline => sense == SenseStatus.offline;

  String get vpCaption => sense == SenseStatus.offline
      ? '机位矫正 · 连接中断'
      : '机位矫正 · 头肩双手入框';

  Future<void> start() async {
    _homeActive = true;
    _lastErrorHint = null;
    sense = SenseStatus.offline;
    notifyListeners();
    _wsSub ??= _ws.events.listen(_onWsEvent);
    if (_cameraReady) {
      await _ensureSession();
    }
  }

  /// Call when rear camera preview is ready (architecture step 2 → 3).
  Future<void> onCameraReady() async {
    _cameraReady = true;
    if (_homeActive) {
      await _ensureSession();
    }
  }

  Future<void> _ensureSession() async {
    if (!_homeActive || !_cameraReady || _starting || _ws.isOpen) return;
    if (_sessionId != null && _token != null) {
      // Session exists but socket down — reconnect handled by ws/.
      return;
    }

    _starting = true;
    _retryTimer?.cancel();
    sense = SenseStatus.offline;
    _lastErrorHint = '正在连接服务…';
    notifyListeners();

    try {
      final auth = await _auth.requireAppToken();
      if (!_homeActive) return;
      _token = auth.token;

      final session = await _api.createSession(
        token: auth.token,
        usePhoneLandmarks: true,
      );
      if (!_homeActive) {
        await _api.stopSession(token: auth.token, sessionId: session.sessionId);
        return;
      }

      _sessionId = session.sessionId;
      _startAttempt = 0;
      await _ws.connect(
        token: auth.token,
        deviceId: auth.deviceId,
        sessionId: session.sessionId,
        wsUrl: session.wsUrl,
      );
    } on ApiException catch (e) {
      debugPrint('session start failed: ${e.code}');
      _lastErrorHint = _hintForApi(e);
      sense = SenseStatus.offline;
      notifyListeners();
      if (e.code == 'unauthorized' || e.statusCode == 401) {
        await _auth.clear();
        _token = null;
        _lastErrorHint = '请先登录后再进入识别页';
        notifyListeners();
      } else {
        _scheduleStartRetry();
      }
    } catch (e) {
      debugPrint('session start failed: $e');
      _lastErrorHint = '无法连接服务，请检查局域网网关';
      sense = SenseStatus.offline;
      notifyListeners();
      _scheduleStartRetry();
    } finally {
      _starting = false;
    }
  }

  void _scheduleStartRetry() {
    if (!_homeActive || !_cameraReady) return;
    _startAttempt += 1;
    final exp = _startAttempt.clamp(1, 6);
    final ms = (500 * (1 << (exp - 1))).clamp(500, 30000);
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(milliseconds: ms), () {
      if (_homeActive && _cameraReady && !_ws.isOpen && _sessionId == null) {
        unawaited(_ensureSession());
      }
    });
  }

  void onLandmarks(Map<String, dynamic> json) {
    if (!_homeActive || _sessionId == null || !_ws.isOpen) return;

    final payload = Map<String, dynamic>.from(json);
    payload['sessionId'] = _sessionId;

    final hasHands = payload.containsKey('hands');
    final path = payload['path'];
    final pathGap = path is Map && path['gap'] == true;
    if (hasHands || (path is Map && !pathGap)) {
      if (sense == SenseStatus.idle || sense == SenseStatus.translating) {
        sense = SenseStatus.recognizing;
        notifyListeners();
      }
    }

    _ws.sendLandmarks(payload);
  }

  void _onWsEvent(WsEvent event) {
    switch (event) {
      case WsConnected():
        _lastErrorHint = null;
        sense = SenseStatus.idle;
        notifyListeners();
      case WsDisconnected(:final reason):
        if (!_homeActive) return;
        if (reason == 'session_replaced') {
          _lastErrorHint = '已在其他设备继续会话';
          _sessionId = null;
        } else if (reason == 'unauthorized') {
          _lastErrorHint = '登录已失效，请重新登录';
          _sessionId = null;
          unawaited(_auth.clear());
        } else if (reason == 'session_not_found') {
          _lastErrorHint = '会话无效，正在重试…';
          _sessionId = null;
          _scheduleStartRetry();
        } else if (_ws.state == AppWsState.reconnecting) {
          _lastErrorHint = '连接已断开，正在重试…';
        } else {
          _lastErrorHint = '连接已断开';
        }
        sense = SenseStatus.offline;
        voice = VoiceStatus.idle;
        notifyListeners();
      case WsReconnecting(:final attempt):
        _lastErrorHint = '连接已断开，正在重试（$attempt）…';
        sense = SenseStatus.offline;
        notifyListeners();
      case WsRecognition(:final text):
        if (text.isEmpty) return;
        sense = SenseStatus.translating;
        currentCaption = text;
        captionHistory = [...captionHistory, text];
        if (captionHistory.length > 4) {
          captionHistory = captionHistory.sublist(captionHistory.length - 4);
        }
        notifyListeners();
        // Settle back to idle shortly if no further activity.
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (!_homeActive) return;
          if (sense == SenseStatus.translating && _ws.isOpen) {
            sense = SenseStatus.idle;
            currentCaption = '';
            notifyListeners();
          }
        });
      case WsSpeechMeta(:final accepted):
        if (!accepted) {
          _lastErrorHint = '音频格式不支持（仅接受 PCM 流）';
          notifyListeners();
          return;
        }
        voice = VoiceStatus.speaking;
        notifyListeners();
      case WsAudioHeader():
        break;
      case WsAudioBinary():
        // P1-3 TTS pipeline will consume PCM; keep voice speaking briefly.
        voice = VoiceStatus.speaking;
        notifyListeners();
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!_homeActive) return;
          if (voice == VoiceStatus.speaking) {
            voice = VoiceStatus.idle;
            notifyListeners();
          }
        });
      case WsErrorEvent(:final code, :final message):
        _lastErrorHint = message.isNotEmpty ? message : code;
        if (code == 'device_busy') {
          _lastErrorHint = '边缘设备忙，请稍后重试';
        }
        notifyListeners();
      case WsSessionLifecycle():
        break;
    }
  }

  String _hintForApi(ApiException e) {
    switch (e.code) {
      case 'device_busy':
        return '边缘设备忙，请稍后重试';
      case 'unauthorized':
        return '鉴权失败，请重新登录';
      default:
        return e.message.isNotEmpty ? e.message : '服务暂时不可用';
    }
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    _homeActive = false;
    _cameraReady = false;
    _starting = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _startAttempt = 0;

    final token = _token;
    final sid = _sessionId;
    _sessionId = null;
    _token = null;

    await _ws.close(reason: 'leave_home', allowReconnect: false);

    if (token != null && sid != null) {
      try {
        await _api.stopSession(token: token, sessionId: sid);
      } catch (e) {
        debugPrint('stop session failed: $e');
      }
    }

    sense = SenseStatus.offline;
    voice = VoiceStatus.idle;
    currentCaption = '';
    _lastErrorHint = null;
    notifyListeners();
    _stopping = false;
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_wsSub?.cancel());
    _wsSub = null;
    unawaited(_ws.dispose());
    _api.close();
    super.dispose();
  }
}
