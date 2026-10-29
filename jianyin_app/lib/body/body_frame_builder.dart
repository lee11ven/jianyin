import 'dart:math' as math;

import '../config/perception_thresholds.dart';
import '../envelope/csl_channels.dart';
import '../envelope/landmark_point.dart';
import 'body_types.dart';

/// Result of building axes from a pose landmark list.
class BodyBuildResult {
  const BodyBuildResult({
    this.body,
    this.axes,
    this.wristL,
    this.wristR,
  });

  final BodyChannel? body;
  final BodyAxes? axes;
  final LandmarkPoint? wristL;
  final LandmarkPoint? wristR;
}

/// Pure Dart shoulder/nose body-frame construction (testable without MediaPipe).
class BodyFrameBuilder {
  const BodyFrameBuilder({this.thresholds = PerceptionThresholds.defaults});

  final PerceptionThresholds thresholds;

  /// MediaPipe Pose indices.
  static const nose = 0;
  static const shoulderL = 11;
  static const shoulderR = 12;
  static const wristL = 15;
  static const wristR = 16;

  BodyBuildResult build(List<LandmarkPoint> landmarks) {
    final wl = _optional(landmarks, wristL);
    final wr = _optional(landmarks, wristR);
    if (landmarks.length <= shoulderR) {
      return BodyBuildResult(wristL: wl, wristR: wr);
    }
    final n = landmarks[nose];
    final sl = landmarks[shoulderL];
    final sr = landmarks[shoulderR];
    if (n.v < thresholds.vAnchor ||
        sl.v < thresholds.vAnchor ||
        sr.v < thresholds.vAnchor) {
      return BodyBuildResult(wristL: wl, wristR: wr);
    }

    final ox = (sl.x + sr.x) * 0.5;
    final oy = (sl.y + sr.y) * 0.5;
    final oz = (sl.z + sr.z) * 0.5;
    final origin = LandmarkPoint(x: ox, y: oy, z: oz, v: 1);
    final dx = sr.x - sl.x;
    final dy = sr.y - sl.y;
    final dz = sr.z - sl.z;
    final shoulderWidth = _len(dx, dy, dz);
    if (shoulderWidth < thresholds.wMin) {
      return BodyBuildResult(wristL: wl, wristR: wr);
    }

    final rx = dx / shoulderWidth;
    final ry = dy / shoulderWidth;
    final rz = dz / shoulderWidth;

    var ux = n.x - ox;
    var uy = n.y - oy;
    var uz = n.z - oz;
    final upLen = _len(ux, uy, uz);
    if (upLen < 1e-6) {
      return BodyBuildResult(wristL: wl, wristR: wr);
    }
    ux /= upLen;
    uy /= upLen;
    uz /= upLen;

    // +Z = +X × +Y; flip so +Z points toward camera (prefer zz <= 0).
    var zx = ry * uz - rz * uy;
    var zy = rz * ux - rx * uz;
    var zz = rx * uy - ry * ux;
    var zSign = 1;
    if (zz > 0) {
      zSign = -1;
      zx = -zx;
      zy = -zy;
      zz = -zz;
    }
    final zLen = _len(zx, zy, zz);
    if (zLen > 1e-6) {
      zx /= zLen;
      zy /= zLen;
      zz /= zLen;
    }

    final axes = BodyAxes(
      origin: origin,
      shoulderWidth: shoulderWidth,
      right: LandmarkPoint(x: rx, y: ry, z: rz, v: 1),
      up: LandmarkPoint(x: ux, y: uy, z: uz, v: 1),
      zSign: zSign,
    );

    final points = <String, LandmarkPoint>{
      'nose': n,
      'shoulderL': sl,
      'shoulderR': sr,
    };
    if (wl != null) points['wristL'] = wl;
    if (wr != null) points['wristR'] = wr;

    return BodyBuildResult(
      body: BodyChannel(points: points, frame: axes.toFrame()),
      axes: axes,
      wristL: wl,
      wristR: wr,
    );
  }

  LandmarkPoint? _optional(List<LandmarkPoint> landmarks, int index) {
    if (index >= landmarks.length) return null;
    final p = landmarks[index];
    if (p.v < thresholds.vAnchor) return null;
    return p;
  }

  static double _len(double x, double y, double z) => math.sqrt(x * x + y * y + z * z);
}
