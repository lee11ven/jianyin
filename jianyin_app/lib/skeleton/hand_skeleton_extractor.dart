import '../config/perception_thresholds.dart';
import '../envelope/landmark_point.dart';
import '../native/mediapipe_vision.dart';
import '../native/vision_frame.dart';
import 'hand_track_state.dart';
import 'hand_types.dart';

/// Handshape branch: MediaPipe Hands → 42-point packing + slot tracking.
///
/// Runs after body / trajectory in the same tick. Omitting `hands` does **not**
/// imply `path.gap`.
abstract class HandSkeletonExtractor {
  Future<SkeletonTickResult> extract({
    required int ts,
    required Object frame,
    required HandState handStatePrior,
    String viewpointClass = 'N0',
    bool omitHands = false,
  });

  /// Latest fused wrist tips for optional trajectory injection (next tick).
  LandmarkPoint? get lastWristLeft;
  LandmarkPoint? get lastWristRight;

  Future<void> dispose();
}

/// Stub until MediaPipe Hands Tasks SDK is linked (P1-0 → P1-2).
class StubHandSkeletonExtractor implements HandSkeletonExtractor {
  @override
  LandmarkPoint? get lastWristLeft => null;

  @override
  LandmarkPoint? get lastWristRight => null;

  @override
  Future<SkeletonTickResult> extract({
    required int ts,
    required Object frame,
    required HandState handStatePrior,
    String viewpointClass = 'N0',
    bool omitHands = false,
  }) async {
    return SkeletonTickResult(handState: handStatePrior);
  }

  @override
  Future<void> dispose() async {}
}

/// N0 MediaPipe Hands → fixed 42 slots with track/label fusion.
class MediaPipeHandSkeletonExtractor implements HandSkeletonExtractor {
  MediaPipeHandSkeletonExtractor({
    required MediaPipeVision vision,
    this.thresholds = PerceptionThresholds.defaults,
    HandSlotFuser? fuser,
  })  : _vision = vision,
        _fuser = fuser ?? HandSlotFuser(thresholds: thresholds);

  final MediaPipeVision _vision;
  final PerceptionThresholds thresholds;
  final HandSlotFuser _fuser;

  List<LandmarkPoint>? _smoothLeft;
  List<LandmarkPoint>? _smoothRight;
  LandmarkPoint? _lastWristLeft;
  LandmarkPoint? _lastWristRight;

  @override
  LandmarkPoint? get lastWristLeft => _lastWristLeft;

  @override
  LandmarkPoint? get lastWristRight => _lastWristRight;

  @override
  Future<SkeletonTickResult> extract({
    required int ts,
    required Object frame,
    required HandState handStatePrior,
    String viewpointClass = 'N0',
    bool omitHands = false,
  }) async {
    if (omitHands || frame is! VisionFrame || handStatePrior == HandState.none) {
      return SkeletonTickResult(handState: handStatePrior);
    }

    final detected = await _vision.detectHands(frame);
    if (detected == null || detected.hands.isEmpty) {
      return const SkeletonTickResult(handState: HandState.none);
    }

    final fused = _fuser.fuse(
      detections: detected.hands,
      handStatePrior: handStatePrior,
    );

    final left = _gateAndSmooth(fused.left, isLeft: true);
    final right = _gateAndSmooth(fused.right, isLeft: false);
    if (left == null && right == null) {
      _lastWristLeft = null;
      _lastWristRight = null;
      return const SkeletonTickResult(handState: HandState.none);
    }

    _lastWristLeft = left?.isNotEmpty == true ? left![0] : null;
    _lastWristRight = right?.isNotEmpty == true ? right![0] : null;

    return SkeletonTickResult(
      hands: packHands42(left: left, right: right),
      handState: fused.state,
    );
  }

  List<LandmarkPoint>? _gateAndSmooth(
    List<LandmarkPoint>? src, {
    required bool isLeft,
  }) {
    if (src == null || src.length < 21) {
      if (isLeft) {
        _smoothLeft = null;
      } else {
        _smoothRight = null;
      }
      return null;
    }
    var valid = 0;
    for (final p in src) {
      if (p.v >= thresholds.vMinJoint) valid++;
    }
    if (valid / 21.0 < thresholds.rMinValid) {
      if (isLeft) {
        _smoothLeft = null;
      } else {
        _smoothRight = null;
      }
      return null;
    }

    final prev = isLeft ? _smoothLeft : _smoothRight;
    final out = <LandmarkPoint>[];
    for (var i = 0; i < 21; i++) {
      final cur = src[i];
      if (cur.v < thresholds.vMinJoint) {
        out.add(LandmarkPoint.zero);
        continue;
      }
      if (prev != null && i < prev.length && prev[i].v > 0) {
        final a = thresholds.smoothAlpha;
        out.add(
          LandmarkPoint(
            x: a * cur.x + (1 - a) * prev[i].x,
            y: a * cur.y + (1 - a) * prev[i].y,
            z: a * cur.z + (1 - a) * prev[i].z,
            v: cur.v,
          ),
        );
      } else {
        out.add(cur);
      }
    }
    if (isLeft) {
      _smoothLeft = out;
    } else {
      _smoothRight = out;
    }
    return out;
  }

  @override
  Future<void> dispose() async {
    _fuser.reset();
    _smoothLeft = null;
    _smoothRight = null;
  }
}
