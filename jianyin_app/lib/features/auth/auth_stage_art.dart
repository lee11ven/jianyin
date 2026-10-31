import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

enum AuthStageKind { hello, happiness }

/// 登录/注册 overlap 壳：径向背景 + body 在板后、elbows 在板上。
///
/// 对齐 HTML `.auth-layout--overlap`（app.css）。
class AuthOverlapScaffold extends StatelessWidget {
  const AuthOverlapScaffold({
    super.key,
    required this.kind,
    required this.child,
  });

  final AuthStageKind kind;
  final Widget child;

  static const _helloBody = 'assets/auth/hello_wave.png';
  static const _helloElbows = 'assets/auth/hello_wave_elbows.png';
  static const _happinessBody = 'assets/auth/happiness_sign.png';
  static const _happinessElbows = 'assets/auth/happiness_elbows.png';

  /// CSS: login `--mascot-sink: 68px` / register `47px`
  double get _sink => kind == AuthStageKind.hello ? 68 : 47;

  /// CSS: login `min(98%, 340px)` / register `min(80%, 340px)`
  double get _widthFactor => kind == AuthStageKind.hello ? 0.98 : 0.80;

  String get _bodyAsset =>
      kind == AuthStageKind.hello ? _helloBody : _happinessBody;

  String get _elbowsAsset =>
      kind == AuthStageKind.hello ? _helloElbows : _happinessElbows;

  String get _semanticLabel =>
      kind == AuthStageKind.hello ? '你好' : '幸福';

  /// CSS overlap panel: `padding-top: calc(var(--space-6) + 16px)` = 48
  static const panelPaddingTop = AppTokens.space6 + AppTokens.space4;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppTokens.ink,
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Keep a short stage strip so the mascot stays visible; panel scrolls.
          final panelMaxHeight = math.max(
            constraints.maxHeight * 0.78,
            constraints.maxHeight - 120,
          );
          return Column(
            children: [
              const Expanded(child: _AuthStageBackground()),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: panelMaxHeight),
                child: _AuthOverlapAnchor(
                  sink: _sink,
                  widthFactor: _widthFactor,
                  bodyAsset: _bodyAsset,
                  elbowsAsset: _elbowsAsset,
                  semanticLabel: _semanticLabel,
                  panelPadding: EdgeInsets.fromLTRB(
                    AppTokens.space5,
                    panelPaddingTop,
                    AppTokens.space5,
                    AppTokens.space5 + bottomInset,
                  ),
                  child: child,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AuthStageBackground extends StatelessWidget {
  const _AuthStageBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0xFF1A2744), AppTokens.ink],
          stops: [0.0, 0.7],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

/// 相对面板顶定位 mascot：`bottom: calc(100% - sink)`。
class _AuthOverlapAnchor extends StatelessWidget {
  const _AuthOverlapAnchor({
    required this.sink,
    required this.widthFactor,
    required this.bodyAsset,
    required this.elbowsAsset,
    required this.semanticLabel,
    required this.panelPadding,
    required this.child,
  });

  final double sink;
  final double widthFactor;
  final String bodyAsset;
  final String elbowsAsset;
  final String semanticLabel;
  final EdgeInsets panelPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final mascotSize = math.min(maxW * widthFactor, 340.0);
        // CSS: bottom: calc(100% - sink) → 贴齐面板顶再下沉 sink
        // Flutter: top = sink - mascotSize（负值探出面板上方）
        final mascotTop = sink - mascotSize;

        Positioned mascotLayer({
          required String asset,
          String? label,
        }) {
          return Positioned(
            left: (maxW - mascotSize) / 2,
            width: mascotSize,
            height: mascotSize,
            top: mascotTop,
            child: IgnorePointer(
              child: Image.asset(
                asset,
                width: mascotSize,
                height: mascotSize,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                semanticLabel: label,
                excludeFromSemantics: label == null,
              ),
            ),
          );
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // z1: body 在面板后面
            mascotLayer(asset: bodyAsset, label: semanticLabel),
            // z2: 纸面面板
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppTokens.paper,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppTokens.radiusXl),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x140B1220),
                    blurRadius: 32,
                    offset: Offset(0, -8),
                  ),
                ],
              ),
              padding: panelPadding,
              child: child,
            ),
            // z3: elbows 压在面板上（与 body 同几何）
            mascotLayer(asset: elbowsAsset),
          ],
        );
      },
    );
  }
}
