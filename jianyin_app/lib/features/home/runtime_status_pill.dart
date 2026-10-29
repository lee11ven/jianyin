import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'sense_status.dart';

class RuntimeStatusPill extends StatefulWidget {
  const RuntimeStatusPill({super.key, required this.status});

  final SenseStatus status;

  @override
  State<RuntimeStatusPill> createState() => _RuntimeStatusPillState();
}

class _RuntimeStatusPillState extends State<RuntimeStatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant RuntimeStatusPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) _syncPulse();
  }

  void _syncPulse() {
    final active = widget.status == SenseStatus.recognizing ||
        widget.status == SenseStatus.translating;
    if (active) {
      _pulse.duration = widget.status == SenseStatus.translating
          ? const Duration(milliseconds: 900)
          : const Duration(milliseconds: 1100);
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Color get _dotColor {
    switch (widget.status) {
      case SenseStatus.offline:
        return AppTokens.statusOffline;
      case SenseStatus.idle:
        return AppTokens.statusIdle;
      case SenseStatus.recognizing:
        return AppTokens.statusRecognizing;
      case SenseStatus.translating:
        return AppTokens.statusTranslating;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = senseStates[widget.status]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _pulse.drive(Tween(begin: 0.35, end: 1)),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _dotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            meta.label,
            style: const TextStyle(
              color: AppTokens.fgOnInk,
              fontSize: AppTokens.textSm,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
