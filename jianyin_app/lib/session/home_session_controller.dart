import 'dart:async';

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../camera/frame_sampler.dart';
import '../features/home/sense_status.dart';
import '../native/keep_alive.dart';
import '../perception/hint_keys.dart';
import '../perception/viewpoint.dart';
import '../tts/jitter_buffer.dart';
import '../tts/tts_pipeline.dart';
import '../ws/app_ws_client.dart';
import '../ws/ws_events.dart';
import 'api_client.dart';
import 'auth_store.dart';
import 'session_models.dart';

/// Tracks the detected face center in normalized camera-frame coordinates (0..1).
/// Rebuilt by HomeSessionController from the nose landmark each tick.
class FaceTracker extends ChangeNotifier {
  double? _x;
  double? _y;
  int _lastTs = 0;

  double? get x => _x;
  double? get y => _y;
  bool get hasFace => _x != null;

  /// Update face position with a 50 ms debounce to avoid excessive rebuilds.
  void update(double x, double y, [int now = 0]) {
    final ts = now;
    if (ts - _lastTs < 50) return;
    _lastTs = ts;
    _x = x.clamp(0.0, 1.0);
    _y = y.clamp(0.0, 1.0);
    notifyListeners();
  }

  void reset() {
    if (_x == null) return;
    _x = null;
    _y = null;
    notifyListeners();
  }
}

/// Convert a face position from the camera preview frame to the overlay frame.
///
/// The overlay frame is centered on screen at overlayFrameWidthDp while the
/// camera fills the full screenWidthDp. The vertical scale is identical since
/// both use full-screen height; only the horizontal axis needs correction.
Offset faceToOverlayPos({
  required Offset face,
  required double overlayFrameWidthDp,
  required double screenWidthDp,
}) {
  final scaleX = overlayFrameWidthDp / screenWidthDp;
  return Offset(face.dx * scaleX, face.dy);
}

/// Home lifecycle: REST session + /ws/app + caption state.
///
/// Enter Home -> (camera ready) -> token -> POST /sessions -> WS.
/// Leave Home -> close WS (no reconnect) -> REST stop.
class HomeSessionController extends ChangeNotifier {
  HomeSessionController({
    AuthStore? authStore,
    ApiClient? apiClient,
    AppWsClient? wsClient,
    TtsPipeline? tts,
    KeepAliveChannel? keepAlive,
  })  : _auth = authStore ?? AuthStore(),
        _api = apiClient ?? ApiClient(),
        _ws = wsClient ?? AppWsClient(),
        _tts = tts ?? TtsPipeline(),
        _keepAlive = keepAlive ?? KeepAliveChannel();

  final AuthStore _auth;
  final ApiClient _api;
  final AppWsClient _ws;

  /// 流式播音管线（Recv → Assembler → JitterBuffer → Player）。
  final TtsPipeline _tts;

  /// 端侧保活（Android 前台服务；iOS 由背景音频模式提供）。
  final KeepAliveChannel _keepAlive;

  /// 最近一次机位档与抖动档（由感知侧每拍上报）。
  ViewpointEstimate viewpoint = ViewpointEstimate.unavailable;
  ShakeTier shakeTier = ShakeTier.stable;

  /// 同屏提示仲裁（按 risks.md 全序取一条）。
  final HintArbiter hints = HintArbiter();

  /// 机位档：掉线时按红档显示取景框。
  ValveBand get vpBand =>
      sense == SenseStatus.offline ? ValveBand.red : viewpoint.band;

  /// 当前应展示的提示文案（无提示时回落机位取景口吻）。
  String get hintText {
    final key = hints.winner(DateTime.now().millisecondsSinceEpoch);
    return key.isNone ? '' : key.copy;
  }

  /// 感知侧每拍回调：刷新机位/抖动档并按档位点亮提示键。
  void onPerception(ViewpointEstimate estimate, ShakeTier tier) {
    viewpoint = estimate;
    shakeTier = tier;
    final now = DateTime.now().millisecondsSinceEpoch;
    hints.prune(now);

    if (estimate.band == ValveBand.green) {
      hints.clear(HintKey.showUpperBody);
    } else {
      // 黄档软提示、红档硬提示，均按 A1–A8 的对应键。
      hints.arm(estimate.className.hintKey, nowMs: now);
      if (estimate.className == ViewpointClass.n0) {
        hints.arm(HintKey.faceCamera, nowMs: now);
      }
    }
    if (tier == ShakeTier.heavy) {
      hints.arm(HintKey.holdSteady, nowMs: now);
    }
    notifyListeners();
  }

