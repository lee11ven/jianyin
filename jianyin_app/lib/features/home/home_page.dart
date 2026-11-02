import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../router/app_router.dart';
import '../../session/home_session_controller.dart';
import '../../theme/tokens.dart';
import '../../widgets/icon_btn.dart';
import 'camera_preview_panel.dart';
import 'caption_zone.dart';
import 'runtime_status_pill.dart';
import 'sense_status.dart';
import 'viewpoint_overlay.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final HomeSessionController _session;
  bool _showUpperBodyHint = false;

  @override
  void initState() {
    super.initState();
    _session = HomeSessionController()..start();
  }

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  Future<void> _leaveTo(String route) async {
    // Don't await stop — WS/API teardown can take seconds after the camera
    // is already cleared, which leaves a blank home frame (feels like 白屏).
    unawaited(_session.stop());
    if (!mounted) return;
    context.go(route);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppTokens.ink,
      ),
      child: Scaffold(
        backgroundColor: AppTokens.ink,
        body: ListenableBuilder(
          listenable: _session,
          builder: (context, _) {
            final senseMeta = _session.meta;
            final hintText = _showUpperBodyHint
                ? '请把头部、双肩和双手一起放入画面'
                : senseMeta.hint;
            final hintTone = _showUpperBodyHint ? HintTone.warn : senseMeta.hintTone;
            return Stack(
              fit: StackFit.expand,
              children: [
                CameraPreviewPanel(
                  onCameraReady: _session.onCameraReady,
                  onHintShowUpperBody: (show) {
                    if (show == _showUpperBodyHint) return;
                    setState(() => _showUpperBodyHint = show);
                  },
                  onLandmarks: _session.onLandmarks,
                  onPerception: _session.onPerception,
                ),
                ListenableBuilder(
                  listenable: _session.faceTracker,
                  builder: (context, _) {
                    final faceTracker = _session.faceTracker;
                    final screenW = MediaQuery.sizeOf(context).width;
                    return Stack(
                      children: [
                        ViewpointOverlay(
                          offline: _session.vpOffline,
                          caption: _session.hintText.isNotEmpty
                              ? _session.hintText
                              : _session.vpCaption,
                          band: _session.vpBand,
                          faceTracker: faceTracker,
                          screenWidthDp: screenW,
                        ),
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: _CameraTopbar(
                            status: _session.sense,
                            onProfile: () => _leaveTo(AppRoutes.profile),
                            onSettings: () => _leaveTo(AppRoutes.settings),
                          ),
                        ),
                        Positioned(
                          left: AppTokens.space5,
                          right: AppTokens.space5,
                          top: MediaQuery.paddingOf(context).top + 72,
                          child: _CameraHint(
                            text: hintText,
                            tone: hintTone,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: CaptionZone.heightDp,
                          child: CaptionZone(
                            history: _session.captionHistory,
                            current: _session.currentCaption,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CameraTopbar extends StatelessWidget {
  const _CameraTopbar({
    required this.status,
    required this.onProfile,
    required this.onSettings,
  });

  final SenseStatus status;
  final VoidCallback onProfile;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          color: AppTokens.topbarBg,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top + AppTokens.space2,
            bottom: AppTokens.space2,
            left: AppTokens.space3,
            right: AppTokens.space2,
          ),
          child: Row(
            children: [
              RuntimeStatusPill(status: status),
              const Spacer(),
              AppIconBtn(
                tooltip: '个人中心',
                color: AppTokens.fgOnInk,
                onPressed: onProfile,
                child: const Icon(Icons.person_outline),
              ),
              AppIconBtn(
                tooltip: '设置',
                color: AppTokens.fgOnInk,
                onPressed: onSettings,
                child: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraHint extends StatelessWidget {
  const _CameraHint({required this.text, required this.tone});

  final String text;
  final HintTone tone;

  Color get _bg {
    switch (tone) {
      case HintTone.muted:
        return AppTokens.hintMuted;
      case HintTone.warn:
        return AppTokens.hintWarn;
      case HintTone.danger:
        return AppTokens.hintDanger;
      case HintTone.none:
        return AppTokens.hintBg;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppTokens.space4,
          vertical: AppTokens.space2,
        ),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppTokens.textSm,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
