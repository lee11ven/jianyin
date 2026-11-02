import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/camera/frame_sampler.dart';
import 'package:jianyin_app/config/perception_thresholds.dart';
import 'package:jianyin_app/tts/jitter_buffer.dart';

/// 端侧指标 harness（**离线合成序列**，非真机采集）。
///
/// 模型（与设计口径一致）：
/// - 音频：每片 100 ms；正常网络下到货节奏 ≈ 实时；首片有网络/首字节时延（建模 30 ms），
///   第二片提前到位（合成侧产出快于实时）→ 缓冲跨过 `T_prime` 即开声。
/// - 抖动场景：偶发 60 ms 到货抖动，用于欠载率口径。
/// - 停顿场景：一次 400 ms 停发，用于「弱网可恢复」口径。
/// - 抽帧：25 Hz 合成帧，每 250 ms 一段持续运动，段中间一帧为动作峰值。
///
/// 复现：`cd jianyin_app && flutter test test/metrics_harness_test.dart`
/// 门限与真机复测步骤见 `docs/reports/metrics.md`、`docs/reports/device-acceptance.md`。
void main() {
  const framesPerMs = 16; // 16 kHz → 16 帧/ms，16 kHz/s ÷ 1000
  const chunkMs = 100;
  const stepMs = 10;

  /// 按到货时刻表模拟一次播放。
  ({int openMs, int underrunMs, int windowMs, int underrunCount, int recoveredMs})
      simulate(List<int> arrivals) {
    final jitter = JitterBuffer();
    jitter.onUtteranceStart();
    var arrivedMs = 0;
    var playedMs = 0;
    var openMs = -1;
    var underrunMs = 0;
    var windowMs = 0;
    var recoveredMs = -1;
    var stallStart = -1;
    final schedule = arrivals.toSet();
    for (var t = 0; t <= 3000; t += stepMs) {
      if (schedule.contains(t)) arrivedMs += chunkMs;
      final buffered = max(0, arrivedMs - playedMs);
      jitter.onBufferedFrames(buffered * framesPerMs, t);
      if (openMs < 0 && jitter.state == PlaybackState.playing) openMs = t;
      if (openMs >= 0) {
        windowMs += stepMs;
        if (jitter.state == PlaybackState.underrun) {
          underrunMs += stepMs;
          if (stallStart < 0) stallStart = t;
        } else if (stallStart >= 0 && recoveredMs < 0) {
          recoveredMs = t - stallStart;
        }
      }
      playedMs = min(arrivedMs, playedMs + stepMs);
    }
    return (
      openMs: openMs,
      underrunMs: underrunMs,
      windowMs: windowMs,
      underrunCount: jitter.underrunCount,
      recoveredMs: recoveredMs,
    );
  }

  test('harness', () {
    final metrics = <String, Object>{};

    // ── 1. 正常网络：开声缓冲时延 ────────────────────────────────────
    final normal = <int>[30, 60];
    for (var t = 160; t <= 3000; t += 100) {
      normal.add(t);
    }
    final open = simulate(normal);
    metrics['openBufferLatencyMs'] = open.openMs;
    metrics['openBufferLatencyTargetMs'] = 100;

    // ── 2. 抖动网络：欠载率（目标 ≤ 2%） ─────────────────────────────
    final jittery = <int>[30, 60];
    for (var t = 160; t <= 3000; t += 100) {
      // 每 5 片插入一次 60 ms 到货抖动
      jittery.add(((t - 160) / 100) % 5 == 3 ? t + 60 : t);
    }
    final jitterRun = simulate(jittery);
    metrics['underrunMs'] = jitterRun.underrunMs;
    metrics['underrunWindowMs'] = jitterRun.windowMs;
    metrics['underrunRate'] =
        jitterRun.windowMs == 0 ? 0 : jitterRun.underrunMs / jitterRun.windowMs;
    metrics['underrunCount'] = jitterRun.underrunCount;

    // ── 3. 弱网停顿 400 ms：可恢复性 ────────────────────────────────
    final stalled = <int>[30, 60];
    for (var t = 160; t < 600; t += 100) {
      stalled.add(t);
    }
    for (var t = 1000; t <= 3000; t += 100) {
      stalled.add(t);
    }
    final stallRun = simulate(stalled);
    metrics['stallMs'] = 400;
    metrics['underrunRecoveredMs'] = stallRun.recoveredMs;

    // ── 4. 漏帧率：活动段内「动作峰值帧」未被放行的比例 ────────────
    final core = FrameSamplerCore(thresholds: const PerceptionThresholds());
    final clock = DateTime(2026, 1, 1);
    const thresholds = PerceptionThresholds();
    var peaks = 0;
    var peaksMissed = 0;
    for (var i = 0; i < 75; i++) {
      final inBurst = (i % 6) >= 1 && (i % 6) <= 5;
      final isPeak = i % 6 == 3;
      final energy = !inBurst
          ? 0.0
          : isPeak
              ? thresholds.tOnset * 2
              : thresholds.tOnset * 1.2;
      final decision = core.onMetrics(
        motionEnergy: energy,
        sharpness: 200,
        now: clock.add(Duration(milliseconds: i * 40)),
      );
      if (isPeak) {
        peaks += 1;
        if (!decision.tick || decision.omitHands) peaksMissed += 1;
      }
    }
    metrics['peakFrames'] = peaks;
    metrics['peakFramesMissed'] = peaksMissed;
    metrics['peakMissRate'] = peaks == 0 ? 0 : peaksMissed / peaks;

    // ── 5. 抖动分档：重抖拒发（安全性）、轻抖放行 ──────────────────
    final heavyCore = FrameSamplerCore(thresholds: thresholds);
    heavyCore.onMetrics(motionEnergy: thresholds.tOnset * 1.2, sharpness: 200, now: clock);
    final heavy = heavyCore.onMetrics(
      motionEnergy: thresholds.tOnset * 5,
      sharpness: 200,
      now: clock.add(const Duration(milliseconds: 200)),
    );
    final lightCore = FrameSamplerCore(thresholds: thresholds);
    lightCore.onMetrics(motionEnergy: thresholds.tOnset * 1.2, sharpness: 200, now: clock);
    final light = lightCore.onMetrics(
      motionEnergy: thresholds.tOnset * 2,
      sharpness: 200,
      now: clock.add(const Duration(milliseconds: 200)),
    );
    metrics['heavyShakeRejected'] = heavy.rejected;
    metrics['lightShakePassed'] = light.tick && !light.rejected;
    metrics['lightShakeTier'] = light.shakeTier.name;

    stdout.writeln('--- metrics (offline harness) ---');
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(metrics));

    // 目标断言（与 docs/reports/metrics.md 的门限一致）
    expect(open.openMs, lessThanOrEqualTo(metrics['openBufferLatencyTargetMs'] as int));
    expect(metrics['underrunRate'] as double, lessThanOrEqualTo(0.02));
    expect(metrics['peakMissRate'] as double, lessThanOrEqualTo(0.03));
    expect(metrics['underrunRecoveredMs'] as int, greaterThan(0));
    expect(heavy.rejected, isTrue);
    expect(light.tick && !light.rejected, isTrue);
  });
}