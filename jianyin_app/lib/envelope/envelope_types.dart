import '../skeleton/hand_types.dart';
import 'catalog.dart';
import 'csl_channels.dart';
import 'landmark_point.dart';

/// Root kind of [gesture_skeleton_envelope_v1].
enum EnvelopeKind { catalog, frame, segment }

/// One joint identity + optional frame coordinates.
class EnvelopeJoint {
  const EnvelopeJoint({
    required this.id,
    required this.role,
    required this.digit,
    required this.local,
    required this.slot,
    this.x,
    this.y,
    this.z,
    this.v,
  });

  final String id;
  final String role;
  final String digit;
  final int local;
  final int slot;
  final double? x;
  final double? y;
  final double? z;
  final double? v;

  LandmarkPoint get point =>
      LandmarkPoint(x: x ?? 0, y: y ?? 0, z: z ?? 0, v: v ?? 0);

  Map<String, dynamic> toJson({required bool withCoords}) {
    final json = <String, dynamic>{
      'id': id,
      'role': role,
      'digit': digit,
      'local': local,
      'slot': slot,
    };
    if (withCoords) {
      json['x'] = x ?? 0;
      json['y'] = y ?? 0;
      json['z'] = z ?? 0;
      json['v'] = v ?? 0;
    }
    return json;
  }
}

/// One bone identity + optional frame [valid].
class EnvelopeBone {
  const EnvelopeBone({
    required this.id,
    required this.boneClass,
    required this.digit,
    required this.from,
    required this.to,
    required this.fromSlot,
    required this.toSlot,
    required this.mediapipeEdge,
    this.segment,
    this.valid,
  });

  final String id;
  final BoneClass boneClass;
  final String digit;
  final String? segment;
  final String from;
  final String to;
  final int fromSlot;
  final int toSlot;
  final bool mediapipeEdge;
  final bool? valid;

  Map<String, dynamic> toJson({required bool withValid}) {
    final json = <String, dynamic>{
      'id': id,
      'boneClass': boneClass.name,
      'segment': segment,
      'digit': digit,
      'from': from,
      'to': to,
      'fromSlot': fromSlot,
      'toSlot': toSlot,
      'mediapipeEdge': mediapipeEdge,
    };
    if (withValid) json['valid'] = valid ?? false;
    return json;
  }
}

/// One hand slot in catalog / frame.
class EnvelopeHand {
  const EnvelopeHand({
    required this.slotBase,
    required this.joints,
    required this.bones,
    this.present,
  });

  final int slotBase;
  final bool? present;
  final List<EnvelopeJoint> joints;
  final List<EnvelopeBone> bones;

  Map<String, dynamic> toJson({required bool frame}) {
    final json = <String, dynamic>{
      'slotBase': slotBase,
      if (frame && present != null) 'present': present,
      'joints': [
        for (final j in joints) j.toJson(withCoords: frame),
      ],
      'bones': [
        for (final b in bones) b.toJson(withValid: frame),
      ],
    };
    return json;
  }
}

/// Cross / stack relation; only appears on [kind] frame.
class HandRelation {
  const HandRelation({
    required this.handState,
    required this.layout,
    required this.foreground,
    required this.occluder,
    required this.occluded,
    required this.labelFrozen,
  });

  final HandState handState;

  /// `left` / `right` / `apart` / `crossed` / `stacked` / `crossed_stacked`.
  final String layout;

  /// `left` / `right` / `unknown`.
  final String foreground;

  /// `left` / `right` / `none`.
  final String occluder;

  /// `left` / `right` / `none`.
  final String occluded;
  final bool labelFrozen;

