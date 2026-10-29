import '../envelope/csl_channels.dart';
import '../envelope/landmark_point.dart';

/// Handedness prior from frame selection.
enum HandState { none, left, right, both }

/// One-tick handshape result (may omit [hands] when quality fails).
class SkeletonTickResult {
  const SkeletonTickResult({
    this.hands,
    this.handState = HandState.none,
  });

  final HandsChannel? hands;
  final HandState handState;
}

/// Build fixed-length 42-point packing from left/right 21-point lists.
HandsChannel packHands42({
  List<LandmarkPoint>? left,
  List<LandmarkPoint>? right,
}) {
  final points = List<LandmarkPoint>.generate(42, (_) => LandmarkPoint.zero);
  void fill(int base, List<LandmarkPoint>? src) {
    if (src == null) return;
    for (var i = 0; i < 21 && i < src.length; i++) {
      points[base + i] = src[i];
    }
  }

  fill(0, left);
  fill(21, right);
  return HandsChannel(points: points);
}
