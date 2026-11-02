import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Bottom caption panel — fixed 200 logical pixels (dp).
class CaptionZone extends StatelessWidget {
  const CaptionZone({
    super.key,
    required this.history,
    required this.current,
    this.height = heightDp,
  });

  /// Fixed height of the caption panel in logical pixels (dp).
  static const heightDp = 200.0;

  final List<String> history;
  final String current;

  /// 实际占用高度。短屏会低于 [heightDp]，避免把取景框顶出屏幕。
  final double height;

  static const _labelStyle = TextStyle(
    color: AppTokens.fgOnInkMuted,
    fontSize: AppTokens.textXs,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.02 * AppTokens.textXs,
  );

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      ...history,
      if (current.isNotEmpty) current,
    ];
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final padTop = AppTokens.space4;
    final padBottom = AppTokens.space5 + bottomInset;
    final overhead = padTop + padBottom + AppTokens.space2 + AppTokens.textXs + 24;

    if (height < overhead) {
      return _glass(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.space4),
        child: const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '实时字幕',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _labelStyle,
          ),
        ),
      );
    }

    return _glass(
      height: height,
      padding: EdgeInsets.fromLTRB(
        AppTokens.space4,
        padTop,
        AppTokens.space4,
        padBottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '实时字幕',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _labelStyle,
          ),
          const SizedBox(height: AppTokens.space2),
          Expanded(
            child: SingleChildScrollView(
              reverse: true,
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: AppTokens.fgOnInk,
                    fontSize: AppTokens.textXl,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                  children: [
                    TextSpan(text: lines.join('\n')),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _GoldCursor(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glass({
    required double height,
    required EdgeInsets padding,
    required Widget child,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: const BoxDecoration(
              color: AppTokens.captionGlass,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GoldCursor extends StatefulWidget {
  @override
  State<_GoldCursor> createState() => _GoldCursorState();
}

class _GoldCursorState extends State<_GoldCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        margin: const EdgeInsets.only(left: 2),
        width: 2,
        height: 16,
        color: AppTokens.gold,
      ),
    );
  }
}
