import '../features/home/sense_status.dart' show HintTone;

/// UX 提示键（18 个，与 docs/design/客户端APP/risks.md 的提示键列表一一对应）。
///
/// `code` 与文档中的 `hint.*` 字面一致，便于日志与验收抽查；文案与语气同屏
/// 只展一条，全序由 [hintPriority] 决定。
enum HintKey {
  none('', '', HintTone.none),

  // 连接 / 音频类
  deviceBusy('hint.device_busy', '边缘设备忙，请稍后重试', HintTone.warn),
  audioFormatError('hint.audio_format_error', '音频格式不支持，已跳过该句', HintTone.danger),
  networkAudio('hint.network_audio', '网络不稳，语音可能断续', HintTone.warn),
  audioDropped('hint.audio_dropped', '网络不稳，已丢弃部分未播语音', HintTone.warn),

  // 采集质量类
  holdSteady('hint.hold_steady', '手机晃动明显，请持稳', HintTone.warn),
  faceCamera('hint.face_camera', '请正对摄像头', HintTone.warn),

  // 机位纠正类（A1–A8）
  vpLessLeftDown('hint.vp.less_left_down', '机位偏左上，请略向左下调整', HintTone.warn),
  vpLessLeftUp('hint.vp.less_left_up', '机位偏左下，请略向左上调整', HintTone.warn),
  vpLessRightDown('hint.vp.less_right_down', '机位偏右上，请略向右下调整', HintTone.warn),
  vpLessRightUp('hint.vp.less_right_up', '机位偏右下，请略向右上调整', HintTone.warn),
  vpFaceFromLeft('hint.vp.face_from_left', '机位偏左，请从左侧正对镜头', HintTone.warn),
  vpFaceFromRight('hint.vp.face_from_right', '机位偏右，请从右侧正对镜头', HintTone.warn),
  vpLowerOrFace('hint.vp.lower_or_face', '机位偏高，请放低手机或正对', HintTone.warn),
  vpRaiseOrFace('hint.vp.raise_or_face', '机位偏低，请抬高手机或正对', HintTone.warn),

  // 取景类
  showUpperBody('hint.show_upper_body', '请露出上半身与双手', HintTone.warn),
  occlusionOrFrame('hint.occlusion_or_frame', '双手交叉或遮挡，请调整取景', HintTone.warn),
  comeCloser('hint.come_closer', '请靠近镜头一些', HintTone.warn),
  backgroundOrLight('hint.background_or_light', '背景杂乱或光线不足，请调整', HintTone.warn);

  const HintKey(this.code, this.copy, this.tone);

  /// 与文档一致的键名。
  final String code;

  /// 同屏一句话的中文文案。
  final String copy;

  final HintTone tone;

  bool get isNone => this == HintKey.none;
}

/// 同屏只展一条的**全序**（越靠前越优先）。
///
/// 顺序与 docs/design/客户端APP/risks.md 的失败场景表一致：连接/音频类故障优先，
/// 其次采集质量，再次机位纠正与取景。
const List<HintKey> hintPriority = <HintKey>[
  HintKey.deviceBusy,
  HintKey.audioFormatError,
  HintKey.networkAudio,
  HintKey.audioDropped,
  HintKey.holdSteady,
  HintKey.faceCamera,
  HintKey.vpFaceFromLeft,
  HintKey.vpFaceFromRight,
  HintKey.vpLowerOrFace,
  HintKey.vpRaiseOrFace,
  HintKey.vpLessLeftDown,
  HintKey.vpLessLeftUp,
  HintKey.vpLessRightDown,
  HintKey.vpLessRightUp,
  HintKey.showUpperBody,
  HintKey.occlusionOrFrame,
  HintKey.comeCloser,
  HintKey.backgroundOrLight,
];

/// 同屏提示仲裁：按 [hintPriority] 选出唯一一条，带防抖 TTL。
///
/// 触发方（抽帧 / 骨架 / 会话层）只 `arm`；UI 只读 [winner]。
class HintArbiter {
  HintArbiter({this.defaultTtlMs = 600});

  /// 未显式指定时的存活时长（防抖：避免同一提示反复闪烁）。
  final int defaultTtlMs;

  final Map<HintKey, int> _expiry = <HintKey, int>{};

  /// 亮起一条提示，`ttlMs` 后自动失效。
  void arm(HintKey key, {required int nowMs, int? ttlMs}) {
    if (key.isNone) return;
    _expiry[key] = nowMs + (ttlMs ?? defaultTtlMs);
  }

  void clear(HintKey key, {int? nowMs}) {
    _expiry.remove(key);
    if (nowMs != null) prune(nowMs);
  }

  void clearAll() => _expiry.clear();

  /// 当前应展示的提示（无则 [HintKey.none]）。
  HintKey winner(int nowMs) {
    prune(nowMs);
    for (final key in hintPriority) {
      if (_expiry.containsKey(key)) return key;
    }
    return HintKey.none;
  }

  /// 清掉已过期的项。
  void prune(int nowMs) {
    _expiry.removeWhere((_, expiry) => expiry <= nowMs);
  }

  int get armedCount => _expiry.length;
}