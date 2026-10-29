import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

/// Locked ML input format for the dual-platform MethodChannel.
///
/// Contiguous **RGBA8888** bytes, row-major, no padding. Rotation already
/// applied so landmarks map to the upright preview the user sees. Algorithm
/// side does **not** mirror again (rear camera + plugin orientation).
class VisionFrame {
  const VisionFrame({
    required this.rgba,
    required this.width,
    required this.height,
    required this.ts,
    this.rotationDegrees = 0,
  });

  final Uint8List rgba;
  final int width;
  final int height;
  final int ts;

  /// Sensor rotation already baked into [rgba] when non-zero was used upstream.
  final int rotationDegrees;

  Map<String, dynamic> toChannelArgs() => {
        'format': 'rgba',
        'width': width,
        'height': height,
        'ts': ts,
        'rotationDegrees': 0,
        'bytes': rgba,
      };
}

/// Convert a [CameraImage] to upright RGBA for MediaPipe IMAGE mode.
///
/// Downscales so the long edge ≤ [maxLongEdge] to keep MethodChannel payload
/// and inference cost bounded on mid-range phones.
Future<VisionFrame?> cameraImageToVisionFrame(
  CameraImage image, {
  required int ts,
  required int sensorOrientation,
  int maxLongEdge = 480,
}) {
  return compute(
    _convertIsolate,
    _ConvertArgs(
      planes: [
        for (final p in image.planes)
          _PlaneData(
            bytes: p.bytes,
            bytesPerRow: p.bytesPerRow,
            bytesPerPixel: p.bytesPerPixel ?? 1,
          ),
      ],
      width: image.width,
      height: image.height,
      formatGroup: image.format.group.name,
      rawFormat: image.format.raw,
      ts: ts,
      sensorOrientation: sensorOrientation,
      maxLongEdge: maxLongEdge,
    ),
  );
}

class _PlaneData {
  const _PlaneData({
    required this.bytes,
    required this.bytesPerRow,
    required this.bytesPerPixel,
  });

  final Uint8List bytes;
  final int bytesPerRow;
  final int bytesPerPixel;
}

class _ConvertArgs {
  const _ConvertArgs({
    required this.planes,
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.rawFormat,
    required this.ts,
    required this.sensorOrientation,
    required this.maxLongEdge,
  });

  final List<_PlaneData> planes;
  final int width;
  final int height;
  final String formatGroup;
  final dynamic rawFormat;
  final int ts;
  final int sensorOrientation;
  final int maxLongEdge;
}

VisionFrame? _convertIsolate(_ConvertArgs args) {
  if (args.planes.isEmpty) return null;

  final srcW = args.width;
  final srcH = args.height;
  Uint8List rgba;

  final group = args.formatGroup;
  if (group == 'bgra8888' || args.rawFormat == 1111970369 /* BGRA */) {
    rgba = _bgraToRgba(args.planes.first, srcW, srcH);
  } else {
    // yuv420 / nv21-style (Android default).
    rgba = _yuv420ToRgba(args.planes, srcW, srcH);
  }

  final rotated = _rotateRgba(rgba, srcW, srcH, args.sensorOrientation);
  var w = rotated.$2;
  var h = rotated.$3;
  var bytes = rotated.$1;

  final longEdge = w > h ? w : h;
  if (longEdge > args.maxLongEdge) {
    final scale = args.maxLongEdge / longEdge;
    final nw = (w * scale).round().clamp(1, args.maxLongEdge);
    final nh = (h * scale).round().clamp(1, args.maxLongEdge);
    bytes = _downscaleRgba(bytes, w, h, nw, nh);
    w = nw;
    h = nh;
  }

  return VisionFrame(rgba: bytes, width: w, height: h, ts: args.ts);
}

Uint8List _bgraToRgba(_PlaneData plane, int width, int height) {
  final out = Uint8List(width * height * 4);
  final src = plane.bytes;
  final stride = plane.bytesPerRow;
  for (var y = 0; y < height; y++) {
    final row = y * stride;
    final oRow = y * width * 4;
    for (var x = 0; x < width; x++) {
      final i = row + x * 4;
      final o = oRow + x * 4;
      if (i + 3 >= src.length) break;
      out[o] = src[i + 2];
      out[o + 1] = src[i + 1];
      out[o + 2] = src[i];
      out[o + 3] = src[i + 3];
    }
  }
  return out;
}

