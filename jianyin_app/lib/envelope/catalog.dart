/// Identity catalog for [gesture_skeleton_envelope_v1].
///
/// Joint / bone / path / body / site ids are locked here. Packing layout matches
/// `mediapipe_hands_v1` (42 points: left [0:21), right [21:42)).
/// Algorithm source: docs/design/算法/客户端/手势骨架信封.md
abstract final class EnvelopeCatalog {
  static const envelope = 'gesture_skeleton_envelope_v1';
  static const packingSchema = 'mediapipe_hands_v1';
  static const packingLength = 42;
  static const leftSlotBase = 0;
  static const rightSlotBase = 21;
  static const jointsPerHand = 21;
  static const bonesPerHand = 23;

  /// Image-plane coord descriptors for handshape joints.
  static const coord = <String, String>{
    'space': 'image_normalized',
    'x': 'right_positive',
    'y': 'down_positive',
    'z': 'relative_depth',
    'v': 'visibility',
  };

  /// MediaPipe Hands local index → role (same for both hands).
  static const jointRoles = <int, String>{
    0: 'wrist',
    1: 'cmc',
    2: 'mcp',
    3: 'ip',
    4: 'tip',
    5: 'mcp',
    6: 'pip',
    7: 'dip',
    8: 'tip',
    9: 'mcp',
    10: 'pip',
    11: 'dip',
    12: 'tip',
    13: 'mcp',
    14: 'pip',
    15: 'dip',
    16: 'tip',
    17: 'mcp',
    18: 'pip',
    19: 'dip',
    20: 'tip',
  };

  static const jointDigits = <int, String>{
    0: 'wrist',
    1: 'thumb',
    2: 'thumb',
    3: 'thumb',
    4: 'thumb',
    5: 'index',
    6: 'index',
    7: 'index',
    8: 'index',
    9: 'middle',
    10: 'middle',
    11: 'middle',
    12: 'middle',
    13: 'ring',
    14: 'ring',
    15: 'ring',
    16: 'ring',
    17: 'pinky',
    18: 'pinky',
    19: 'pinky',
    20: 'pinky',
  };

  /// Tip local indices used by path channel.
  static const tipLocals = <String, int>{
    'thumb': 4,
    'index': 8,
    'middle': 12,
    'ring': 16,
    'pinky': 20,
  };

  /// Palm estimate uses MCP locals 5 / 9 / 17.
  static const palmMcpLocals = <int>[5, 9, 17];

  static const bodyPoseIndex = <String, int>{
    'nose': 0,
    'eyeL': 2,
    'eyeR': 5,
    'earL': 7,
    'earR': 8,
    'mouthL': 9,
    'mouthR': 10,
    'shoulderL': 11,
    'shoulderR': 12,
    'elbowL': 13,
    'elbowR': 14,
    'wristL': 15,
    'wristR': 16,
    'hipL': 23,
    'hipR': 24,
  };

  static const sites = <String>[
    'forehead',
    'eye',
    'nose',
    'mouth',
    'chin',
    'ear',
    'cheek',
    'neck',
    'shoulder',
    'chest',
    'abdomen',
    'waist',
    'neutral',
    'none',
  ];

  /// Palm-only path identities (wrist / tips reuse joint ids).
  static const pathPoints = <Map<String, Object>>[
    {
      'id': 'L.palm',
      'hand': 'left',
      'derivedFrom': ['L.index.mcp', 'L.middle.mcp', 'L.pinky.mcp'],
    },
    {
      'id': 'R.palm',
      'hand': 'right',
      'derivedFrom': ['R.index.mcp', 'R.middle.mcp', 'R.pinky.mcp'],
    },
  ];

  static const nonmanualQuantities = <String>[
    'head.pitch',
    'head.yaw',
    'head.roll',
    'mouth.open',
    'mouth.round',
    'mouth.spread',
    'brow.raise',
    'brow.furrow',
    'eye.openL',
    'eye.openR',
  ];

