import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 流式 PCM 播放器契约（对应 docs/design/算法/客户端/流式语音播放.md
/// 「PCM 流式播放器契约（设计级）」）。
///
/// 一期只走 `ws_binary_audio`：**PCM s16le / 16 kHz / mono**，边收边写，
/// 不落临时文件、不等整句。
abstract class PcmPlayer {
  /// 打开流式 sink；返回是否可用（不可用时调用方降级为“只计数不发声”）。
  Future<bool> open({required int sampleRate, required int channels});

  /// 追加 PCM 字节；应尽快返回。
  Future<void> write(Uint8List bytes);

  /// 原生缓冲中尚未播出的帧数（水位来源，可缺省为 0）。
  Future<int> bufferedFrames();

  /// 清空未播数据并停止（`Flushing` 必调）。
  Future<void> flush();

  /// 释放资源。
  Future<void> close();

  /// 每片音频的时长（ms），用于水位换算。
  int durationMsForBytes(int byteCount);
}

/// 原生播放桥：Android `AudioTrack(MODE_STREAM)` / iOS `AVAudioEngine`。
///
/// 与 `lib/native/` 的 MediaPipe 桥同构：薄 MethodChannel + 明确的字节契约。
/// 平台未实现（如 x86 模拟器、桌面）时自动降级为 [NoopPcmPlayer]。
class NativePcmPlayer implements PcmPlayer {
  NativePcmPlayer({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'jianyin/pcm_player';

  final MethodChannel _channel;
  int _sampleRate = 16000;
  int _channels = 1;
  bool _opened = false;
  PcmPlayer? _fallback;

  bool get usingFallback => _fallback != null;

  @override
  Future<bool> open({required int sampleRate, required int channels}) async {
    _sampleRate = sampleRate;
    _channels = channels;
    try {
      final ok = await _channel.invokeMethod<bool>('open', {
        'sampleRate': sampleRate,
        'channels': channels,
      });
      _opened = ok ?? false;
    } on MissingPluginException {
      _opened = false;
    } on PlatformException catch (e) {
      debugPrint('PCM open failed: ${e.message}');
      _opened = false;
    }
    if (!_opened) {
      final fallback = NoopPcmPlayer();
      await fallback.open(sampleRate: sampleRate, channels: channels);
      _fallback = fallback;
      return false;
    }
    return true;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    if (_fallback != null) return _fallback!.write(bytes);
    if (bytes.isEmpty || !_opened) return;
    await _channel.invokeMethod<void>('write', {'bytes': bytes});
  }

  @override
  Future<int> bufferedFrames() async {
    if (_fallback != null) return _fallback!.bufferedFrames();
    if (!_opened) return 0;
    try {
      return await _channel.invokeMethod<int>('bufferedFrames') ?? 0;
    } on MissingPluginException {
      return 0;
    } on PlatformException {
      return 0;
    }
  }

  @override
  Future<void> flush() async {
    if (_fallback != null) return _fallback!.flush();
    if (!_opened) return;
    try {
      await _channel.invokeMethod<void>('flush');
    } on MissingPluginException {
      /* 无原生实现：忽略 */
    } on PlatformException {
      /* 忽略，Flushing 不应阻断会话拆除 */
    }
  }

  @override
  Future<void> close() async {
    if (_fallback != null) {
      await _fallback!.close();
      _fallback = null;
      return;
    }
    if (!_opened) return;
    _opened = false;
    try {
      await _channel.invokeMethod<void>('close');
    } on MissingPluginException {
      /* 无原生实现：忽略 */
    } on PlatformException {
      /* 忽略 */
    }
  }

  @override
  int durationMsForBytes(int byteCount) =>
      byteCount * 1000 ~/ (_sampleRate * _channels * 2);
}

/// 无原生音频时的降级播放器：只按写入量维护水位，不发声。
///
/// 用途（与 MediaPipe 在 x86 模拟器上缺失时的处理一致）：
/// 1. 让状态机、抖动缓冲与 UI 在不可发声环境下仍可验证；
/// 2. 桌面/模拟器联调不因缺少原生实现而中断整条链路。
class NoopPcmPlayer implements PcmPlayer {
  NoopPcmPlayer({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  int _sampleRate = 16000;
  int _channels = 1;
  double _bufferedMs = 0;
  DateTime? _lastTick;

  @override
  Future<bool> open({required int sampleRate, required int channels}) async {
    _sampleRate = sampleRate;
    _channels = channels;
    _lastTick = _clock();
    return false;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _drain();
    _bufferedMs += durationMsForBytes(bytes.length);
  }

  @override
  Future<int> bufferedFrames() async {
    _drain();
    final frames = (_bufferedMs / 1000 * _sampleRate).round();
    return frames < 0 ? 0 : frames;
  }

  @override
  Future<void> flush() async {
    _bufferedMs = 0;
    _lastTick = _clock();
  }

  @override
  Future<void> close() async {
    _bufferedMs = 0;
    _lastTick = null;
  }

  @override
  int durationMsForBytes(int byteCount) =>
      byteCount * 1000 ~/ (_sampleRate * _channels * 2);

  void _drain() {
    final now = _clock();
    final last = _lastTick;
    if (last == null) {
      _lastTick = now;
      return;
    }
    final elapsed = now.difference(last).inMicroseconds / 1000.0;
    _lastTick = now;
    _bufferedMs -= elapsed;
    if (_bufferedMs < 0) _bufferedMs = 0;
  }
}