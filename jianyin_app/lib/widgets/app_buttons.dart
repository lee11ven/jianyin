import 'package:flutter/material.dart';

import '../theme/tokens.dart';

enum AppButtonVariant { primary, ghost, danger }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.enabled = true,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
  }) : variant = AppButtonVariant.primary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.enabled = true,
  }) : variant = AppButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool enabled;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && widget.onPressed != null;
    late final Color bg;
    late final Color fg;
    late final BorderSide border;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        bg = AppTokens.teal;
        fg = Colors.white;
        border = BorderSide.none;
      case AppButtonVariant.ghost:
        bg = Colors.transparent;
        fg = AppTokens.fgMuted;
        border = const BorderSide(color: AppTokens.border);
      case AppButtonVariant.danger:
        bg = Colors.transparent;
        fg = AppTokens.danger;
        border = BorderSide(color: AppTokens.danger.withValues(alpha: 0.35));
    }

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _pressed = false);
                widget.onPressed?.call();
              }
            : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: AppTokens.durationFast,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: AppTokens.touchMin),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(AppTokens.radiusBtn),
              border: Border.fromBorderSide(border),
            ),
            child: Text(
              widget.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: fg,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
