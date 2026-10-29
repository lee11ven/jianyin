/// Shared `{x,y,z,v}` landmark sample used by hands / path / body channels.
class LandmarkPoint {
  const LandmarkPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.v,
  });

  final double x;
  final double y;
  final double z;
  final double v;

  static const zero = LandmarkPoint(x: 0, y: 0, z: 0, v: 0);

  Map<String, double> toJson() => {'x': x, 'y': y, 'z': z, 'v': v};

  factory LandmarkPoint.fromJson(Map<String, dynamic> json) {
    return LandmarkPoint(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
      z: (json['z'] as num?)?.toDouble() ?? 0,
      v: (json['v'] as num?)?.toDouble() ?? 0,
    );
  }
}
