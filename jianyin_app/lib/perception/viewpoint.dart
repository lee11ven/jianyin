import '../body/body_types.dart';
import 'hint_keys.dart';

/// 机位短名枚举（`viewpoint_class`）：N0 与 A1–A8。
///
/// 语义与命名以 docs/design/算法/客户端/index.md 为唯一事实来源：
/// N0 为标准机位；A1/A3/A5/A7 为正机位（主判深度角），A2/A4/A6/A8 为斜机位
/// （主判偏向角）。
enum ViewpointClass {
  n0('N0'),
  a1('A1'),
  a2('A2'),
  a3('A3'),
  a4('A4'),
  a5('A5'),
  a6('A6'),
  a7('A7'),
  a8('A8');

  const ViewpointClass(this.code);

  final String code;

  /// 正机位（四类，主判 depth 阀）。
  bool get isCardinal => this == a1 || this == a3 || this == a5 || this == a7;

  /// 斜机位（四类，主判 bias 阀）。
  bool get isOblique => this == a2 || this == a4 || this == a6 || this == a8;

  /// 对应的纠正提示键。
  HintKey get hintKey => switch (this) {
        ViewpointClass.a1 => HintKey.vpLessLeftDown,
        ViewpointClass.a2 => HintKey.vpLessRightDown,
        ViewpointClass.a3 => HintKey.vpFaceFromRight,
        ViewpointClass.a4 => HintKey.vpLessRightUp,
        ViewpointClass.a5 => HintKey.vpRaiseOrFace,
        ViewpointClass.a6 => HintKey.vpLessLeftUp,
        ViewpointClass.a7 => HintKey.vpFaceFromLeft,
        ViewpointClass.a8 => HintKey.vpLowerOrFace,
        ViewpointClass.n0 => HintKey.none,
      };
}

/// 三档：绿（通采）/ 黄（限采）/ 红（拒采）。
enum ValveBand { green, yellow, red }

/// 机位阀（4 个两位小数），冷启动加载，不热更新。
class ViewpointValves {
  const ViewpointValves({
    this.depthSoft = 0.17,
    this.depthHard = 0.67,
    this.biasSoft = 0.17,
    this.biasHard = 0.78,
  });

  final double depthSoft;
  final double depthHard;
  final double biasSoft;
  final double biasHard;

  static const defaults = ViewpointValves();

  ViewpointValves copyWith({
    double? depthSoft,
    double? depthHard,
    double? biasSoft,
    double? biasHard,
  }) {
    return ViewpointValves(
      depthSoft: depthSoft ?? this.depthSoft,
      depthHard: depthHard ?? this.depthHard,
      biasSoft: biasSoft ?? this.biasSoft,
      biasHard: biasHard ?? this.biasHard,
    );
  }
}

/// 一次机位估计结果。
class ViewpointEstimate {
  const ViewpointEstimate({
    required this.className,
    required this.band,
    required this.depthScore,
    required this.biasScore,
  });

  final ViewpointClass className;
  final ValveBand band;

  /// 0.00–1.00；0 表示贴近 N0。
  final double depthScore;
  final double biasScore;

  static const unavailable = ViewpointEstimate(
    className: ViewpointClass.n0,
    band: ValveBand.green,
    depthScore: 0,
    biasScore: 0,
  );

  /// 黄档质量加严系数（正机位 `S_min`×1.15；斜机位再 `A_min`×1.2）。
  double get sharpnessScale =>
      band == ValveBand.yellow ? (isCardinal ? 1.15 : 1.32) : 1.0;

  bool get isCardinal => className.isCardinal;

  /// 红档：不送手形、轨迹写 `gap`。
  bool get rejectHands => band == ValveBand.red;

  bool get writeGapWhenRejected => band == ValveBand.red;
}

