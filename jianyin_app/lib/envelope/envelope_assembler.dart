import '../skeleton/hand_types.dart';
import 'catalog.dart';
import 'csl_channels.dart';
import 'envelope_packer.dart';
import 'envelope_types.dart';
import 'landmark_point.dart';

/// Builds local gesture_skeleton_envelope_v1 frames and projects uplink.
///
/// Same-tick order (locked): body -> trajectory -> skeleton -> assemble -> pack.
/// Bones / relation / present / valid / segment are never uplinked.
abstract class EnvelopeAssembler {
  GestureSkeletonCatalog catalog();

  /// Whether catalog has been emitted at least once.
  bool get catalogSent;

  /// Reset catalog sent state (called on reconnect).
  void resetCatalogSent();

  /// handState == none -> null (no frame).
  GestureSkeletonFrame? assembleFrame({
    required int ts,
    required HandState handState,
    HandsChannel? hands,
    PathChannel? path,
    BodyChannel? body,
    NonmanualChannel? nonmanual,
    HandRelation? relation,
    double vMin = 0.5,
  });

  /// Project frame channels that may uplink; omits bones / relation / present.
  CslChannelsLandmarks projectUplink({
    required GestureSkeletonFrame frame,
    required String sessionId,
    EnvelopePacker packer = const DefaultEnvelopePacker(),
  });
}

/// Expands Hands42 into full joint/bone frame identity, then packs uplink.
class DefaultEnvelopeAssembler implements EnvelopeAssembler {
  DefaultEnvelopeAssembler();

  bool _catalogSent = false;
  @override
  bool get catalogSent => _catalogSent;
  @override
  void resetCatalogSent() => _catalogSent = false;

  late final GestureSkeletonCatalog _catalog =
      GestureSkeletonCatalog.fromLocked();

  @override
  GestureSkeletonCatalog catalog() {
    _catalogSent = true;
    return _catalog;
  }

  @override
  GestureSkeletonFrame? assembleFrame({
    required int ts,
    required HandState handState,
    HandsChannel? hands,
    PathChannel? path,
    BodyChannel? body,
    NonmanualChannel? nonmanual,
    HandRelation? relation,
    double vMin = 0.5,
  }) {
    if (handState == HandState.none) return null;

    final points = hands?.points;
    final left = _buildHand(
      left: true,
      points: points,
      vMin: vMin,
    );
    final right = _buildHand(
      left: false,
      points: points,
      vMin: vMin,
    );

    return GestureSkeletonFrame(
      ts: ts,
      left: left,
      right: right,
      relation: relation ?? HandRelation.fromHandState(handState),
      path: path,
      body: body,
      nonmanual: nonmanual,
    );
  }

  @override
  CslChannelsLandmarks projectUplink({
    required GestureSkeletonFrame frame,
    required String sessionId,
    EnvelopePacker packer = const DefaultEnvelopePacker(),
  }) {
    final packedHands = frame.toHandsChannel();
    final hasAnyVisible = packedHands.points.any((p) => p.v > 0);
    return packer.pack(
      ts: frame.ts,
      sessionId: sessionId,
      hands: hasAnyVisible ? packedHands : null,
      path: frame.path,
      body: frame.body,
      nonmanual: frame.nonmanual,
    );
  }

  EnvelopeHand _buildHand({
    required bool left,
    required List<LandmarkPoint>? points,
    required double vMin,
  }) {
    final slotBase =
        left ? EnvelopeCatalog.leftSlotBase : EnvelopeCatalog.rightSlotBase;
    final joints = <EnvelopeJoint>[
      for (var local = 0; local < EnvelopeCatalog.jointsPerHand; local++)
        _jointFromPoints(
          left: left,
          local: local,
          points: points,
        ),
    ];
    final present = joints.any((j) => (j.v ?? 0) >= vMin);
    final bones = <EnvelopeBone>[
      for (final spec in EnvelopeCatalog.boneLocals)
        _boneFromJoints(
          left: left,
          spec: spec,
          joints: joints,
          vMin: vMin,
        ),
    ];
    return EnvelopeHand(
      slotBase: slotBase,
      present: present,
      joints: joints,
      bones: bones,
    );
  }

  EnvelopeJoint _jointFromPoints({
    required bool left,
    required int local,
    required List<LandmarkPoint>? points,
  }) {
    final s = EnvelopeCatalog.slot(left: left, local: local);
    final p = (points != null && s < points.length)
        ? points[s]
        : LandmarkPoint.zero;
    return EnvelopeJoint(
      id: EnvelopeCatalog.jointId(left: left, local: local),
      role: EnvelopeCatalog.jointRoles[local]!,
      digit: EnvelopeCatalog.jointDigits[local]!,
      local: local,
      slot: s,
      x: p.x,
      y: p.y,
      z: p.z,
      v: p.v,
    );
  }

  EnvelopeBone _boneFromJoints({
    required bool left,
    required BoneSpec spec,
    required List<EnvelopeJoint> joints,
    required double vMin,
  }) {
    final fromV = joints[spec.fromLocal].v ?? 0;
    final toV = joints[spec.toLocal].v ?? 0;
    return EnvelopeBone(
      id: EnvelopeCatalog.boneId(left: left, spec: spec),
      boneClass: spec.boneClass,
      digit: spec.digit,
      segment: spec.segment,
      from: EnvelopeCatalog.jointId(left: left, local: spec.fromLocal),
      to: EnvelopeCatalog.jointId(left: left, local: spec.toLocal),
      fromSlot: EnvelopeCatalog.slot(left: left, local: spec.fromLocal),
      toSlot: EnvelopeCatalog.slot(left: left, local: spec.toLocal),
      mediapipeEdge: spec.mediapipeEdge,
      valid: fromV >= vMin && toV >= vMin,
    );
  }
}
