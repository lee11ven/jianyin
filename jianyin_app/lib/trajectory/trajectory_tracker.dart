import '../body/body_types.dart';
import '../config/perception_thresholds.dart';
import '../envelope/csl_channels.dart';
import '../envelope/landmark_point.dart';
import '../envelope/catalog.dart';
import 'path_types.dart';

/// Activity-segment trajectory branch (~30 Hz wrist / palm / tips).
///
/// Reads [BodyAxes] when anchors are valid (path.space = body);
/// otherwise emits space = image and anchor = false.
abstract class TrajectoryTracker {
  Future<PathTickResult> sample({
    required int ts,
    required BodyAxes? axes,
    required bool forceGap,
    LandmarkPoint? wristLeft,
    LandmarkPoint? wristRight,
  });

  /// Inject hand skeleton 21-point lists so tips can be propagated into path.
  void injectTips({
    required List<LandmarkPoint>? left,
    required List<LandmarkPoint>? right,
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
  void injectTips({
    required List<LandmarkPoint>? left,
    required List<LandmarkPoint>? right,
  }) {}

  @override
  Future<void> dispose() async {}
}

/// Fixed-beat wrist path with explicit gap and body/image space switch.
///
/// Tips are injected from HandSkeletonExtractor after each tick so that
/// path.left.tips / path.right.tips carry the real fingertip coordinates.
class DefaultTrajectoryTracker implements TrajectoryTracker {
  DefaultTrajectoryTracker({
    this.thresholds = PerceptionThresholds.defaults,
  });

  final PerceptionThresholds thresholds;

  /// Last injected tip lists (cleared each sample call).
  List<LandmarkPoint>? _injectedLeft;
  List<LandmarkPoint>? _injectedRight;

  @override
  void injectTips({
    required List<LandmarkPoint>? left,
    required List<LandmarkPoint>? right,
  }) {
    _injectedLeft = left;
    _injectedRight = right;
  }

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

    HandPathSample? mapHand({
      required LandmarkPoint? wrist,
      required List<LandmarkPoint>? tips,
    }) {
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
      final mappedTips = <String, LandmarkPoint>{
        for (final entry in EnvelopeCatalog.tipLocals.entries)
          entry.key: _tipFromSkeleton(
            tips,
            entry.value,
            axes: axes,
          ),
      };
      return HandPathSample(
        wrist: out,
        palm: palm,
        tips: mappedTips,
      );
    }

    return PathTickResult(
      path: PathChannel(
        space: space,
        anchor: anchor,
        gap: false,
        left: mapHand(
          wrist: wristLeft,
          tips: _injectedLeft,
        ) ?? HandPathSample.absent(),
        right: mapHand(
          wrist: wristRight,
          tips: _injectedRight,
        ) ?? HandPathSample.absent(),
      ),
    );
  }

  /// Extract a tip landmark from the 21-point skeleton at [localIndex].
  /// Converts to body coords when [axes] is present.
  LandmarkPoint _tipFromSkeleton(
    List<LandmarkPoint>? tips,
    int localIndex, {
    required BodyAxes? axes,
  }) {
    if (tips == null || localIndex >= tips.length) {
      return LandmarkPoint.zero;
    }
    final p = tips[localIndex];
    if (p.v <= 0) return LandmarkPoint.zero;
    if (axes != null) {
      return axes.toBody(p, v: p.v);
    }
    return p;
  }

  @override
  Future<void> dispose() async {
    _injectedLeft = null;
    _injectedRight = null;
  }
}
