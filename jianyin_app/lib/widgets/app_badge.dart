import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space2,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppTokens.goldSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: AppTokens.textXs,
          fontWeight: FontWeight.w600,
          color: Color(0xFF92600A),
        ),
      ),
    );
  }
}
