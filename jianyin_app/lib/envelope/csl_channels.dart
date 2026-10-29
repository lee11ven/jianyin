import 'landmark_point.dart';

/// One hand's path sample (wrist / palm / five tips).
class HandPathSample {
  const HandPathSample({
    required this.wrist,
    required this.palm,
    required this.tips,
  });

  final LandmarkPoint wrist;
  final LandmarkPoint palm;
  final Map<String, LandmarkPoint> tips;

  static HandPathSample absent() => HandPathSample(
        wrist: LandmarkPoint.zero,
        palm: LandmarkPoint.zero,
        tips: {
          for (final name in const [
            'thumb',
            'index',
            'middle',
            'ring',
            'pinky',
          ])
            name: LandmarkPoint.zero,
        },
      );

  Map<String, dynamic> toJson() => {
        'wrist': wrist.toJson(),
        'palm': palm.toJson(),
        'tips': {
          for (final e in tips.entries) e.key: e.value.toJson(),
        },
      };
}

/// Activity-segment trajectory channel (`path`).
class PathChannel {
  const PathChannel({
    required this.space,
    required this.anchor,
    required this.gap,
    this.left,
    this.right,
  });

  /// `body` or `image`.
  final String space;
  final bool anchor;
  final bool gap;
  final HandPathSample? left;
  final HandPathSample? right;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'space': space,
      'anchor': anchor,
      'gap': gap,
    };
    if (!gap) {
      json['left'] = (left ?? HandPathSample.absent()).toJson();
      json['right'] = (right ?? HandPathSample.absent()).toJson();
    }
    return json;
  }
}

/// Body-frame metadata for shoulder-normalized coordinates.
class BodyFrame {
  const BodyFrame({
    required this.origin,
    required this.shoulderWidth,
    required this.right,
    required this.up,
    required this.zSign,
  });

  final LandmarkPoint origin;
  final double shoulderWidth;
  final LandmarkPoint right;
  final LandmarkPoint up;
  final int zSign;

  Map<String, dynamic> toJson() => {
        'origin': {'x': origin.x, 'y': origin.y, 'z': origin.z},
        'shoulderWidth': shoulderWidth,
        'right': {'x': right.x, 'y': right.y, 'z': right.z},
        'up': {'x': up.x, 'y': up.y, 'z': up.z},
        'zSign': zSign,
      };
}

/// Pose subset + frame (`body` channel).
class BodyChannel {
  const BodyChannel({
    required this.points,
    required this.frame,
  });

  final Map<String, LandmarkPoint> points;
  final BodyFrame frame;

  Map<String, dynamic> toJson() => {
        for (final e in points.entries) e.key: e.value.toJson(),
        'frame': frame.toJson(),
      };
}

/// Compact non-manual face / head quantities.
class NonmanualChannel {
  const NonmanualChannel({
    required this.head,
    required this.mouth,
    required this.brow,
    required this.eye,
  });

  final Map<String, double> head;
  final Map<String, double> mouth;
  final Map<String, double> brow;
  final Map<String, double> eye;

  Map<String, dynamic> toJson() => {
        'head': head,
        'mouth': mouth,
        'brow': brow,
        'eye': eye,
      };
}

/// Hands packing for `csl_channels_v1` / `mediapipe_hands_v1`.
class HandsChannel {
  const HandsChannel({required this.points});

  /// Fixed length 42; missing slots use `v = 0`.
  final List<LandmarkPoint> points;

  Map<String, dynamic> toJson() => {
        'schema': 'mediapipe_hands_v1',
        'points': points.map((p) => p.toJson()).toList(growable: false),
      };
}

/// Uplink payload projected from the envelope frame.
class CslChannelsLandmarks {
  const CslChannelsLandmarks({
    required this.ts,
    required this.sessionId,
    this.hands,
    this.path,
    this.body,
    this.nonmanual,
  });

  final int ts;
  final String sessionId;
  final HandsChannel? hands;
  final PathChannel? path;
  final BodyChannel? body;
  final NonmanualChannel? nonmanual;

  static const schema = 'csl_channels_v1';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': 'landmarks',
      'protocolVersion': 1,
      'ts': ts,
      'sessionId': sessionId,
      'schema': schema,
    };
    if (hands != null) json['hands'] = hands!.toJson();
    if (path != null) json['path'] = path!.toJson();
    if (body != null) json['body'] = body!.toJson();
    if (nonmanual != null) json['nonmanual'] = nonmanual!.toJson();
    return json;
  }
}