  /// Default relation from handState alone (no cross/stack inference).
  factory HandRelation.fromHandState(HandState handState) {
    switch (handState) {
      case HandState.left:
        return const HandRelation(
          handState: HandState.left,
          layout: 'left',
          foreground: 'unknown',
          occluder: 'none',
          occluded: 'none',
          labelFrozen: false,
        );
      case HandState.right:
        return const HandRelation(
          handState: HandState.right,
          layout: 'right',
          foreground: 'unknown',
          occluder: 'none',
          occluded: 'none',
          labelFrozen: false,
        );
      case HandState.both:
        return const HandRelation(
          handState: HandState.both,
          layout: 'apart',
          foreground: 'unknown',
          occluder: 'none',
          occluded: 'none',
          labelFrozen: false,
        );
      case HandState.none:
        return const HandRelation(
          handState: HandState.none,
          layout: 'apart',
          foreground: 'unknown',
          occluder: 'none',
          occluded: 'none',
          labelFrozen: false,
        );
    }
  }

  Map<String, dynamic> toJson() => {
        'handState': handState.name,
        'layout': layout,
        'foreground': foreground,
        'occluder': occluder,
        'occluded': occluded,
        'labelFrozen': labelFrozen,
      };
}

/// Local `kind: frame` envelope (identity + one-tick observation).
class GestureSkeletonFrame {
  const GestureSkeletonFrame({
    required this.ts,
    required this.left,
    required this.right,
    required this.relation,
    this.path,
    this.body,
    this.nonmanual,
  });

  final int ts;
  final EnvelopeHand left;
  final EnvelopeHand right;
  final HandRelation relation;
  final PathChannel? path;
  final BodyChannel? body;
  final NonmanualChannel? nonmanual;

  static const kind = EnvelopeKind.frame;

  /// Rebuild fixed-length 42 packing from frame joints.
  HandsChannel toHandsChannel() {
    final points = List<LandmarkPoint>.generate(
      EnvelopeCatalog.packingLength,
      (_) => LandmarkPoint.zero,
    );
    for (final j in left.joints) {
      points[j.slot] = j.point;
    }
    for (final j in right.joints) {
      points[j.slot] = j.point;
    }
    return HandsChannel(points: points);
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'envelope': EnvelopeCatalog.envelope,
      'kind': kind.name,
      'ts': ts,
      'coord': Map<String, String>.from(EnvelopeCatalog.coord),
      'hands': {
        'left': left.toJson(frame: true),
        'right': right.toJson(frame: true),
      },
      'relation': relation.toJson(),
    };
    if (path != null) json['path'] = path!.toJson();
    if (body != null) json['body'] = body!.toJson();
    if (nonmanual != null) json['nonmanual'] = nonmanual!.toJson();
    return json;
  }
}

/// Local `kind: segment` envelope (window-level; not uplinked).
class GestureSkeletonSegment {
  const GestureSkeletonSegment({
    required this.t0,
    required this.t1,
    this.hand,
    this.trace,
    this.space,
    this.movement,
    this.places,
    this.head,
    this.mouth,
    this.alternating = false,
    this.hands,
  });

  final int t0;
  final int t1;
  final String? hand;
  final String? trace;
  final String? space;
  final Map<String, dynamic>? movement;
  final List<String>? places;
  final String? head;
  final Map<String, double>? mouth;
  final bool alternating;
  final List<String>? hands;

  static const kind = EnvelopeKind.segment;

  Map<String, dynamic> toJson() {
    if (alternating) {
      return {
        'envelope': EnvelopeCatalog.envelope,
        'kind': kind.name,
        'alternating': true,
        'hands': hands ?? const ['left', 'right'],
        't0': t0,
        't1': t1,
      };
    }
    return {
      'envelope': EnvelopeCatalog.envelope,
      'kind': kind.name,
      't0': t0,
      't1': t1,
      'hand': hand,
      'trace': trace,
      'space': space,
      if (movement != null) 'movement': movement,
      if (places != null) 'places': places,
      if (head != null) 'head': head,
      if (mouth != null) 'mouth': mouth,
    };
  }
}

/// Local `kind: catalog` document wrapper.
class GestureSkeletonCatalog {
  const GestureSkeletonCatalog(this.document);

  final Map<String, dynamic> document;

  static const kind = EnvelopeKind.catalog;

  factory GestureSkeletonCatalog.fromLocked() =>
      GestureSkeletonCatalog(EnvelopeCatalog.buildCatalogJson());

  Map<String, dynamic> toJson() => document;
}
