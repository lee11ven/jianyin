import 'package:flutter/services.dart';

import '../envelope/landmark_point.dart';
import 'mediapipe_vision.dart';
import 'vision_frame.dart';

/// Shared MethodChannel contract for Android + iOS MediaPipe Tasks Vision.
///
/// Methods:
/// - `ensureReady` → copies `.task` assets and creates landmarkers
/// - `detectPose` / `detectHands` → IMAGE mode on RGBA frames
class MediaPipeVisionChannel implements MediaPipeVision {
  MediaPipeVisionChannel({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('jianyin/mediapipe_vision');

  final MethodChannel _channel;
  bool _ready = false;

  static const poseAsset = 'assets/ml/pose_landmarker_lite.task';
  static const handsAsset = 'assets/ml/hand_landmarker.task';

  @override
  Future<void> ensureReady() async {
    if (_ready) return;
    await _channel.invokeMethod<void>('ensureReady', {
      'poseAsset': poseAsset,
      'handsAsset': handsAsset,
    });
    _ready = true;
  }

  @override
  Future<PoseDetectionResult?> detectPose(VisionFrame frame) async {
    await ensureReady();
    final raw = await _channel.invokeMethod<dynamic>(
      'detectPose',
      frame.toChannelArgs(),
    );
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    final list = (map['landmarks'] as List?) ?? const [];
    if (list.isEmpty) return null;
    return PoseDetectionResult(
      landmarks: [
        for (final e in list)
          LandmarkPoint.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  @override
  Future<HandsDetectionResult?> detectHands(VisionFrame frame) async {
    await ensureReady();
    final raw = await _channel.invokeMethod<dynamic>(
      'detectHands',
      frame.toChannelArgs(),
    );
    if (raw == null) return null;
    final map = Map<String, dynamic>.from(raw as Map);
    final handsRaw = (map['hands'] as List?) ?? const [];
    if (handsRaw.isEmpty) return null;
    final hands = <DetectedHand>[];
    for (final h in handsRaw) {
      final hm = Map<String, dynamic>.from(h as Map);
      final lm = (hm['landmarks'] as List?) ?? const [];
      hands.add(
        DetectedHand(
          landmarks: [
            for (final e in lm)
              LandmarkPoint.fromJson(Map<String, dynamic>.from(e as Map)),
          ],
          handedness: hm['handedness'] as String? ?? 'Right',
          score: (hm['score'] as num?)?.toDouble() ?? 0,
        ),
      );
    }
    return HandsDetectionResult(hands: hands);
  }

  @override
  Future<void> dispose() async {
    if (!_ready) return;
    try {
      await _channel.invokeMethod<void>('dispose');
    } catch (_) {}
    _ready = false;
  }
}

/// In-memory fake for unit tests (no native SDK).
class FakeMediaPipeVision implements MediaPipeVision {
  FakeMediaPipeVision({
    this.pose,
    this.hands,
  });

  PoseDetectionResult? pose;
  HandsDetectionResult? hands;
  int poseCalls = 0;
  int handsCalls = 0;

  @override
  Future<void> ensureReady() async {}

  @override
  Future<PoseDetectionResult?> detectPose(VisionFrame frame) async {
    poseCalls++;
    return pose;
  }

  @override
  Future<HandsDetectionResult?> detectHands(VisionFrame frame) async {
    handsCalls++;
    return hands;
  }

  @override
  Future<void> dispose() async {}
}
