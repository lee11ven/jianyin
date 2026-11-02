import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/camera/frame_sampler.dart';
import 'package:jianyin_app/config/perception_thresholds.dart';

FrameSamplerCore coreWith({
  double tOnset = 12,
  double jLight = 1.8,
  double jHeavy = 3.0,
  int quietMs = 800,
  int idleMs = 120,
  int activeMs = 40,
  double sMin = 80,
  int peakHoldMs = 60,
}) {
  return FrameSamplerCore(
    thresholds: PerceptionThresholds(
      tOnset: tOnset,
      tQuietMs: quietMs,
      deltaIdleMs: idleMs,
      deltaActiveMs: activeMs,
      sMin: sMin,
      jLightFactor: jLight,
      jHeavyFactor: jHeavy,
      peakHoldMinIntervalMs: peakHoldMs,
    ),
  );
}

void main() {
  group('FrameSamplerCore 四态机', () {
    test('Idle：低采样探测拍只做存在性检查', () {
      final core = coreWith();
      final d = core.onMetrics(
        motionEnergy: 0,
        sharpness: 200,
        now: DateTime(2026, 1, 1, 0, 0, 0),
      );
      expect(d.phase, FrameSamplerPhase.idle);
      expect(d.tick, isTrue, reason: 'Idle 探测拍也放行（presence）');
      expect(d.presenceOnly, isTrue);
      expect(d.omitHands, isTrue);
      expect(d.forcePathGap, isTrue);
    });

    test('连续运动升 Active；静默回 Idle', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );
      expect(core.phase, FrameSamplerPhase.active);

      final d = core.onMetrics(
        motionEnergy: 0,
        sharpness: 200,
        now: t0.add(const Duration(seconds: 2)),
      );
      expect(d.phase, FrameSamplerPhase.idle);
      expect(d.presenceOnly, isTrue);
    });

    test('节流：Active 内小于 deltaActiveMs 的帧不放行，但峰值可 PeakHold', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );

      // 10 ms 后：既有运动又在节流窗内，但能量是新峰值（轻抖、非重抖）→ PeakHold 放行
      final peak = core.onMetrics(
        motionEnergy: 26,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 210)),
      );
      expect(peak.peakHold, isTrue);
      expect(peak.tick, isTrue);
      expect(peak.phase, FrameSamplerPhase.peakHold);

      // 非峰值且节流内 → 不放行
      final skipped = core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 220)),
      );
      expect(skipped.tick, isFalse);
    });

    test('清晰度低于 S_min → 本拍不带手形（omitHands）', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );
      final d = core.onMetrics(
        motionEnergy: 20,
        sharpness: 10,
        now: t0.add(const Duration(milliseconds: 300)),
      );
      expect(d.omitHands, isTrue);
      expect(d.forcePathGap, isFalse);
    });

    test('黄档加严：qualityScale 抬升后原本放行的清晰度会被拒', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );
      core.viewpointQualityScale = 1.32;
      final d = core.onMetrics(
        motionEnergy: 20,
        sharpness: 90,
        now: t0.add(const Duration(milliseconds: 300)),
      );
      expect(d.omitHands, isTrue, reason: '90 < 80 × 1.32');
    });
  });

  group('抖动分档与 Reject', () {
    test('按 tOnset 倍数分档：稳 / 轻抖 / 重抖', () {
      final core = coreWith();
      expect(core.tierFor(10), ShakeTier.stable);
      expect(core.tierFor(30), ShakeTier.light);
      expect(core.tierFor(40), ShakeTier.heavy);
    });

    test('重抖 → Reject：不送手形 + 轨迹写 gap', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      final d = core.onMetrics(
        motionEnergy: 60,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );
      expect(d.shakeTier, ShakeTier.heavy);
      expect(d.rejected, isTrue);
      expect(d.phase, FrameSamplerPhase.reject);
      expect(d.omitHands, isTrue);
      expect(d.forcePathGap, isTrue);
    });

    test('红档机位（viewpointRejects）→ Reject：不改抖动档', () {
      final core = coreWith();
      final t0 = DateTime(2026, 1, 1);
      core.onMetrics(motionEnergy: 20, sharpness: 200, now: t0);
      core.viewpointRejects = true;
      final d = core.onMetrics(
        motionEnergy: 20,
        sharpness: 200,
        now: t0.add(const Duration(milliseconds: 200)),
      );
      expect(d.rejected, isTrue);
      expect(d.shakeTier, ShakeTier.stable);
      expect(d.forcePathGap, isTrue);
    });

    test('reset 清空全部状态', () {
      final core = coreWith();
      core.onMetrics(
        motionEnergy: 40,
        sharpness: 200,
        now: DateTime(2026, 1, 1),
      );
      core.viewpointQualityScale = 1.2;
      core.viewpointRejects = true;
      core.reset();
      expect(core.phase, FrameSamplerPhase.idle);
      expect(core.shakeTier, ShakeTier.stable);
      expect(core.viewpointQualityScale, 1.0);
      expect(core.viewpointRejects, isFalse);
    });
  });
}