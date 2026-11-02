import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../config/perception_thresholds.dart';
import '../native/vision_frame.dart';
import '../skeleton/hand_types.dart';

/// 抽帧状态机四态：`Idle / Active / PeakHold / Reject`。
///
/// 语义见 docs/design/算法/客户端/视频流抽帧.md「自适应抽帧状态机」。
enum FrameSamplerPhase {
  /// 低采样（约 8–12 Hz 探测）。
  idle,

  /// 升采样（约 25 Hz），完整质量门控。
  active,

  /// 运动峰值保留：在最小间隔内保留能量峰值帧，抑制均匀抽稀漏关键帧。
  peakHold,

  /// 本帧拒发手形：重抖或红档机位；轨迹可写 `gap`。
  reject,
}

/// 摄像头抖动分档（稳 / 轻抖 / 重抖）。
enum ShakeTier { stable, light, heavy }

/// 一次抽帧决策（纯逻辑输出，便于单测）。
class FrameSamplerDecision {
  const FrameSamplerDecision({
    required this.phase,
    required this.shakeTier,
    required this.tick,
    required this.presenceOnly,
    required this.omitHands,
    required this.forcePathGap,
    required this.peakHold,
    required this.rejected,
  });

  final FrameSamplerPhase phase;
  final ShakeTier shakeTier;

  /// 本帧是否放行（进入感知管线）。
  final bool tick;

  /// 是否只做存在性探测（`Idle` 拍）。
  final bool presenceOnly;

  final bool omitHands;
  final bool forcePathGap;

  /// 是否由峰值保留而放行。
  final bool peakHold;

  /// 是否属于 `Reject`（重抖或红档机位）。
  final bool rejected;
}

/// 抽帧核心逻辑（纯 Dart）：状态机 + 抖动分档 + 质量/机位门控 + 峰值保留。
///
/// 与 I/O 解耦，便于单测；[FrameSampler] 负责相机帧转换与回调。
class FrameSamplerCore {
  FrameSamplerCore({this.thresholds = PerceptionThresholds.defaults});

  final PerceptionThresholds thresholds;

  FrameSamplerPhase phase = FrameSamplerPhase.idle;
  ShakeTier shakeTier = ShakeTier.stable;

  /// 机位档加严系数：黄档 `S_min`×1.15（正机位）/ ×1.32（斜机位）。
  double viewpointQualityScale = 1.0;

  /// 红档机位：不送手形 + 轨迹写 `gap`。
  bool viewpointRejects = false;

  int _onsetStreak = 0;
  DateTime? _lastMotionAt;
  DateTime? _lastTickAt;
  DateTime? _lastPeakAt;
  double _peakEnergy = 0;

  /// 抖动分档：以运动能量相对 `tOnset` 的倍数近似（单体图像可得的代理量）。
  ShakeTier tierFor(double motionEnergy) {
    if (thresholds.tOnset <= 0) return ShakeTier.stable;
    final ratio = motionEnergy / thresholds.tOnset;
    if (ratio >= thresholds.jHeavyFactor) return ShakeTier.heavy;
    if (ratio >= thresholds.jLightFactor) return ShakeTier.light;
    return ShakeTier.stable;
  }

  /// 处理一帧质量指标，返回本拍决策。
  FrameSamplerDecision onMetrics({
    required double motionEnergy,
    required double sharpness,
    required DateTime now,
  }) {
    final moving = motionEnergy >= thresholds.tOnset;
    if (moving) {
      _onsetStreak += 1;
      _lastMotionAt = now;
    } else {
      _onsetStreak = 0;
    }

    // Idle → Active：连续 2 帧有运动。
    if (phase == FrameSamplerPhase.idle || phase == FrameSamplerPhase.reject) {
      if (_onsetStreak >= 2) phase = FrameSamplerPhase.active;
    } else if (phase == FrameSamplerPhase.active || phase == FrameSamplerPhase.peakHold) {
      final quiet = _lastMotionAt == null ||
          now.difference(_lastMotionAt!).inMilliseconds >= thresholds.tQuietMs;
      if (quiet && !moving) phase = FrameSamplerPhase.idle;
    }

    shakeTier = tierFor(motionEnergy);

    final presenceOnly = phase == FrameSamplerPhase.idle;
    final minInterval =
        presenceOnly ? thresholds.deltaIdleMs : thresholds.deltaActiveMs;
    final throttled = _lastTickAt != null &&
        now.difference(_lastTickAt!).inMilliseconds < minInterval;

    // PeakHold：在节流窗口内保留运动能量峰值帧（有最小间隔限制）。
    var peakHold = false;
    if (!presenceOnly && throttled && moving) {
      final isNewPeak = motionEnergy > _peakEnergy * 1.15;
      final peakAllowed = _lastPeakAt == null ||
          now.difference(_lastPeakAt!).inMilliseconds >=
              thresholds.peakHoldMinIntervalMs;
      if (isNewPeak && peakAllowed) {
        peakHold = true;
        _lastPeakAt = now;
      }
    }
    if (moving && motionEnergy >= _peakEnergy) {
      _peakEnergy = motionEnergy;
    } else if (!moving) {
      _peakEnergy = 0;
    }

    if (throttled && !peakHold) {
      _restoreSteadyPhase();
      return FrameSamplerDecision(
        phase: phase,
        shakeTier: shakeTier,
        tick: false,
        presenceOnly: presenceOnly,
        omitHands: true,
        forcePathGap: presenceOnly,
        peakHold: false,
        rejected: false,
      );
    }

    // Reject：重抖或红档机位 → 本帧不送手形；轨迹写 gap。
    final rejected = !presenceOnly && (shakeTier == ShakeTier.heavy || viewpointRejects);
    final omitHands = presenceOnly ||
        rejected ||
        shakeTier == ShakeTier.heavy ||
        sharpness < thresholds.sMin * viewpointQualityScale;

    _lastTickAt = now;
    phase = rejected ? FrameSamplerPhase.reject : (peakHold ? FrameSamplerPhase.peakHold : phase);

    return FrameSamplerDecision(
      phase: phase,
      shakeTier: shakeTier,
      tick: true,
      presenceOnly: presenceOnly,
      omitHands: omitHands,
      forcePathGap: presenceOnly || rejected,
      peakHold: peakHold,
      rejected: rejected,
    );
  }

