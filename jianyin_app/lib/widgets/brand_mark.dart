import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// 见音品牌标识：App Logo + 名称。
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.compact = false});

  /// 仅显示图标，不显示「见音」文字。
  final bool compact;

  static const _logoAsset = 'assets/branding/logo.png';

  @override
  Widget build(BuildContext context) {
    final logo = ClipRRect(
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: Image.asset(
        _logoAsset,
        width: compact ? 36 : 44,
        height: compact ? 36 : 44,
        fit: BoxFit.cover,
        semanticLabel: '见音',
      ),
    );

    if (compact) return logo;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(width: AppTokens.space3),
        Text('见音', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
