import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class AppIconBtn extends StatelessWidget {
  const AppIconBtn({
    super.key,
    required this.child,
    this.onPressed,
    this.tooltip,
    this.color,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: backgroundColor ?? Colors.transparent,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: SizedBox(
          width: AppTokens.touchMin,
          height: AppTokens.touchMin,
          child: IconTheme(
            data: IconThemeData(
              color: color ?? IconTheme.of(context).color ?? AppTokens.fg,
              size: AppTokens.iconMd,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
    if (tooltip == null) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}
