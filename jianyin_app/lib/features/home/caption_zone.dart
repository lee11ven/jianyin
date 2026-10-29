import 'dart:ui';

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Bottom caption panel — fixed 200 logical pixels (dp).
class CaptionZone extends StatelessWidget {
  const CaptionZone({
    super.key,
    required this.history,
    required this.current,
  });

  /// Fixed height of the caption panel in logical pixels (dp).
  static const heightDp = 200.0;

  final List<String> history;
  final String current;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      ...history,
      if (current.isNotEmpty) current,
    ];

    return SizedBox(
      height: heightDp,
      width: double.infinity,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              AppTokens.space4,
              AppTokens.space4,
              AppTokens.space4,
              AppTokens.space5 + MediaQuery.paddingOf(context).bottom,
            ),
            decoration: const BoxDecoration(
              color: AppTokens.captionGlass,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '实时字幕',
                  style: TextStyle(
                    color: AppTokens.fgOnInkMuted,
                    fontSize: AppTokens.textXs,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.02 * AppTokens.textXs,
                  ),
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
