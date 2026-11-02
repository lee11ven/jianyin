import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../perception/viewpoint.dart';
import '../../theme/tokens.dart';

/// 写死在预览上的构图模板：顶对齐、3:4，不跟随鼻点移动。
///
/// 父级需要给出有界高度（顶栏和字幕之间的剩余区域）。框放不下时缩小，
/// 放不下一整框时只留一行说明，避免把字幕区和提示胶囊挤出屏幕。
class ViewpointOverlay extends StatelessWidget {
  const ViewpointOverlay({
    super.key,
    required this.caption,
    this.band,
  });

  final String caption;

  /// 机位档：绿/黄/红驱动取景框三色。null 按绿。
  final ValveBand? band;

  static const _maxWidth = 280.0;
  static const _widthFraction = 0.78;
  static const _maxHeightFraction = 0.46;
  static const _minFrame = 48.0;

  @override
  Widget build(BuildContext context) {
    final active = band ?? ValveBand.green;
    final stroke = switch (active) {
      ValveBand.green => AppTokens.vpGreen,
      ValveBand.yellow => AppTokens.vpYellow,
      ValveBand.red => AppTokens.vpRed,
    };
    final captionColor = active == ValveBand.green
        ? const Color(0x8CF1F5F9)
        : stroke;

    final captionStyle = TextStyle(
      color: captionColor,
      fontSize: AppTokens.textXs,
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: 0.04 * AppTokens.textXs,
      shadows: const [
        Shadow(color: Colors.black54, blurRadius: 6),
      ],
    );

    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slotH = constraints.maxHeight;
            final line = MediaQuery.textScalerOf(context).scale(AppTokens.textXs) *
                1.2;
            // 说明比剩余区域还高时，只留一行，不再排框。
            if (slotH < line + AppTokens.space3 + _minFrame) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: Text(
                  caption,
                  maxLines: 1,
                  style: captionStyle,
                ),
              );
            }

            final screenH = MediaQuery.sizeOf(context).height;
            return Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, frameSlot) {
                      final frame = _fitFrame(
                        maxWidth: frameSlot.maxWidth,
                        maxHeight: frameSlot.maxHeight,
                        screenHeight: screenH,
                      );
                      if (frame == null) return const SizedBox.shrink();
                      return Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: frame.width,
                          height: frame.height,
                          child: CustomPaint(
                            key: const ValueKey('vp-frame'),
                            painter: _ViewpointPainter(color: stroke),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: AppTokens.space3),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: captionStyle,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Size? _fitFrame({
    required double maxWidth,
    required double maxHeight,
    required double screenHeight,
  }) {
    if (maxWidth < 2 || maxHeight < 2) return null;
    var frameW = math.min(maxWidth * _widthFraction, _maxWidth);
    var frameH = frameW * 4 / 3;
    final cap = math.min(maxHeight, screenHeight * _maxHeightFraction);
    if (frameH > cap) {
      frameH = cap;
      frameW = frameH * 3 / 4;
    }
    if (frameW < _minFrame || frameH < _minFrame) return null;
    return Size(frameW, frameH);
  }
}

class _ViewpointPainter extends CustomPainter {
  _ViewpointPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final arm = math.min(28.0, math.min(size.width, size.height) * 0.22);
    canvas.drawLine(Offset.zero, Offset(arm, 0), stroke);
    canvas.drawLine(Offset.zero, Offset(0, arm), stroke);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - arm, 0), stroke);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, arm), stroke);
    canvas.drawLine(Offset(0, size.height), Offset(arm, size.height), stroke);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - arm), stroke);
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - arm, size.height),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - arm),
      stroke,
    );

    final shoulder = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final shoulderY = size.height * 0.38;
    _drawDashedLine(
      canvas,
      Offset(size.width * 0.12, shoulderY),
      Offset(size.width * 0.88, shoulderY),
      shoulder,
    );

    final headW = math.min(size.width * 0.22, size.height * 0.34);
    final head = Rect.fromLTWH(
      (size.width - headW) / 2,
      size.height * 0.14,
      headW,
      headW,
    );
    final headPaint = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    _drawDashedOval(canvas, head, headPaint);
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const gap = 5.0;
    final total = (b - a).distance;
    if (total < 1) return;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final from = a + dir * drawn;
      final to = a + dir * math.min(drawn + dashWidth, total);
      canvas.drawLine(from, to, paint);
      drawn += dashWidth + gap;
    }
  }

  void _drawDashedOval(Canvas canvas, Rect rect, Paint paint) {
    if (rect.width < 2 || rect.height < 2) return;
    const dash = 4.0;
    const gap = 3.5;
    final metric = Path()..addOval(rect);
    for (final part in metric.computeMetrics()) {
      var dist = 0.0;
      while (dist < part.length) {
        final next = math.min(dist + dash, part.length);
        canvas.drawPath(part.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ViewpointPainter oldDelegate) =>
      oldDelegate.color != color;
}
