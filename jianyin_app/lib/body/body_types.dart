import '../envelope/csl_channels.dart';
import '../envelope/landmark_point.dart';

/// Result of the multi-organ branch for one tick.
class BodyTickResult {
  const BodyTickResult({
    this.body,
    this.nonmanual,
    this.hintShowUpperBody = false,
    this.wristL,
    this.wristR,
  });

  final BodyChannel? body;
  final NonmanualChannel? nonmanual;

  /// Continuous anchor failure → UX `hint.show_upper_body`.
  final bool hintShowUpperBody;

  /// Pose wrists for trajectory MVP (indices 15/16).
  final LandmarkPoint? wristL;
  final LandmarkPoint? wristR;

  bool get hasFrame => body != null;
}

/// Shoulder-normalized body axes (signer-right X, toward-nose Y, toward-camera Z).
class BodyAxes {
  const BodyAxes({
    required this.origin,
    required this.shoulderWidth,
    required this.right,
    required this.up,
    required this.zSign,
  });

  final LandmarkPoint origin;
  final double shoulderWidth;
  final LandmarkPoint right;
  final LandmarkPoint up;
  final int zSign;

  BodyFrame toFrame() => BodyFrame(
        origin: origin,
        shoulderWidth: shoulderWidth,
        right: right,
        up: up,
        zSign: zSign,
      );

  /// Convert image-normalized point into shoulder-width body coordinates.
  LandmarkPoint toBody(LandmarkPoint image, {required double v}) {
    final dx = image.x - origin.x;
    final dy = image.y - origin.y;
    final dz = image.z - origin.z;
    final s = shoulderWidth <= 1e-6 ? 1.0 : shoulderWidth;
    // Columns of R are +X,+Y,+Z in image space; p_body = R^T (p - O) / s.
    final bx = (right.x * dx + right.y * dy + right.z * dz) / s;
    final by = (up.x * dx + up.y * dy + up.z * dz) / s;
    final bz = zSign *
        ((right.y * up.z - right.z * up.y) * dx +
                (right.z * up.x - right.x * up.z) * dy +
                (right.x * up.y - right.y * up.x) * dz) /
            s;
    return LandmarkPoint(x: bx, y: by, z: bz, v: v);
  }
}
