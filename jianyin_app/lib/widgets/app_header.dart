import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'icon_btn.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  const AppHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Size get preferredSize => const Size.fromHeight(AppTokens.touchMin + 8);

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Material(
      color: AppTokens.paperElevated,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTokens.border)),
        ),
        padding: EdgeInsets.only(
          top: top + AppTokens.space2,
          bottom: AppTokens.space2,
          left: AppTokens.space2,
          right: AppTokens.space4,
        ),
        child: Row(
          children: [
            if (onBack != null)
              AppIconBtn(
                tooltip: '返回',
                onPressed: onBack,
                child: const Icon(Icons.chevron_left, size: AppTokens.iconMd),
              )
            else
              const SizedBox(width: AppTokens.touchMin),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class HeaderTextButton extends StatelessWidget {
  const HeaderTextButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: AppTokens.teal,
        disabledForegroundColor: AppTokens.fgMuted.withValues(alpha: 0.55),
        minimumSize: const Size(0, AppTokens.touchMin),
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.space3),
        textStyle: const TextStyle(
          fontSize: AppTokens.textSm,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}
