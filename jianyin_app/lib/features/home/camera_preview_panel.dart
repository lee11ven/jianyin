import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../camera/frame_sampler.dart';
import '../../perception/perception_runtime.dart';

/// Rear camera preview + Idle/Active frame sampler -> perception tick.
///
/// Promotes PerceptionRuntime to a shared singleton so the home controller can
/// access catalog() and visionReady status independently of the widget lifecycle.
class CameraPreviewPanel extends StatefulWidget {
  const CameraPreviewPanel({
    super.key,
    this.onCameraReady,
    this.onHintShowUpperBody,
    this.onLandmarks,
  });

  /// Fired once when rear preview is initialized (before / with perception).
  final VoidCallback? onCameraReady;
  final ValueChanged<bool>? onHintShowUpperBody;
  final ValueChanged<Map<String, dynamic>>? onLandmarks;

  @override
  State<CameraPreviewPanel> createState() => _CameraPreviewPanelState();
}

class _CameraPreviewPanelState extends State<CameraPreviewPanel> {
  CameraController? _controller;
  bool _live = false;
  bool _initTried = false;
  bool _streaming = false;
  PerceptionRuntime? _runtime;
  FrameSampler? _sampler;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (_initTried) return;
    _initTried = true;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        rear,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      final runtime = PerceptionRuntime();
      final ready = await runtime.ensureReady();
      if (!ready) {
        debugPrint(
          'MediaPipe unavailable (camera preview only): ${runtime.visionError}',
        );
      }

      FrameSampler? sampler;
      if (ready) {
        sampler = FrameSampler(
          sensorOrientation: rear.sensorOrientation,
          onTick: (req) async {
            final json = await runtime.tickEnvelope(
              ts: req.ts,
              frame: req.frame,
              handStatePrior: req.handState,
              viewpointClass: req.viewpointClass,
              forcePathGap: req.forcePathGap,
              omitHands: req.omitHands,
            );
            if (json == null) return;
            widget.onHintShowUpperBody?.call(runtime.hintShowUpperBody);
            widget.onLandmarks?.call(json);
          },
        );
      }

      setState(() {
        _controller = controller;
        _live = true;
        _runtime = runtime;
        _sampler = sampler;
      });

      widget.onCameraReady?.call();

      if (sampler != null) {
        await controller.startImageStream((image) {
          _sampler?.onCameraImage(image);
        });
        _streaming = true;
      }
    } catch (e) {
      debugPrint('Camera init failed: $e');
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (_streaming) {
      controller?.stopImageStream().catchError((_) {});
    }
    controller?.dispose();
    _runtime?.dispose();
    _sampler?.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_live && _controller != null && _controller!.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: _controller!.value.previewSize?.height ?? 1,
            height: _controller!.value.previewSize?.width ?? 1,
            child: CameraPreview(_controller!),
          ),
        ),
      );
    }
    return const _CameraFallback();
  }
}

class _CameraFallback extends StatelessWidget {
  const _CameraFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2744), Color(0xFF0D1117)],
        ),
      ),
      child: CustomPaint(
        painter: _SilhouettePainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _SilhouettePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final cx = size.width / 2;
    final head = Rect.fromCenter(
      center: Offset(cx, size.height * 0.32),
      width: size.width * 0.14,
      height: size.height * 0.20,
    );
    canvas.drawOval(head, paint);

    final body = Path()
      ..moveTo(cx - size.width * 0.18, size.height * 0.42)
      ..lineTo(cx + size.width * 0.18, size.height * 0.42)
      ..lineTo(cx + size.width * 0.22, size.height * 0.78)
      ..lineTo(cx - size.width * 0.22, size.height * 0.78)
      ..close();
    canvas.drawPath(body, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