  /// 节流未放行时不要把 `peakHold/reject` 残留为当前态。
  void _restoreSteadyPhase() {
    if (phase == FrameSamplerPhase.peakHold || phase == FrameSamplerPhase.reject) {
      phase = _lastMotionAt == null ? FrameSamplerPhase.idle : FrameSamplerPhase.active;
    }
  }

  void reset() {
    phase = FrameSamplerPhase.idle;
    shakeTier = ShakeTier.stable;
    viewpointQualityScale = 1.0;
    viewpointRejects = false;
    _onsetStreak = 0;
    _lastMotionAt = null;
    _lastTickAt = null;
    _lastPeakAt = null;
    _peakEnergy = 0;
  }
}

/// 元数据 for one activity-segment tick request.
class FrameTickRequest {
  const FrameTickRequest({
    required this.ts,
    required this.frame,
    required this.handState,
    required this.omitHands,
    required this.forcePathGap,
    this.viewpointClass = 'N0',
    this.sharpness = 0,
    this.motionEnergy = 0,
    this.shakeTier = ShakeTier.stable,
  });

  final int ts;
  final VisionFrame frame;
  final HandState handState;
  final bool omitHands;
  final bool forcePathGap;
  final String viewpointClass;
  final double sharpness;
  final double motionEnergy;
  final ShakeTier shakeTier;
}

/// 相机帧时钟 + 四态机 + 质量/机位门控，驱动 [PerceptionPipeline.tick]。
class FrameSampler {
  FrameSampler({
    this.thresholds = PerceptionThresholds.defaults,
    required this.onTick,
    this.sensorOrientation = 90,
    FrameSamplerCore? core,
  }) : core = core ?? FrameSamplerCore(thresholds: thresholds);

  final PerceptionThresholds thresholds;
  final Future<void> Function(FrameTickRequest request) onTick;
  int sensorOrientation;
  final FrameSamplerCore core;

  FrameSamplerPhase get phase => core.phase;
  ShakeTier get shakeTier => core.shakeTier;
  HandState handState = HandState.none;

  Uint8List? _prevY;
  HandState _pendingHand = HandState.none;
  int _pendingHandStreak = 0;
  bool _busy = false;

  /// 机位黄档质量加严（由感知侧按上一拍的机位估计回填）。
  void setViewpointQualityScale(double scale) => core.viewpointQualityScale = scale;

  /// 机位红档：不送手形 + 轨迹写 `gap`（由感知侧回填）。
  void setViewpointRejects(bool rejects) => core.viewpointRejects = rejects;

  Future<void> onCameraImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      await _handle(image);
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(CameraImage image) async {
    final yPlane = image.planes.first;
    final metrics = measureYPlane(
      yBytes: yPlane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: yPlane.bytesPerRow,
      previousY: _prevY,
    );
    _prevY = Uint8List.fromList(yPlane.bytes);

    final now = DateTime.now();
    final decision = core.onMetrics(
      motionEnergy: metrics.motionEnergy,
      sharpness: metrics.sharpness,
      now: now,
    );
    _updateHandStateGuess(metrics.motionEnergy, decision);

    if (!decision.tick) return;

    final ts = now.millisecondsSinceEpoch;
    final vision = await cameraImageToVisionFrame(
      image,
      ts: ts,
      sensorOrientation: sensorOrientation,
    );
    if (vision == null) return;

    await onTick(
      FrameTickRequest(
        ts: ts,
        frame: vision,
        handState: decision.presenceOnly ? HandState.none : handState,
        omitHands: decision.omitHands,
        forcePathGap: decision.forcePathGap,
        sharpness: metrics.sharpness,
        motionEnergy: metrics.motionEnergy,
        shakeTier: decision.shakeTier,
      ),
    );
  }

  void _updateHandStateGuess(double energy, FrameSamplerDecision decision) {
    // MVP coarse prior: motion → both; otherwise keep previous until quiet.
    final guess = energy >= thresholds.tOnset ? HandState.both : handState;
    if (guess == _pendingHand) {
      _pendingHandStreak++;
    } else {
      _pendingHand = guess;
      _pendingHandStreak = 1;
    }
    if (_pendingHandStreak >= thresholds.nStableHand) {
      handState = _pendingHand;
    }
    if (decision.phase == FrameSamplerPhase.idle) {
      handState = HandState.none;
    }
  }

  void reset() {
    core.reset();
    handState = HandState.none;
    _prevY = null;
    _pendingHand = HandState.none;
    _pendingHandStreak = 0;
  }
}