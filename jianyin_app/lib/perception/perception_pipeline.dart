import '../body/body_extractor.dart';
import '../body/body_types.dart';
import '../envelope/csl_channels.dart';
import '../envelope/envelope_assembler.dart';
import '../envelope/envelope_packer.dart';
import '../envelope/landmark_point.dart';
import '../skeleton/hand_skeleton_extractor.dart';
import '../skeleton/hand_types.dart';
import '../trajectory/trajectory_tracker.dart';

/// Same-tick perception scheduler: body -> trajectory -> skeleton -> envelope.
///
/// MediaPipe SDKs plug into the three extractors; this class only orders calls,
/// assembles the local frame, and packs csl_channels_v1.
class PerceptionPipeline {
  PerceptionPipeline({
    BodyExtractor? body,
    TrajectoryTracker? trajectory,
    HandSkeletonExtractor? skeleton,
    EnvelopeAssembler? assembler,
    EnvelopePacker? packer,
  })  : _body = body ?? StubBodyExtractor(),
        _trajectory = trajectory ?? StubTrajectoryTracker(),
        _skeleton = skeleton ?? StubHandSkeletonExtractor(),
        _assembler = assembler ?? DefaultEnvelopeAssembler(),
        _packer = packer ?? DefaultEnvelopePacker();

  final BodyExtractor _body;
  final TrajectoryTracker _trajectory;
  final HandSkeletonExtractor _skeleton;
  final EnvelopeAssembler _assembler;
  final EnvelopePacker _packer;

  /// Access the assembler for catalog queries.
  EnvelopeAssembler get assembler => _assembler;

  /// Prefer Hands wrists from the previous tick when present.
  LandmarkPoint? _prevHandsWristL;
  LandmarkPoint? _prevHandsWristR;

  /// Run one activity-segment tick. [frame] is a VisionFrame once camera lands.
  Future<CslChannelsLandmarks?> tick({
    required int ts,
    required String sessionId,
    required Object frame,
    HandState handStatePrior = HandState.none,
    String viewpointClass = 'N0',
    bool forcePathGap = false,
    bool omitHands = false,
  }) async {
    final bodyResult = await _body.extract(ts: ts, frame: frame);
    final axes = _axesFrom(bodyResult);

    final wristL = _prevHandsWristL ?? bodyResult.wristL;
    final wristR = _prevHandsWristR ?? bodyResult.wristR;

    final pathResult = await _trajectory.sample(
      ts: ts,
      axes: axes,
      forceGap: forcePathGap,
      wristLeft: wristL,
      wristRight: wristR,
    );
    final handsResult = await _skeleton.extract(
      ts: ts,
      frame: frame,
      handStatePrior: handStatePrior,
      viewpointClass: viewpointClass,
      omitHands: omitHands,
    );

    _prevHandsWristL = _skeleton.lastWristLeft;
    _prevHandsWristR = _skeleton.lastWristRight;

    final handState = handsResult.handState;
    final assembled = _assembler.assembleFrame(
      ts: ts,
      handState: handState,
      hands: handsResult.hands,
      path: pathResult.path,
      body: bodyResult.body,
      nonmanual: bodyResult.nonmanual,
    );

    if (assembled != null) {
      return _assembler.projectUplink(
        frame: assembled,
        sessionId: sessionId,
        packer: _packer,
      );
    }

    // handState == none: no local frame; still pack path/body for stub ticks.
    return _packer.pack(
      ts: ts,
      sessionId: sessionId,
      hands: handsResult.hands,
      path: pathResult.path,
      body: bodyResult.body,
      nonmanual: bodyResult.nonmanual,
    );
  }

  BodyAxes? _axesFrom(BodyTickResult result) {
    final body = result.body;
    if (body == null) return null;
    final f = body.frame;
    return BodyAxes(
      origin: f.origin,
      shoulderWidth: f.shoulderWidth,
      right: f.right,
      up: f.up,
      zSign: f.zSign,
    );
  }

  Future<void> dispose() async {
    await _body.dispose();
    await _trajectory.dispose();
    await _skeleton.dispose();
  }
}
