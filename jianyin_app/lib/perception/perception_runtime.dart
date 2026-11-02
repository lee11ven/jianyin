import '../body/body_extractor.dart';
import '../config/perception_thresholds.dart';
import '../envelope/csl_channels.dart';
import '../envelope/envelope_assembler.dart';
import '../envelope/landmark_point.dart';
import '../native/mediapipe_vision.dart';
import '../native/mediapipe_vision_channel.dart';
import 'viewpoint.dart';
import '../skeleton/hand_skeleton_extractor.dart';
import '../skeleton/hand_types.dart';
import '../trajectory/trajectory_tracker.dart';
import 'perception_pipeline.dart';

/// Wires MediaPipe-backed extractors into PerceptionPipeline.
class PerceptionRuntime {
  PerceptionRuntime({
    MediaPipeVision? vision,
    this.thresholds = PerceptionThresholds.defaults,
    this.sessionId = 'local',
    EnvelopeAssembler? assembler,
    this.valves = ViewpointValves.defaults,
  })  : vision = vision ?? MediaPipeVisionChannel(),
        _assembler = assembler;

  final MediaPipeVision vision;
  final PerceptionThresholds thresholds;
  final String sessionId;
  final EnvelopeAssembler? _assembler;

  /// 机位 4 阀（设置页持久化值，冷启动加载，不热更新）。
  final ViewpointValves valves;

  late final MediaPipeBodyExtractor body = MediaPipeBodyExtractor(
    vision: vision,
    thresholds: thresholds,
  );
  late final DefaultTrajectoryTracker trajectory = DefaultTrajectoryTracker(
    thresholds: thresholds,
  );
  late final MediaPipeHandSkeletonExtractor skeleton =
      MediaPipeHandSkeletonExtractor(
    vision: vision,
    thresholds: thresholds,
  );
  late final PerceptionPipeline pipeline = PerceptionPipeline(
    body: body,
    trajectory: trajectory,
    skeleton: skeleton,
    assembler: _assembler,
  );

  CslChannelsLandmarks? lastLandmarks;

  /// 机位估计器与最近一次结论（N0/A1–A8 + 绿/黄/红三档）；阀来自 [valves]。
  late final ViewpointEstimator viewpointEstimator =
      ViewpointEstimator(valves: valves);
  ViewpointEstimate viewpoint = ViewpointEstimate.unavailable;

  /// 以最近一拍的身体结果刷新机位档，返回结论供抽帧器与 UI 使用。
  ViewpointEstimate refreshViewpoint() {
    viewpoint = viewpointEstimator.estimate(body.lastResult);
    return viewpoint;
  }

  /// False on x86 emulators / missing native libs — camera UI still runs.
  bool visionReady = false;
  String? visionError;

  bool get hintShowUpperBody => body.lastResult.hintShowUpperBody;

  /// The gesture_skeleton_envelope_v1 catalog document.
  /// Call this once after WS connect to send identity to server.
  Map<String, dynamic>? getCatalogJson() {
    return pipeline.assembler.catalog().toJson();
  }

  Future<bool> ensureReady() async {
    try {
      await vision.ensureReady();
      visionReady = true;
      visionError = null;
      return true;
    } catch (e) {
      visionReady = false;
      visionError = e.toString();
      return false;
    }
  }

  /// Same-tick perception, plus injects hand tips into trajectory tracker.
  /// Returns the uplink message JSON or null if vision is not ready.
  Future<Map<String, dynamic>?> tickEnvelope({
    required int ts,
    required Object frame,
    required HandState handStatePrior,
    String viewpointClass = 'N0',
    bool forcePathGap = false,
    bool omitHands = false,
  }) async {
    if (!visionReady) return null;
    final msg = await pipeline.tick(
      ts: ts,
      sessionId: sessionId,
      frame: frame,
      handStatePrior: handStatePrior,
      viewpointClass: viewpointClass,
      forcePathGap: forcePathGap,
      omitHands: omitHands,
    );
    lastLandmarks = msg;
    // Inject hand skeleton tips into trajectory for next tick path.tips.
    final hands = msg?.hands?.points;
    if (hands != null) {
      trajectory.injectTips(
        left: List<LandmarkPoint>.from(hands.sublist(0, 21)),
        right: List<LandmarkPoint>.from(hands.sublist(21, 42)),
      );
    }
    return msg?.toJson();
  }

  /// Preview-only mode when native MediaPipe cannot load (e.g. x86 emulator).
  void markVisionUnavailable([String? reason]) {
    visionReady = false;
    visionError = reason ?? visionError ?? 'MediaPipe unavailable';
  }

  Future<void> dispose() async {
    await pipeline.dispose();
    await vision.dispose();
  }
}