  final FaceTracker _faceTracker = FaceTracker();
  FaceTracker get faceTracker => _faceTracker;

  StreamSubscription<WsEvent>? _wsSub;
  Timer? _retryTimer;
  /// When Active ticks stop (no person / quiet), fall back to 就绪.
  Timer? _senseIdleTimer;
  static const _senseIdleAfter = Duration(milliseconds: 800);

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
    currentCaption = '';
    captionHistory = [];
    notifyListeners();
    _wsSub ??= _ws.events.listen(_onWsEvent);
    if (_cameraReady) {
      await _ensureSession();
    }
  }

  /// Call when rear camera preview is ready (architecture step 2 -> 3).
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
      // 播音 sink 与识别会话同生命周期：进 Home 打开，离开 / 退出时 flush + close。
      await _tts.ensureOpen();
      // 保活与识别会话同生命周期：仅 Home 存活期间运行前台服务。
      unawaited(_keepAlive.start());
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

  /// Called by CameraPreviewPanel.onLandmarks.
  ///
  /// The payload is either a csl_channels_v1 JSON (from envelope packer) or a
  /// gesture_skeleton_envelope_v1 catalog frame. We detect kind to route accordingly.
  void onLandmarks(Map<String, dynamic> json) {
    if (!_homeActive || _sessionId == null) return;

    final kind = json['kind'] as String?;
    final envelope = json['envelope'] as String?;

    // Catalog is sent by the WS client on connect; just log it.
    if (kind == 'catalog' && envelope == 'gesture_skeleton_envelope_v1') {
      debugPrint('[Envelope] catalog received from client (echo)');
      return;
    }

    if (!_ws.isOpen) return;

    final payload = Map<String, dynamic>.from(json);
    payload['sessionId'] = _sessionId;

    // If this is a full envelope frame, send it as-is.
    // Otherwise it is a csl_channels_v1 landmarks packet.
    final hasEnvelope = envelope == 'gesture_skeleton_envelope_v1' && kind == 'frame';
    if (hasEnvelope) {
      _ws.sendEnvelopeFrame(payload);
    } else {
      _ws.sendLandmarks(payload);
    }

    _updateSenseFromUplink(payload);
  }

  /// Formal sense rules while Home is active:
  /// WS down → 掉线; WS up + no person → 就绪; WS up + person → 识别中.
  void _updateSenseFromUplink(Map<String, dynamic> payload) {
    final nose = _payloadNose(payload);
    final hasPerson = nose != null;

    if (hasPerson) {
      _faceTracker.update(
        nose.$1,
        nose.$2,
        DateTime.now().millisecondsSinceEpoch,
      );
    } else {
      _faceTracker.reset();
    }

    if (sense == SenseStatus.offline) return;

    // Keep brief 转译中 until its own settle; still refresh presence watchdog.
    if (sense == SenseStatus.translating) {
      _armSenseIdleWatchdog();
      return;
    }

    final next =
        hasPerson ? SenseStatus.recognizing : SenseStatus.idle;

    if (hasPerson) {
      _armSenseIdleWatchdog();
    } else {
      _senseIdleTimer?.cancel();
      _senseIdleTimer = null;
    }

    if (next != sense) {
      sense = next;
      notifyListeners();
    }
  }

  /// Nose with usable coords → person / portrait present.
  ///
  /// 取值形状与 [noseFromUplink] 一致：上行 `body` 是**扁平**结构。
  (double, double)? _payloadNose(Map<String, dynamic> payload) =>
      noseFromUplink(payload);

  /// If presence probes stop (camera stall), leave 识别中 → 就绪.
  void _armSenseIdleWatchdog() {
    _senseIdleTimer?.cancel();
    _senseIdleTimer = Timer(_senseIdleAfter, () {
      if (!_homeActive || !_ws.isOpen) return;
      if (sense != SenseStatus.recognizing) return;
      _faceTracker.reset();
      sense = SenseStatus.idle;
      notifyListeners();
    });
  }

  void _onWsEvent(WsEvent event) {
    switch (event) {
      case WsConnected():
        _lastErrorHint = null;
        sense = SenseStatus.idle;
        currentCaption = '';
        captionHistory = [];
        notifyListeners();
      case WsDisconnected(:final reason):
        // 断线即收口：重连后 tts 为 Idle，不续播旧句残片。
        unawaited(_tts.flush());
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
        // Leave 转译中; next presence tick restores 识别中/就绪.
        Future<void>.delayed(const Duration(milliseconds: 800), () {
          if (!_homeActive) return;
          if (sense == SenseStatus.translating && _ws.isOpen) {
            sense = _faceTracker.hasFace
                ? SenseStatus.recognizing
                : SenseStatus.idle;
            currentCaption = '';
            notifyListeners();
          }
        });
      case WsSpeechMeta(:final accepted):
        _tts.onSpeech(event, sessionId: _sessionId);
        if (!accepted || _tts.lastRejection != null) {
          _lastErrorHint = '音频格式不支持（仅接受 PCM 流）';
        }
        _syncVoiceFromTts();
        notifyListeners();
      case WsAudioHeader():
        _tts.onHeader(event, sessionId: _sessionId);
      case WsAudioBinary(:final bytes, :final header):
        unawaited(_tts.onBinary(bytes, header: header).then((_) => _syncVoiceFromTts()));
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

  /// 播报状态以 TTS 管线状态机为准（不再使用占位定时器）。
  void _syncVoiceFromTts() {
    final next = switch (_tts.state) {
      PlaybackState.idle || PlaybackState.flushing => VoiceStatus.idle,
      PlaybackState.priming ||
      PlaybackState.playing ||
      PlaybackState.underrun =>
        VoiceStatus.speaking,
    };
    if (next != voice) {
      voice = next;
      notifyListeners();
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
    _senseIdleTimer?.cancel();
    _senseIdleTimer = null;
    _startAttempt = 0;

    final token = _token;
    final sid = _sessionId;
    _sessionId = null;
    _token = null;

    // 拆除顺序（architecture.md）：先收口播音与保活 → 关 WS → REST stop。
    await _tts.flush();
    await _keepAlive.stop();
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
    captionHistory = [];
    _lastErrorHint = null;
    _faceTracker.reset();
    notifyListeners();
    _stopping = false;
  }

  @override
  void dispose() {
    unawaited(stop());
    unawaited(_wsSub?.cancel());
    _wsSub = null;
    unawaited(_ws.dispose());
    unawaited(_tts.close());
    _api.close();
    super.dispose();
  }
}

/// 上行 `body` 通道的鼻尖探针：返回图像归一化 `(x, y)`；无人像锚点时为 null。
///
/// 线格式是**扁平**结构 —— `body['nose'] = {x,y,z,v}` —— 与
/// `docs/api/protocol.md` 的 `csl_channels_v1` 定义及 `BodyChannel.toJson()` 一致。
/// 为兼容历史写法，同时接受嵌套的 `body['points']['nose']`。
///
/// 可见性 `v <= 0` 或坐标越界（非图像归一化）视为未检出，避免用无效锚点驱动
/// 「识别中」状态与取景框。
(double, double)? noseFromUplink(Map<String, dynamic> payload) {
  final dynamic body = payload['body'];
  if (body is! Map) return null;

  final dynamic flatNose = body['nose'];
  final dynamic nested = body['points'];
  final dynamic nose = flatNose is Map
      ? flatNose
      : (nested is Map ? nested['nose'] : null);
  if (nose is! Map) return null;

  final nx = (nose['x'] as num?)?.toDouble();
  final ny = (nose['y'] as num?)?.toDouble();
  final nv = (nose['v'] as num?)?.toDouble() ?? 1.0;
  if (nx == null || ny == null) return null;
  if (nv <= 0 || nx < 0 || nx > 1 || ny < 0 || ny > 1) return null;
  return (nx, ny);
}
