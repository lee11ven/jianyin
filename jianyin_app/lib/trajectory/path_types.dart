import '../envelope/csl_channels.dart';

/// Trace point id used by cloud segment features.
///
/// Default wrist; fingertip when book-air / tip-driven motion.
enum PathTraceKind { wrist, thumbTip, indexTip, middleTip, ringTip, pinkyTip }

/// One activity-segment path tick.
class PathTickResult {
  const PathTickResult({
    required this.path,
    this.traceLeft = PathTraceKind.wrist,
    this.traceRight = PathTraceKind.wrist,
  });

  final PathChannel path;
  final PathTraceKind traceLeft;
  final PathTraceKind traceRight;
}
