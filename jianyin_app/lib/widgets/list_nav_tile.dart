import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ListNavTile extends StatelessWidget {
  const ListNavTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.paperElevated,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppTokens.space4,
            vertical: AppTokens.space3,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: danger
                      ? const Color(0xFFFEE2E2)
                      : AppTokens.tealSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: danger ? AppTokens.danger : AppTokens.teal,
                ),
              ),
              const SizedBox(width: AppTokens.space3),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: AppTokens.iconMd,
                color: AppTokens.fgMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ListNavGroup extends StatelessWidget {
  const ListNavGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.paperElevated,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: AppTokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, color: AppTokens.muted),
          ],
        ],
      ),
    );
  }
}
