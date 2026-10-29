import '../body/body_types.dart';
import '../config/perception_thresholds.dart';
import '../envelope/csl_channels.dart';
import '../envelope/landmark_point.dart';
import 'path_types.dart';

/// Activity-segment trajectory branch (~30 Hz wrist / palm / tips).
///
/// Reads [BodyAxes] when anchors are valid (`path.space = body`);
/// otherwise emits `space = image` and `anchor = false`.
abstract class TrajectoryTracker {
  Future<PathTickResult> sample({
    required int ts,
    required BodyAxes? axes,
    required bool forceGap,
    LandmarkPoint? wristLeft,
    LandmarkPoint? wristRight,
  });

  Future<void> dispose();
}

/// Stub until hand tracking + optical-flow fallback are wired.
class StubTrajectoryTracker implements TrajectoryTracker {
  @override
  Future<PathTickResult> sample({
    required int ts,
    required BodyAxes? axes,
    required bool forceGap,
    LandmarkPoint? wristLeft,
    LandmarkPoint? wristRight,
  }) async {
    final space = axes != null ? 'body' : 'image';
    return PathTickResult(
      path: PathChannel(
        space: space,
        anchor: axes != null,
        gap: forceGap || true,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

/// Fixed-beat wrist path with explicit gap and body/image space switch.
class DefaultTrajectoryTracker implements TrajectoryTracker {
  DefaultTrajectoryTracker({
    this.thresholds = PerceptionThresholds.defaults,
  });

  final PerceptionThresholds thresholds;

  @override
  Future<PathTickResult> sample({
    required int ts,
    required BodyAxes? axes,
    required bool forceGap,
    LandmarkPoint? wristLeft,
    LandmarkPoint? wristRight,
  }) async {
    final space = axes != null ? 'body' : 'image';
    final anchor = axes != null;
    if (forceGap || (wristLeft == null && wristRight == null)) {
      return PathTickResult(
        path: PathChannel(space: space, anchor: anchor, gap: true),
      );
    }

    HandPathSample? mapHand(LandmarkPoint? wrist) {
      if (wrist == null || wrist.v <= 0) return null;
      final image = wrist;
      final out = axes != null
          ? axes.toBody(image, v: image.v)
          : image;
      final palm = LandmarkPoint(
        x: out.x,
        y: out.y,
        z: out.z,
        v: out.v * thresholds.palmVisibilityScale,
      );
      return HandPathSample(
        wrist: out,
        palm: palm,
        tips: {
          for (final name in const [
            'thumb',
            'index',
            'middle',
            'ring',
            'pinky',
          ])
            name: LandmarkPoint.zero,
        },
      );
    }

    return PathTickResult(
      path: PathChannel(
        space: space,
        anchor: anchor,
        gap: false,
        left: mapHand(wristLeft) ?? HandPathSample.absent(),
        right: mapHand(wristRight) ?? HandPathSample.absent(),
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
