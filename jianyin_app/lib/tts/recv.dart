import '../ws/ws_events.dart';

/// 下行音频的**接收侧校验**（ws/ 只做帧路由，格式语义归 tts/）。
///
/// 一期正式路径只有 `ws_binary_audio` + PCM s16le / 16 kHz / mono：
/// 其它 `delivery`、非 PCM 编码或采样率/channels 不符的句一律拒收，不入队。
class PcmFormat {
  const PcmFormat({
    this.mimeType = 'audio/pcm',
    this.encoding = 's16le',
    this.sampleRate = 16000,
    this.channels = 1,
  });

  final String mimeType;
  final String encoding;
  final int sampleRate;
  final int channels;

  static const defaults = PcmFormat();

  bool matchesHeader(WsAudioHeader header) {
    return header.mimeType == mimeType &&
        header.encoding == encoding &&
        header.sampleRate == sampleRate &&
        header.channels == channels;
  }
}

/// 拒收原因（映射到 UX 提示键）。
enum AudioRejection {
  /// `speech.delivery` 不是 `ws_binary_audio`（含 `inline_fallback` / `audioBase64`）。
  unsupportedDelivery,

  /// `audio.header` 与本期锁定的 PCM 格式不一致。
  unsupportedFormat,

  /// 片所属的句未声明（无对应 `speech`），或会话不符。
  unknownUtterance,
}

/// 校验 `speech` 元数据。
AudioRejection? validateSpeech(WsSpeechMeta meta, {String? sessionId}) {
  if (sessionId != null && meta.sessionId.isNotEmpty && meta.sessionId != sessionId) {
    return AudioRejection.unknownUtterance;
  }
  if (!meta.accepted) return AudioRejection.unsupportedDelivery;
  if (meta.utteranceId.isEmpty) return AudioRejection.unknownUtterance;
  return null;
}

/// 校验 `audio.header`。
AudioRejection? validateHeader(WsAudioHeader header, {String? sessionId}) {
  if (sessionId != null && header.sessionId.isNotEmpty && header.sessionId != sessionId) {
    return AudioRejection.unknownUtterance;
  }
  if (header.utteranceId.isEmpty) return AudioRejection.unknownUtterance;
  if (!PcmFormat.defaults.matchesHeader(header)) {
    return AudioRejection.unsupportedFormat;
  }
  if (header.seq < 0) return AudioRejection.unsupportedFormat;
  return null;
}