Uint8List _yuv420ToRgba(List<_PlaneData> planes, int width, int height) {
  final out = Uint8List(width * height * 4);
  final yPlane = planes[0];
  final yBytes = yPlane.bytes;
  final yStride = yPlane.bytesPerRow;

  // Prefer NV21/NV12 (2 planes) then I420 (3 planes). Approximation is fine for landmarks.
  if (planes.length >= 2 && planes[1].bytesPerPixel == 2) {
    final uv = planes[1].bytes;
    final uvStride = planes[1].bytesPerRow;
    final nv21 = planes.length == 2; // camera plugin often packs VU on Android
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yi = yBytes[y * yStride + x] & 0xff;
        final uvIndex = (y >> 1) * uvStride + (x & ~1);
        int u;
        int v;
        if (nv21) {
          v = uv[uvIndex] & 0xff;
          u = uv[uvIndex + 1] & 0xff;
        } else {
          u = uv[uvIndex] & 0xff;
          v = uv[uvIndex + 1] & 0xff;
        }
        _yuvToRgbaPixel(out, (y * width + x) * 4, yi, u, v);
      }
    }
    return out;
  }

  if (planes.length >= 3) {
    final uBytes = planes[1].bytes;
    final vBytes = planes[2].bytes;
    final uStride = planes[1].bytesPerRow;
    final vStride = planes[2].bytesPerRow;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final yi = yBytes[y * yStride + x] & 0xff;
        final ui = uBytes[(y >> 1) * uStride + (x >> 1)] & 0xff;
        final vi = vBytes[(y >> 1) * vStride + (x >> 1)] & 0xff;
        _yuvToRgbaPixel(out, (y * width + x) * 4, yi, ui, vi);
      }
    }
    return out;
  }

  // Grayscale fallback from Y only.
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final yi = yBytes[y * yStride + x];
      final o = (y * width + x) * 4;
      out[o] = yi;
      out[o + 1] = yi;
      out[o + 2] = yi;
      out[o + 3] = 255;
    }
  }
  return out;
}

void _yuvToRgbaPixel(Uint8List out, int o, int y, int u, int v) {
  final c = y - 16;
  final d = u - 128;
  final e = v - 128;
  final r = ((298 * c + 409 * e + 128) >> 8).clamp(0, 255);
  final g = ((298 * c - 100 * d - 208 * e + 128) >> 8).clamp(0, 255);
  final b = ((298 * c + 516 * d + 128) >> 8).clamp(0, 255);
  out[o] = r;
  out[o + 1] = g;
  out[o + 2] = b;
  out[o + 3] = 255;
}

(Uint8List, int, int) _rotateRgba(
  Uint8List src,
  int width,
  int height,
  int degrees,
) {
  final d = ((degrees % 360) + 360) % 360;
  if (d == 0) return (src, width, height);

  if (d == 180) {
    final out = Uint8List(src.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final si = (y * width + x) * 4;
        final di = ((height - 1 - y) * width + (width - 1 - x)) * 4;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    return (out, width, height);
  }

  final outW = height;
  final outH = width;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final si = (y * width + x) * 4;
      late int dx;
      late int dy;
      if (d == 90) {
        dx = height - 1 - y;
        dy = x;
      } else {
        // 270
        dx = y;
        dy = width - 1 - x;
      }
      final di = (dy * outW + dx) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = src[si + 3];
    }
  }
  return (out, outW, outH);
}

Uint8List _downscaleRgba(
  Uint8List src,
  int sw,
  int sh,
  int dw,
  int dh,
) {
  final out = Uint8List(dw * dh * 4);
  for (var y = 0; y < dh; y++) {
    final sy = (y * sh / dh).floor().clamp(0, sh - 1);
    for (var x = 0; x < dw; x++) {
      final sx = (x * sw / dw).floor().clamp(0, sw - 1);
      final si = (sy * sw + sx) * 4;
      final di = (y * dw + x) * 4;
      out[di] = src[si];
      out[di + 1] = src[si + 1];
      out[di + 2] = src[si + 2];
      out[di + 3] = src[si + 3];
    }
  }
  return out;
}

/// Y-plane metrics on the raw camera buffer (no full RGBA convert).
class YPlaneMetrics {
  const YPlaneMetrics({required this.motionEnergy, required this.sharpness});

  final double motionEnergy;
  final double sharpness;
}

YPlaneMetrics measureYPlane({
  required Uint8List yBytes,
  required int width,
  required int height,
  required int bytesPerRow,
  Uint8List? previousY,
  int sampleStep = 4,
}) {
  var energy = 0.0;
  var count = 0;
  if (previousY != null && previousY.length == yBytes.length) {
    for (var y = 0; y < height; y += sampleStep) {
      final row = y * bytesPerRow;
      for (var x = 0; x < width; x += sampleStep) {
        final i = row + x;
        if (i >= yBytes.length || i >= previousY.length) continue;
        energy += (yBytes[i] - previousY[i]).abs();
        count++;
      }
    }
  }
  final motion = count == 0 ? 0.0 : energy / count;

  // Laplacian-ish variance on a coarse grid.
  var sum = 0.0;
  var sumSq = 0.0;
  var n = 0;
  for (var y = sampleStep; y < height - sampleStep; y += sampleStep) {
    for (var x = sampleStep; x < width - sampleStep; x += sampleStep) {
      final c = yBytes[y * bytesPerRow + x] & 0xff;
      final l = yBytes[y * bytesPerRow + (x - sampleStep)] & 0xff;
      final r = yBytes[y * bytesPerRow + (x + sampleStep)] & 0xff;
      final u = yBytes[(y - sampleStep) * bytesPerRow + x] & 0xff;
      final d = yBytes[(y + sampleStep) * bytesPerRow + x] & 0xff;
      final lap = (4 * c - l - r - u - d).toDouble();
      sum += lap;
      sumSq += lap * lap;
      n++;
    }
  }
  final mean = n == 0 ? 0.0 : sum / n;
  final sharpness = n == 0 ? 0.0 : (sumSq / n) - mean * mean;
  return YPlaneMetrics(motionEnergy: motion, sharpness: sharpness);
}
