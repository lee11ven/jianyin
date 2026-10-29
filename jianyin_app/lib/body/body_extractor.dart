import '../config/perception_thresholds.dart';
import '../native/mediapipe_vision.dart';
import '../native/vision_frame.dart';
import 'body_frame_builder.dart';
import 'body_types.dart';

/// Multi-organ branch: Pose subset + compact face quantities.
///
/// Runs first in the same-tick order. Provides body axes for trajectory.
abstract class BodyExtractor {
  /// Process one preview frame aligned to the activity-segment clock.
  Future<BodyTickResult> extract({
    required int ts,
    required Object frame,
  });

  Future<void> dispose();
}

/// Stub until MediaPipe Pose + Face are linked.
class StubBodyExtractor implements BodyExtractor {
  @override
  Future<BodyTickResult> extract({
    required int ts,
    required Object frame,
  }) async {
    return const BodyTickResult();
  }

  @override
  Future<void> dispose() async {}
}

/// MediaPipe Pose → nose/shoulders body frame (MVP; no Face / nonmanual).
class MediaPipeBodyExtractor implements BodyExtractor {
  MediaPipeBodyExtractor({
    required MediaPipeVision vision,
    this.thresholds = PerceptionThresholds.defaults,
    BodyFrameBuilder? builder,
  })  : _vision = vision,
        _builder = builder ?? BodyFrameBuilder(thresholds: thresholds);

  final MediaPipeVision _vision;
  final PerceptionThresholds thresholds;
  final BodyFrameBuilder _builder;
  int _missStreak = 0;
  BodyTickResult lastResult = const BodyTickResult();

  @override
  Future<BodyTickResult> extract({
    required int ts,
    required Object frame,
  }) async {
    if (frame is! VisionFrame) {
      lastResult = const BodyTickResult();
      return lastResult;
    }
    final pose = await _vision.detectPose(frame);
    if (pose == null || pose.landmarks.isEmpty) {
      _missStreak++;
      lastResult = BodyTickResult(
        hintShowUpperBody: _missStreak >= thresholds.nAnchor,
      );
      return lastResult;
    }
    final built = _builder.build(pose.landmarks);
    if (built.body == null) {
      _missStreak++;
      lastResult = BodyTickResult(
        hintShowUpperBody: _missStreak >= thresholds.nAnchor,
        wristL: built.wristL,
        wristR: built.wristR,
      );
      return lastResult;
    }
    _missStreak = 0;
    lastResult = BodyTickResult(
      body: built.body,
      wristL: built.wristL,
      wristR: built.wristR,
    );
    return lastResult;
  }

  @override
  Future<void> dispose() async {}
}
