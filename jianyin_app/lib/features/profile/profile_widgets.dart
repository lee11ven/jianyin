import 'package:flutter/material.dart';

import '../../session/session_models.dart';
import '../../theme/tokens.dart';

/// Large letter mark — the personal signal of the profile surface.
class ProfileIdentityMark extends StatelessWidget {
  const ProfileIdentityMark({
    super.key,
    required this.letter,
    this.size = 88,
  });

  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '头像，$letter',
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment(-0.6, -0.8),
            end: Alignment(0.7, 0.9),
            colors: [Color(0xFF14B8A6), AppTokens.teal, Color(0xFF134E4A)],
          ),
          border: Border.all(color: AppTokens.gold.withValues(alpha: 0.55), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppTokens.teal.withValues(alpha: 0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Text(
          letter,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.42,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// Ink stage echoing Home / auth atmosphere — person first, brand quiet.
///
/// When [padTopSafeArea] is true, content sits below the status bar / notch
/// and an optional [leading] toolbar row (e.g. back) stays in the safe band.
class ProfileInkStage extends StatelessWidget {
  const ProfileInkStage({
    super.key,
    required this.user,
    this.onTap,
    this.actionLabel,
    this.compact = false,
    this.padTopSafeArea = false,
    this.leading,
  });

  final UserProfile? user;
  final VoidCallback? onTap;
  final String? actionLabel;
  final bool compact;
  final bool padTopSafeArea;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final name = user?.username.trim().isNotEmpty == true
        ? user!.username.trim()
        : '见音用户';
    final letter = user?.avatarLetter ?? '?';
    final phone = user?.maskedPhone ?? '—';
    final plan = user?.planLabel ?? '免费版';
    final greeting = '你好，$name';
    final topInset =
        padTopSafeArea ? MediaQuery.paddingOf(context).top : 0.0;

    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          greeting,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTokens.fgOnInk,
                fontSize: compact ? AppTokens.textXl : AppTokens.text2xl,
                height: 1.2,
              ),
        ),
        const SizedBox(height: AppTokens.space2),
        Text(
          phone,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTokens.fgOnInkMuted,
              ),
        ),
        const SizedBox(height: AppTokens.space3),
        _PlanChip(label: plan),
      ],
    );

    // Fixed square mark sized to the meta stack (greeting+phone+chip).
    // Do not use IntrinsicHeight/LayoutBuilder/AspectRatio here — they assert
    // under unbounded sliver constraints and white-screen the profile page.
    final markSize = compact ? 88.0 : 96.0;
    final identityRow = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ProfileIdentityMark(letter: letter, size: markSize),
        const SizedBox(width: AppTokens.space4),
        Expanded(child: meta),
      ],
    );

    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        identityRow,
        if (actionLabel != null) ...[
          const SizedBox(height: AppTokens.space5),
          Row(
            children: [
              Text(
                actionLabel!,
                style: const TextStyle(
                  color: AppTokens.statusIdle,
                  fontSize: AppTokens.textSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: AppTokens.statusIdle,
              ),
            ],
          ),
        ],
      ],
    );

    final bodyPad = Padding(
      padding: EdgeInsets.fromLTRB(
        AppTokens.space5,
        leading != null ? AppTokens.space3 : AppTokens.space5,
        AppTokens.space5,
        AppTokens.space5,
      ),
      child: onTap == null
          ? identity
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                child: identity,
              ),
            ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const RadialGradient(
          center: Alignment(0, -0.35),
          radius: 1.05,
          colors: [Color(0xFF1A2744), AppTokens.ink],
          stops: [0.0, 0.72],
        ),
        borderRadius: compact
            ? BorderRadius.circular(AppTokens.radiusXl)
            : const BorderRadius.vertical(
                bottom: Radius.circular(AppTokens.radiusXl),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: topInset),
          if (leading != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.space2,
                AppTokens.space2,
                AppTokens.space2,
                0,
              ),
              child: SizedBox(
                height: AppTokens.touchMin,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: leading!,
                ),
              ),
            ),
          bodyPad,
        ],
      ),
    );
  }
}

