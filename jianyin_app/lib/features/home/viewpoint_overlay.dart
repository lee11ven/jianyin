import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

class ViewpointOverlay extends StatelessWidget {
  const ViewpointOverlay({
    super.key,
    required this.offline,
    required this.caption,
  });

  final bool offline;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final color = offline ? AppTokens.vpRed : AppTokens.vpGreen;
    final frameW = MediaQuery.sizeOf(context).width * 0.72;
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
                painter: _ViewpointPainter(color: color),
              ),
            ),
            const SizedBox(height: AppTokens.space3),
            Text(
              caption,
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
  _ViewpointPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    const arm = 22.0;
    // corners
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), paint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-arm, 0), paint);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), paint);
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(arm, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(0, -arm),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(-arm, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(0, -arm),
      paint,
    );

    // head oval
    final head = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.28),
      width: size.width * 0.28,
      height: size.height * 0.16,
    );
    canvas.drawOval(head, paint..strokeWidth = 1.5);

    // shoulder dashed line
    final dash = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25;
    final y = size.height * 0.48;
    final start = Offset(size.width * 0.18, y);
    final end = Offset(size.width * 0.82, y);
    _drawDashed(canvas, start, end, dash);
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashWidth = 6.0;
    const gap = 5.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final from = a + dir * drawn;
      final to = a + dir * (drawn + dashWidth).clamp(0, total);
      canvas.drawLine(from, to, paint);
      drawn += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _ViewpointPainter oldDelegate) =>
      oldDelegate.color != color;
}
