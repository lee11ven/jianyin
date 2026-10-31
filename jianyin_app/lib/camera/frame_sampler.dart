import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../config/perception_thresholds.dart';
import '../native/vision_frame.dart';
import '../skeleton/hand_types.dart';

enum FrameSamplerPhase { idle, active }

/// Metadata for one activity-segment tick request.
class FrameTickRequest {
  const FrameTickRequest({
    required this.ts,
    required this.frame,
    required this.handState,
    required this.omitHands,
    required this.forcePathGap,
    this.viewpointClass = 'N0',
    this.sharpness = 0,
    this.motionEnergy = 0,
  });

  final int ts;
  final VisionFrame frame;
  final HandState handState;
  final bool omitHands;
  final bool forcePathGap;
  final String viewpointClass;
  final double sharpness;
  final double motionEnergy;
}

/// Idle/Active clock + sharpness gate driving [PerceptionPipeline.tick].
class FrameSampler {
  FrameSampler({
    this.thresholds = PerceptionThresholds.defaults,
    required this.onTick,
    this.sensorOrientation = 90,
  });

  final PerceptionThresholds thresholds;
  final Future<void> Function(FrameTickRequest request) onTick;
  int sensorOrientation;

  FrameSamplerPhase phase = FrameSamplerPhase.idle;
  HandState handState = HandState.none;

  Uint8List? _prevY;
  int _onsetStreak = 0;
  DateTime? _lastMotionAt;
  DateTime? _lastTickAt;
  HandState _pendingHand = HandState.none;
  int _pendingHandStreak = 0;
  bool _busy = false;

  Future<void> onCameraImage(CameraImage image) async {
    if (_busy) return;
    _busy = true;
    try {
      await _handle(image);
    } finally {
      _busy = false;
    }
  }

  Future<void> _handle(CameraImage image) async {
    final yPlane = image.planes.first;
    final metrics = measureYPlane(
      yBytes: yPlane.bytes,
      width: image.width,
      height: image.height,
      bytesPerRow: yPlane.bytesPerRow,
      previousY: _prevY,
    );
    _prevY = Uint8List.fromList(yPlane.bytes);

    final now = DateTime.now();
    final moving = metrics.motionEnergy >= thresholds.tOnset;
    if (moving) {
      _onsetStreak++;
      _lastMotionAt = now;
    } else {
      _onsetStreak = 0;
    }

    if (phase == FrameSamplerPhase.idle) {
      if (_onsetStreak >= 2) {
        phase = FrameSamplerPhase.active;
      }
    } else {
      final quiet = _lastMotionAt == null ||
          now.difference(_lastMotionAt!).inMilliseconds >= thresholds.tQuietMs;
      if (quiet && !moving) {
        phase = FrameSamplerPhase.idle;
      }
    }

    // Idle: low-rate presence probe (person → 识别中 / none → 就绪).
    // Active: full perception tick cadence.
    final presenceOnly = phase == FrameSamplerPhase.idle;
    final minInterval =
        presenceOnly ? thresholds.deltaIdleMs : thresholds.deltaActiveMs;
    if (_lastTickAt != null &&
        now.difference(_lastTickAt!).inMilliseconds < minInterval) {
      return;
    }

    _updateHandStateGuess(metrics.motionEnergy);
    final ts = now.millisecondsSinceEpoch;
    final vision = await cameraImageToVisionFrame(
      image,
      ts: ts,
      sensorOrientation: sensorOrientation,
    );
    if (vision == null) return;

    final omitHands =
        presenceOnly || metrics.sharpness < thresholds.sMin;
    _lastTickAt = now;
    await onTick(
      FrameTickRequest(
        ts: ts,
        frame: vision,
        handState: presenceOnly ? HandState.none : handState,
        omitHands: omitHands,
        forcePathGap: presenceOnly,
        sharpness: metrics.sharpness,
        motionEnergy: metrics.motionEnergy,
      ),
    );
  }

  void _updateHandStateGuess(double energy) {
    // MVP coarse prior: motion → both; otherwise keep previous until quiet.
    final guess = energy >= thresholds.tOnset ? HandState.both : handState;
    if (guess == _pendingHand) {
      _pendingHandStreak++;
    } else {
      _pendingHand = guess;
      _pendingHandStreak = 1;
    }
    if (_pendingHandStreak >= thresholds.nStableHand) {
      handState = _pendingHand;
    }
    if (phase == FrameSamplerPhase.idle) {
      handState = HandState.none;
    }
  }

  void reset() {
    phase = FrameSamplerPhase.idle;
    handState = HandState.none;
    _prevY = null;
    _onsetStreak = 0;
    _lastMotionAt = null;
    _lastTickAt = null;
    _pendingHand = HandState.none;
    _pendingHandStreak = 0;
  }
}
