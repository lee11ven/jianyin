enum SenseStatus { offline, idle, recognizing, translating }

enum VoiceStatus { idle, speaking }

enum HintTone { none, muted, warn, danger }

class SenseMeta {
  const SenseMeta({
    required this.label,
    required this.hint,
    this.hintTone = HintTone.none,
  });

  final String label;
  final String hint;
  final HintTone hintTone;
}

const Map<SenseStatus, SenseMeta> senseStates = {
  SenseStatus.offline: SenseMeta(
    label: '掉线',
    hint: '连接已断开，正在重试…',
    hintTone: HintTone.muted,
  ),
  SenseStatus.idle: SenseMeta(
    label: '就绪',
    hint: '请正对镜头，露出上半身',
  ),
  SenseStatus.recognizing: SenseMeta(
    label: '识别中',
    hint: '正在捕捉手语…',
  ),
  SenseStatus.translating: SenseMeta(
    label: '转译中',
    hint: '正在生成语音文案…',
  ),
};
