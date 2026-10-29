import '../body/body_extractor.dart';
import '../config/perception_thresholds.dart';
import '../envelope/csl_channels.dart';
import '../native/mediapipe_vision.dart';
import '../native/mediapipe_vision_channel.dart';
import '../skeleton/hand_skeleton_extractor.dart';
import '../skeleton/hand_types.dart';
import '../trajectory/trajectory_tracker.dart';
import 'perception_pipeline.dart';

/// Wires MediaPipe-backed extractors into [PerceptionPipeline].
class PerceptionRuntime {
  PerceptionRuntime({
    MediaPipeVision? vision,
    this.thresholds = PerceptionThresholds.defaults,
    this.sessionId = 'local',
  }) : vision = vision ?? MediaPipeVisionChannel();

  final MediaPipeVision vision;
  final PerceptionThresholds thresholds;
  final String sessionId;

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
  );

  CslChannelsLandmarks? lastLandmarks;

  /// False on x86 emulators / missing native libs — camera UI still runs.
  bool visionReady = false;
  String? visionError;

  bool get hintShowUpperBody => body.lastResult.hintShowUpperBody;

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

  Future<CslChannelsLandmarks?> tick({
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
    return msg;
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