/// 从图像线索估计机位档。
///
/// 说明（实现边界）：设计中的深度角/偏向角依赖机位外参（`O→C`），端侧只拿到
/// 单目图像，因此这里用**头肩几何代理**：头相对肩的垂直比例偏差作为
/// `depth_score`，头相对肩中点的水平偏移作为 `bias_score`。两者都按“归一化后
/// 0 贴近 N0、1 为极端”整理，再用 4 个两位小数阀门分绿/黄/红。接入手势原点
/// 三维几何（设备姿态）后，只需替换 [_scores] 的实现。
class ViewpointEstimator {
  const ViewpointEstimator({this.valves = ViewpointValves.defaults});

  final ViewpointValves valves;

  /// 从身体通道估计；缺锚点时返回 [ViewpointEstimate.unavailable]。
  ViewpointEstimate estimate(BodyTickResult body) {
    final channel = body.body;
    if (channel == null) return ViewpointEstimate.unavailable;
    final nose = channel.points['nose'];
    final shoulderL = channel.points['shoulderL'];
    final shoulderR = channel.points['shoulderR'];
    if (nose == null || shoulderL == null || shoulderR == null) {
      return ViewpointEstimate.unavailable;
    }

    final width = (shoulderR.x - shoulderL.x).abs();
    if (width < 0.02) return ViewpointEstimate.unavailable;

    final midX = (shoulderL.x + shoulderR.x) / 2;
    final midY = (shoulderL.y + shoulderR.y) / 2;

    // 正面标准机位时，头-肩垂直距离约为一个肩宽（比例 ≈1）。
    final verticalRatio = (midY - nose.y) / width;
    final depthScore = (1.0 - verticalRatio).abs().clamp(0.0, 1.0);
    final biasScore = ((nose.x - midX).abs() / width * 2).clamp(0.0, 1.0);

    final className = _classify(depthScore, biasScore, verticalRatio, nose.x - midX);
    final band = _bandFor(className, depthScore, biasScore);
    return ViewpointEstimate(
      className: className,
      band: band,
      depthScore: double.parse(depthScore.toStringAsFixed(2)),
      biasScore: double.parse(biasScore.toStringAsFixed(2)),
    );
  }

  ViewpointClass _classify(
    double depthScore,
    double biasScore,
    double verticalRatio,
    double horizontalOffset,
  ) {
    final depthGreen = depthScore <= valves.depthSoft;
    final biasGreen = biasScore <= valves.biasSoft;
    if (depthGreen && biasGreen) return ViewpointClass.n0;

    final horizontalDominant = biasScore > depthScore || depthGreen;
    final verticalDominant = !horizontalDominant;

    if (verticalDominant) {
      // 俯视（图像上头肩纵向间距被压缩，比例 < 1）→ A1；仰视 → A5。
      return verticalRatio < 1.0 ? ViewpointClass.a1 : ViewpointClass.a5;
    }
    // 横向偏：偏向程度决定正机位 / 斜机位（A3/A7 vs A4/A8）。
    final oblique = biasScore > valves.depthHard;
    if (horizontalOffset >= 0) {
      return oblique ? ViewpointClass.a4 : ViewpointClass.a3;
    }
    return oblique ? ViewpointClass.a8 : ViewpointClass.a7;
  }

  ValveBand _bandFor(
    ViewpointClass className,
    double depthScore,
    double biasScore,
  ) {
    if (className == ViewpointClass.n0) return ValveBand.green;
    // 6 类异常都有正/斜两套阀；用两套阀的**较宽**判定先判红，再判黄，
    // 保证任何一路进入硬档都不会被另一路的绿档掩盖。
    final score = className.isOblique ? biasScore : depthScore;
    final soft = className.isOblique ? valves.biasSoft : valves.depthSoft;
    final hard = className.isOblique ? valves.biasHard : valves.depthHard;
    if (score > hard) return ValveBand.red;
    if (score > soft) return ValveBand.yellow;
    // 主 score 在绿档但已归入异常（例如斜向过度、或另一路进入黄档）→ 黄档。
    final other = className.isOblique ? depthScore : biasScore;
    final otherSoft = className.isOblique ? valves.depthSoft : valves.biasSoft;
    return other > otherSoft ? ValveBand.yellow : ValveBand.green;
  }
}