  /// Locked bone topology (local indices). Order: phalanx → metacarpal →
  /// wristBridge → palmArch. Same for both hands; ids / slots get a prefix.
  static const boneLocals = <BoneSpec>[
    // Phalanx (14)
    BoneSpec(
      idSuffix: 'thumb.phalanx.proximal',
      boneClass: BoneClass.phalanx,
      digit: 'thumb',
      segment: 'proximal',
      fromLocal: 2,
      toLocal: 3,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'thumb.phalanx.distal',
      boneClass: BoneClass.phalanx,
      digit: 'thumb',
      segment: 'distal',
      fromLocal: 3,
      toLocal: 4,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'index.phalanx.proximal',
      boneClass: BoneClass.phalanx,
      digit: 'index',
      segment: 'proximal',
      fromLocal: 5,
      toLocal: 6,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'index.phalanx.middle',
      boneClass: BoneClass.phalanx,
      digit: 'index',
      segment: 'middle',
      fromLocal: 6,
      toLocal: 7,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'index.phalanx.distal',
      boneClass: BoneClass.phalanx,
      digit: 'index',
      segment: 'distal',
      fromLocal: 7,
      toLocal: 8,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'middle.phalanx.proximal',
      boneClass: BoneClass.phalanx,
      digit: 'middle',
      segment: 'proximal',
      fromLocal: 9,
      toLocal: 10,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'middle.phalanx.middle',
      boneClass: BoneClass.phalanx,
      digit: 'middle',
      segment: 'middle',
      fromLocal: 10,
      toLocal: 11,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'middle.phalanx.distal',
      boneClass: BoneClass.phalanx,
      digit: 'middle',
      segment: 'distal',
      fromLocal: 11,
      toLocal: 12,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'ring.phalanx.proximal',
      boneClass: BoneClass.phalanx,
      digit: 'ring',
      segment: 'proximal',
      fromLocal: 13,
      toLocal: 14,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'ring.phalanx.middle',
      boneClass: BoneClass.phalanx,
      digit: 'ring',
      segment: 'middle',
      fromLocal: 14,
      toLocal: 15,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'ring.phalanx.distal',
      boneClass: BoneClass.phalanx,
      digit: 'ring',
      segment: 'distal',
      fromLocal: 15,
      toLocal: 16,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'pinky.phalanx.proximal',
      boneClass: BoneClass.phalanx,
      digit: 'pinky',
      segment: 'proximal',
      fromLocal: 17,
      toLocal: 18,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'pinky.phalanx.middle',
      boneClass: BoneClass.phalanx,
      digit: 'pinky',
      segment: 'middle',
      fromLocal: 18,
      toLocal: 19,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'pinky.phalanx.distal',
      boneClass: BoneClass.phalanx,
      digit: 'pinky',
      segment: 'distal',
      fromLocal: 19,
      toLocal: 20,
      mediapipeEdge: true,
    ),
    // Metacarpal (5)
    BoneSpec(
      idSuffix: 'thumb.metacarpal',
      boneClass: BoneClass.metacarpal,
      digit: 'thumb',
      fromLocal: 1,
      toLocal: 2,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'index.metacarpal',
      boneClass: BoneClass.metacarpal,
      digit: 'index',
      fromLocal: 0,
      toLocal: 5,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'middle.metacarpal',
      boneClass: BoneClass.metacarpal,
      digit: 'middle',
      fromLocal: 0,
      toLocal: 9,
      mediapipeEdge: false,
    ),
    BoneSpec(
      idSuffix: 'ring.metacarpal',
      boneClass: BoneClass.metacarpal,
      digit: 'ring',
      fromLocal: 0,
      toLocal: 13,
      mediapipeEdge: false,
    ),
    BoneSpec(
      idSuffix: 'pinky.metacarpal',
      boneClass: BoneClass.metacarpal,
      digit: 'pinky',
      fromLocal: 0,
      toLocal: 17,
      mediapipeEdge: true,
    ),
    // Wrist bridge (1)
    BoneSpec(
      idSuffix: 'thumb.wristBridge',
      boneClass: BoneClass.wristBridge,
      digit: 'thumb',
      fromLocal: 0,
      toLocal: 1,
      mediapipeEdge: true,
    ),
    // Palm arch (3)
    BoneSpec(
      idSuffix: 'palm.arch.index_middle',
      boneClass: BoneClass.palmArch,
      digit: 'palm',
      fromLocal: 5,
      toLocal: 9,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'palm.arch.middle_ring',
      boneClass: BoneClass.palmArch,
      digit: 'palm',
      fromLocal: 9,
      toLocal: 13,
      mediapipeEdge: true,
    ),
    BoneSpec(
      idSuffix: 'palm.arch.ring_pinky',
      boneClass: BoneClass.palmArch,
      digit: 'palm',
      fromLocal: 13,
      toLocal: 17,
      mediapipeEdge: true,
    ),
  ];

