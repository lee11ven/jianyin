import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/body/body_extractor.dart';
import 'package:jianyin_app/body/body_frame_builder.dart';
import 'package:jianyin_app/envelope/landmark_point.dart';
import 'package:jianyin_app/native/mediapipe_vision.dart';
import 'package:jianyin_app/native/mediapipe_vision_channel.dart';
import 'package:jianyin_app/native/vision_frame.dart';
import 'package:jianyin_app/perception/perception_pipeline.dart';
import 'package:jianyin_app/skeleton/hand_skeleton_extractor.dart';
import 'package:jianyin_app/skeleton/hand_track_state.dart';
import 'package:jianyin_app/skeleton/hand_types.dart';
import 'package:jianyin_app/trajectory/trajectory_tracker.dart';

LandmarkPoint p(double x, double y, double z, double v) =>
    LandmarkPoint(x: x, y: y, z: z, v: v);

VisionFrame _tinyFrame() => VisionFrame(
      rgba: Uint8List(4 * 4 * 4),
      width: 4,
      height: 4,
      ts: 1,
    );

List<LandmarkPoint> _poseWithAnchors() {
  final pts = List<LandmarkPoint>.generate(33, (_) => LandmarkPoint.zero);
  pts[0] = p(0.5, 0.2, -0.1, 0.99); // nose
  pts[11] = p(0.35, 0.45, 0.0, 0.98); // shoulderL
  pts[12] = p(0.65, 0.45, 0.0, 0.98); // shoulderR
  pts[15] = p(0.30, 0.70, -0.02, 0.95); // wristL
  pts[16] = p(0.70, 0.70, -0.02, 0.95); // wristR
  return pts;
}

void main() {
  test('BodyFrameBuilder writes frame when nose+shoulders visible', () {
    final built = const BodyFrameBuilder().build(_poseWithAnchors());
    expect(built.body, isNotNull);
    expect(built.axes, isNotNull);
    expect(built.body!.frame.shoulderWidth, closeTo(0.30, 1e-6));
    expect(built.wristL, isNotNull);
    expect(built.wristR, isNotNull);
  });

  test('BodyFrameBuilder is conservative when shoulder missing', () {
    final pts = _poseWithAnchors();
    pts[11] = p(0.35, 0.45, 0.0, 0.1);
    final built = const BodyFrameBuilder().build(pts);
    expect(built.body, isNull);
    expect(built.axes, isNull);
  });

  test('DefaultTrajectoryTracker body space and explicit gap', () async {
    final tracker = DefaultTrajectoryTracker();
    final axes = const BodyFrameBuilder().build(_poseWithAnchors()).axes!;
    final gap = await tracker.sample(
      ts: 1,
      axes: axes,
      forceGap: true,
      wristLeft: p(0.3, 0.7, 0, 1),
    );
    expect(gap.path.gap, isTrue);
    expect(gap.path.space, 'body');

    final ok = await tracker.sample(
      ts: 2,
      axes: axes,
      forceGap: false,
      wristLeft: p(0.3, 0.7, 0, 1),
      wristRight: p(0.7, 0.7, 0, 1),
    );
    expect(ok.path.gap, isFalse);
    expect(ok.path.anchor, isTrue);
    expect(ok.path.left!.wrist.v, greaterThan(0));
  });

  test('omit hands does not force path gap', () async {
    final vision = FakeMediaPipeVision(
      pose: PoseDetectionResult(landmarks: _poseWithAnchors()),
      hands: HandsDetectionResult(
        hands: [
          DetectedHand(
            landmarks: List.generate(21, (i) => p(0.2, 0.2 + i * 0.01, 0, 0.9)),
            handedness: 'Left',
            score: 0.9,
          ),
        ],
      ),
    );
    final pipeline = PerceptionPipeline(
      body: MediaPipeBodyExtractor(vision: vision),
      trajectory: DefaultTrajectoryTracker(),
      skeleton: MediaPipeHandSkeletonExtractor(vision: vision),
    );

    final withHands = await pipeline.tick(
      ts: 1,
      sessionId: 's',
      frame: _tinyFrame(),
      handStatePrior: HandState.left,
      omitHands: false,
    );
    expect(withHands, isNotNull);
    expect(withHands!.hands, isNotNull);
    expect(withHands.path?.gap, isFalse);

    final omitted = await pipeline.tick(
      ts: 2,
      sessionId: 's',
      frame: _tinyFrame(),
      handStatePrior: HandState.left,
      omitHands: true,
    );
    expect(omitted, isNotNull);
    expect(omitted!.hands, isNull);
    expect(omitted.path?.gap, isFalse);

    await pipeline.dispose();
  });

  test('HandSlotFuser keeps single-hand slot without mirroring', () {
    final fuser = HandSlotFuser();
    final left = DetectedHand(
      landmarks: List.generate(21, (i) => p(0.2, 0.2, 0, 0.9)),
      handedness: 'Left',
      score: 0.95,
    );
    final fused = fuser.fuse(
      detections: [left],
      handStatePrior: HandState.left,
    );
    expect(fused.left, isNotNull);
    expect(fused.right, isNull);
    expect(fused.state, HandState.left);
  });

  test('MediaPipeBodyExtractor streaks hint.show_upper_body', () async {
    final vision = FakeMediaPipeVision();
    final body = MediaPipeBodyExtractor(vision: vision);
    for (var i = 0; i < 10; i++) {
      await body.extract(ts: i, frame: _tinyFrame());
    }
    expect(body.lastResult.hintShowUpperBody, isTrue);
  });

  test('Y-plane sharpness responds to edges', () {
    final flat = Uint8List(64 * 64);
    final sharp = Uint8List(64 * 64);
    for (var y = 0; y < 64; y++) {
      for (var x = 0; x < 64; x++) {
        sharp[y * 64 + x] = (x % 8 < 4) ? 0 : 255;
      }
    }
    final mFlat = measureYPlane(
      yBytes: flat,
      width: 64,
      height: 64,
      bytesPerRow: 64,
    );
    final mSharp = measureYPlane(
      yBytes: sharp,
      width: 64,
      height: 64,
      bytesPerRow: 64,
    );
    expect(mSharp.sharpness, greaterThan(mFlat.sharpness));
  });
}
