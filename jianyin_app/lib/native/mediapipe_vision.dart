import '../envelope/landmark_point.dart';
import 'vision_frame.dart';

/// One detected hand from MediaPipe Hand Landmarker.
class DetectedHand {
  const DetectedHand({
    required this.landmarks,
    required this.handedness,
    required this.score,
  });

  /// MediaPipe Hands 21 points (image-normalized).
  final List<LandmarkPoint> landmarks;

  /// `"Left"` or `"Right"` from the model (subject view / camera convention).
  final String handedness;
  final double score;
}

class PoseDetectionResult {
  const PoseDetectionResult({required this.landmarks});

  /// Full pose landmark list (MediaPipe Pose index order).
  final List<LandmarkPoint> landmarks;
}

class HandsDetectionResult {
  const HandsDetectionResult({required this.hands});

  final List<DetectedHand> hands;
}

/// Dual-platform vision backend (real MethodChannel or fake for tests).
abstract class MediaPipeVision {
  Future<void> ensureReady();

  Future<PoseDetectionResult?> detectPose(VisionFrame frame);

  Future<HandsDetectionResult?> detectHands(VisionFrame frame);

  Future<void> dispose();
}