  static String jointId({required bool left, required int local}) {
    final prefix = left ? 'L' : 'R';
    final digit = jointDigits[local]!;
    final role = jointRoles[local]!;
    if (local == 0) return '$prefix.wrist';
    return '$prefix.$digit.$role';
  }

  static int slot({required bool left, required int local}) {
    return (left ? leftSlotBase : rightSlotBase) + local;
  }

  static String boneId({required bool left, required BoneSpec spec}) {
    final prefix = left ? 'L' : 'R';
    return '$prefix.${spec.idSuffix}';
  }

  /// Bones for one hand in locked catalog order (23). Topology is isomorphic
  /// across hands; use [boneId] / [slot] for the side-specific identity.
  static List<BoneSpec> get bonesLeft => boneLocals;
  static List<BoneSpec> get bonesRight => boneLocals;

  static List<Map<String, Object>> bodyPoints() {
    return [
      for (final e in bodyPoseIndex.entries)
        {'id': 'B.${e.key}', 'poseIndex': e.value},
    ];
  }

  static Map<String, dynamic> _jointCatalogJson({
    required bool left,
    required int local,
  }) {
    return {
      'id': jointId(left: left, local: local),
      'role': jointRoles[local]!,
      'digit': jointDigits[local]!,
      'local': local,
      'slot': slot(left: left, local: local),
    };
  }

  static Map<String, dynamic> _boneCatalogJson({
    required bool left,
    required BoneSpec spec,
  }) {
    return {
      'id': boneId(left: left, spec: spec),
      'boneClass': spec.boneClass.name,
      'segment': spec.segment,
      'digit': spec.digit,
      'from': jointId(left: left, local: spec.fromLocal),
      'to': jointId(left: left, local: spec.toLocal),
      'fromSlot': slot(left: left, local: spec.fromLocal),
      'toSlot': slot(left: left, local: spec.toLocal),
      'mediapipeEdge': spec.mediapipeEdge,
    };
  }

  static Map<String, dynamic> _handCatalogJson({required bool left}) {
    return {
      'slotBase': left ? leftSlotBase : rightSlotBase,
      'joints': [
        for (var local = 0; local < jointsPerHand; local++)
          _jointCatalogJson(left: left, local: local),
      ],
      'bones': [
        for (final spec in boneLocals)
          _boneCatalogJson(left: left, spec: spec),
      ],
    };
  }

  /// Full `kind: catalog` document for debug / validation.
  static Map<String, dynamic> buildCatalogJson() {
    return {
      'envelope': envelope,
      'kind': 'catalog',
      'coord': Map<String, String>.from(coord),
      'packing': {
        'schema': packingSchema,
        'length': packingLength,
        'left': [leftSlotBase, rightSlotBase],
        'right': [rightSlotBase, packingLength],
      },
      'hands': {
        'left': _handCatalogJson(left: true),
        'right': _handCatalogJson(left: false),
      },
      'pathPoints': pathPoints,
      'bodyPoints': bodyPoints(),
      'sites': List<String>.from(sites),
      'nonmanualQuantities': List<String>.from(nonmanualQuantities),
    };
  }
}

/// Bone class locked by the envelope catalog.
enum BoneClass { phalanx, metacarpal, wristBridge, palmArch }

/// One bone identity in catalog topology (hand-agnostic local indices).
class BoneSpec {
  const BoneSpec({
    required this.idSuffix,
    required this.boneClass,
    required this.digit,
    required this.fromLocal,
    required this.toLocal,
    required this.mediapipeEdge,
    this.segment,
  });

  /// Id without `L.` / `R.` prefix, e.g. `thumb.phalanx.proximal`.
  final String idSuffix;
  final BoneClass boneClass;
  final String digit;

  /// Phalanx segment only; otherwise null.
  final String? segment;
  final int fromLocal;
  final int toLocal;
  final bool mediapipeEdge;
}
