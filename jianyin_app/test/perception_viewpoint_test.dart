import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/body/body_types.dart';
import 'package:jianyin_app/envelope/csl_channels.dart';
import 'package:jianyin_app/envelope/landmark_point.dart';
import 'package:jianyin_app/perception/hint_keys.dart';
import 'package:jianyin_app/perception/viewpoint.dart';

BodyTickResult bodyWith({
  required double noseX,
  required double noseY,
  double shoulderLY = 0.42,
  double shoulderRY = 0.42,
  double shoulderLX = 0.38,
  double shoulderRX = 0.62,
}) {
  LandmarkPoint p(double x, double y) => LandmarkPoint(x: x, y: y, z: 0, v: 0.95);
  return BodyTickResult(
    body: BodyChannel(
      points: {
        'nose': p(noseX, noseY),
        'shoulderL': p(shoulderLX, shoulderLY),
        'shoulderR': p(shoulderRX, shoulderRY),
      },
      frame: BodyFrame(
        origin: p((shoulderLX + shoulderRX) / 2, (shoulderLY + shoulderRY) / 2),
        shoulderWidth: (shoulderRX - shoulderLX).abs(),
        right: p(1, 0),
        up: p(0, -1),
        zSign: 1,
      ),
    ),
  );
}

void main() {
  group('ViewpointEstimator', () {
    const estimator = ViewpointEstimator();

    test('缺 body → 不可用（按 N0/绿处理，不误报机位异常）', () {
      final estimate = estimator.estimate(const BodyTickResult());
      expect(estimate.className, ViewpointClass.n0);
      expect(estimate.band, ValveBand.green);
      expect(estimate.depthScore, 0);
      expect(estimate.biasScore, 0);
    });

    test('标准机位（头肩居中、头-肩距约一个肩宽）→ N0/绿', () {
      // 肩宽 0.24；鼻在肩中点上方 0.24 → verticalRatio = 1.0
      final estimate = estimator.estimate(bodyWith(noseX: 0.50, noseY: 0.18));
      expect(estimate.className, ViewpointClass.n0);
      expect(estimate.band, ValveBand.green);
      expect(estimate.depthScore, lessThanOrEqualTo(0.17));
      expect(estimate.biasScore, lessThanOrEqualTo(0.17));
      expect(estimate.rejectHands, isFalse);
      expect(estimate.sharpnessScale, 1.0);
    });

    test('纵向压缩（俯视）→ A1，且超出 hard → 红档拒发', () {
      // 头-肩距仅 0.02 → ratio≈0.08 → depthScore≈0.92 > 0.67(hard)
      final estimate = estimator.estimate(bodyWith(noseX: 0.50, noseY: 0.40));
      expect(estimate.className, ViewpointClass.a1);
      expect(estimate.band, ValveBand.red);
      expect(estimate.rejectHands, isTrue);
      expect(estimate.className.hintKey, HintKey.vpLessLeftDown);
    });

    test('纵向拉大（仰视）→ A5，黄档给加严系数', () {
      // 头-肩距 0.38 → ratio≈1.58 → depthScore≈0.58 ∈ (0.17, 0.67]
      final estimate = estimator.estimate(
        bodyWith(noseX: 0.50, noseY: 0.42 - 0.38),
      );
      expect(estimate.className, ViewpointClass.a5);
      expect(estimate.band, ValveBand.yellow);
      expect(estimate.sharpnessScale, greaterThan(1.0));
      expect(estimate.rejectHands, isFalse);
    });

    test('横向偏移主导 → A3/A4 或 A7/A8，且随偏向加深升档', () {
      final mild = estimator.estimate(bodyWith(noseX: 0.66, noseY: 0.18));
      expect(mild.className.isOblique || mild.className == ViewpointClass.a3, isTrue);
      expect(mild.band, isNot(ValveBand.green));

      final strong = estimator.estimate(bodyWith(noseX: 0.95, noseY: 0.18));
      expect(strong.band, ValveBand.red);
      expect(strong.className.isOblique || strong.className == ViewpointClass.a3, isTrue);
    });

    test('阀门可被覆盖（两套阀互不掩盖）', () {
      const soft = ViewpointEstimator(
        valves: ViewpointValves(depthSoft: 0.9, depthHard: 0.95),
      );
      final estimate = soft.estimate(bodyWith(noseX: 0.50, noseY: 0.40));
      expect(estimate.band, isNot(ValveBand.red));
    });
  });

  group('HintArbiter', () {
    test('按全序取唯一一条', () {
      final arbiter = HintArbiter();
      arbiter.arm(HintKey.showUpperBody, nowMs: 0);
      arbiter.arm(HintKey.holdSteady, nowMs: 0);
      expect(arbiter.winner(10), HintKey.holdSteady, reason: '抖动优先于取景');
      expect(hintPriority.indexOf(HintKey.holdSteady),
          lessThan(hintPriority.indexOf(HintKey.showUpperBody)));
    });

    test('TTL 到期自动失效', () {
      final arbiter = HintArbiter(defaultTtlMs: 500);
      arbiter.arm(HintKey.networkAudio, nowMs: 1000);
      expect(arbiter.winner(1200), HintKey.networkAudio);
      expect(arbiter.winner(1600), HintKey.none);
    });

    test('机位键优先于取景键；clear 后回落', () {
      final arbiter = HintArbiter();
      arbiter.arm(HintKey.showUpperBody, nowMs: 0);
      arbiter.arm(HintKey.vpRaiseOrFace, nowMs: 0);
      expect(arbiter.winner(0), HintKey.vpRaiseOrFace);
      arbiter.clear(HintKey.vpRaiseOrFace, nowMs: 0);
      expect(arbiter.winner(0), HintKey.showUpperBody);
    });

    test('18 个提示键全部有键名与文案', () {
      final keys = HintKey.values.where((k) => !k.isNone).toList();
      expect(keys.length, 18);
      for (final key in keys) {
        expect(key.code.startsWith('hint.'), isTrue, reason: '${key.name} 键名不合规');
        expect(key.copy.isNotEmpty, isTrue, reason: '${key.name} 缺文案');
        expect(hintPriority.contains(key), isTrue, reason: '${key.name} 未进全序');
      }
    });
  });
}