class _PlanChip extends StatelessWidget {
  const _PlanChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space3,
        vertical: AppTokens.space1,
      ),
      decoration: BoxDecoration(
        color: AppTokens.goldSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTokens.gold.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFE8C56A),
          fontSize: AppTokens.textXs,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ProfileSectionLabel extends StatelessWidget {
  const ProfileSectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: AppTokens.space2,
        bottom: AppTokens.space3,
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTokens.fgMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              fontSize: AppTokens.textSm,
            ),
      ),
    );
  }
}

/// Destination row for profile hub — outline icons, 48dp hit area.
class ProfileDestinationTile extends StatelessWidget {
  const ProfileDestinationTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.accent = false,
    this.danger = false,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool accent;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final iconFg = danger
        ? AppTokens.danger
        : accent
            ? const Color(0xFF92600A)
            : AppTokens.teal;
    final iconBg = danger
        ? const [
            Color(0xFFFFF1F2),
            Color(0xFFFEE2E2),
          ]
        : accent
            ? const [
                Color(0xFFFFF8E8),
                Color(0xFFF5E6C0),
              ]
            : const [
                Color(0xFFE6FFFA),
                Color(0xFFCCFBF1),
              ];
    final splash = danger
        ? AppTokens.danger.withValues(alpha: 0.08)
        : accent
            ? AppTokens.gold.withValues(alpha: 0.12)
            : AppTokens.teal.withValues(alpha: 0.1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: splash,
        highlightColor: splash.withValues(alpha: 0.06),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.space4,
              vertical: AppTokens.space3 + 2,
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: iconBg,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: iconFg.withValues(alpha: 0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(icon, size: 22, color: iconFg),
                ),
                const SizedBox(width: AppTokens.space3 + 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTokens.textBase,
                              height: 1.25,
                              color: danger ? AppTokens.danger : AppTokens.fg,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTokens.fgMuted,
                              fontSize: AppTokens.textSm,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppTokens.space2),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: danger
                        ? const Color(0xFFFEE2E2)
                        : accent
                            ? AppTokens.goldSoft
                            : AppTokens.muted,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: danger
                        ? AppTokens.danger.withValues(alpha: 0.7)
                        : accent
                            ? const Color(0xFF92600A)
                            : AppTokens.fgMuted,
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

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTokens.paperElevated,
        borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        border: Border.all(color: AppTokens.border.withValues(alpha: 0.65)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0B1220),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x060B1220),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                indent: 78,
                endIndent: AppTokens.space4,
                color: AppTokens.muted.withValues(alpha: 0.85),
              ),
          ],
        ],
      ),
    );
  }
}

class ProfileFactRow extends StatelessWidget {
  const ProfileFactRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTokens.space4,
        vertical: AppTokens.space4,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 76,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Teal segmented control for sex — clearer than default chips.
class ProfileSexSegment extends StatelessWidget {
  const ProfileSexSegment({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  static const options = [
    ('unknown', '保密'),
    ('male', '男'),
    ('female', '女'),
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '性别',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppTokens.muted,
          borderRadius: BorderRadius.circular(AppTokens.radiusField),
        ),
        child: Row(
          children: [
            for (final opt in options)
              Expanded(
                child: _Seg(
                  label: opt.$2,
                  selected: value == opt.$1,
                  enabled: enabled,
                  onTap: () => onChanged(opt.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.paperElevated : Colors.transparent,
      borderRadius: BorderRadius.circular(AppTokens.radiusField - 2),
      elevation: selected ? 1 : 0,
      shadowColor: const Color(0x140B1220),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTokens.radiusField - 2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppTokens.touchMin),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTokens.textSm,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? AppTokens.teal
                    : AppTokens.fgMuted.withValues(alpha: enabled ? 1 : 0.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
