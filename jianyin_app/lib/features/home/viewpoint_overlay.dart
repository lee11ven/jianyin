import 'package:flutter/material.dart';

import '../../session/home_session_controller.dart';
import '../../theme/tokens.dart';

/// Viewport alignment overlay that follows the real-time face ellipse.
class ViewpointOverlay extends StatefulWidget {
  const ViewpointOverlay({
    super.key,
    required this.offline,
    required this.caption,
    required this.faceTracker,
    required this.screenWidthDp,
  });

  final bool offline;
  final String caption;
  final FaceTracker faceTracker;
  final double screenWidthDp;

  @override
  State<ViewpointOverlay> createState() => _ViewpointOverlayState();
}

class _ViewpointOverlayState extends State<ViewpointOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _alignController;
  double _alignedRatio = 1.0;

  @override
  void initState() {
    super.initState();
    _alignController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    widget.faceTracker.addListener(_onFaceUpdate);
  }

  @override
  void dispose() {
    widget.faceTracker.removeListener(_onFaceUpdate);
    _alignController.dispose();
    super.dispose();
  }

  void _onFaceUpdate() {
    if (!widget.faceTracker.hasFace) return;
    final dx = widget.faceTracker.x! - 0.5;
    if (dx.abs() < 0.02) {
      if (_alignedRatio != 1.0) {
        setState(() => _alignedRatio = 1.0);
        _alignController.forward(from: 0);
      }
    } else {
      _alignedRatio = (1.0 - dx.abs() * 2).clamp(0.0, 1.0);
      _alignController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.offline ? AppTokens.vpRed : AppTokens.vpGreen;
    final frameW = widget.screenWidthDp * 0.72;
    final frameH = frameW * 4 / 3;

    return IgnorePointer(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: frameW,
              height: frameH,
              child: CustomPaint(
                painter: _ViewpointPainter(
                  color: color,
                  faceTracker: widget.faceTracker,
                  frameW: frameW,
                  frameH: frameH,
                  screenWidthDp: widget.screenWidthDp,
                  alignedRatio: _alignedRatio,
                ),
              ),
            ),
            const SizedBox(height: AppTokens.space3),
            Text(
              widget.caption,
              style: TextStyle(
                color: color,
                fontSize: AppTokens.textXs,
                fontWeight: FontWeight.w500,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 6),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewpointPainter extends CustomPainter {
  _ViewpointPainter({
    required this.color,
    required this.faceTracker,
    required this.frameW,
    required this.frameH,
    required this.screenWidthDp,
    required this.alignedRatio,
  });

  final Color color;
  final FaceTracker faceTracker;
  final double frameW;
  final double frameH;
  final double screenWidthDp;
  final double alignedRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const arm = 22.0;
    // Corner brackets
    canvas.drawLine(Offset.zero, Offset(arm, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, arm), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - arm, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, arm), paint);
    canvas.drawLine(Offset(0, size.height), Offset(arm, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(0, size.height - arm), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - arm, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width, size.height - arm), paint);

    // Shoulder dashed line
    final dash = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final shoulderY = size.height * 0.48;
    _drawDashed(
      canvas,
      Offset(size.width * 0.18, shoulderY),
      Offset(size.width * 0.82, shoulderY),
      dash,
    );

    // Face ellipse — tracks real nose landmark
    if (faceTracker.hasFace) {
      final pos = faceToOverlayPos(
        face: Offset(faceTracker.x!, faceTracker.y!),
        overlayFrameWidthDp: frameW,
        screenWidthDp: screenWidthDp,
      );
      final headW = size.width * 0.22;
      final headH = size.height * 0.30;
      final head = Rect.fromCenter(
        center: pos,
        width: headW,
        height: headH,
      );
      canvas.drawOval(head, paint..strokeWidth = 1.5);
    } else {
      // Placeholder when no face detected yet
      final head = Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.30),
        width: size.width * 0.22,
        height: size.height * 0.30,
      );
      canvas.drawOval(
        head,
        paint
          ..color = color.withValues(alpha: 0.4)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    // Center-alignment arrow when face is off-center
    if (faceTracker.hasFace && alignedRatio < 0.95) {
      final arrowPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final cx = size.width / 2;
      final cy = size.height * 0.30;
      final dy = (0.5 - faceTracker.y!) * size.height * 0.15;
      final arrowDir = dy.sign;
      final arrowY = cy + dy;
      canvas.drawLine(Offset(cx, cy - 8 * arrowDir), Offset(cx, arrowY), arrowPaint);
      final tipSize = 5.0;
      canvas.drawLine(
        Offset(cx - tipSize, arrowY - 6 * arrowDir),
        Offset(cx, arrowY),
        arrowPaint,
      );
      canvas.drawLine(
        Offset(cx + tipSize, arrowY - 6 * arrowDir),
        Offset(cx, arrowY),
        arrowPaint,
      );
    }
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const gap = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final from = a + dir * drawn;
      final to = a + dir * (drawn + dashWidth).clamp(0.0, total);
      canvas.drawLine(from, to, paint);
      drawn += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ViewpointPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.faceTracker != faceTracker ||
      oldDelegate.alignedRatio != alignedRatio;
}
