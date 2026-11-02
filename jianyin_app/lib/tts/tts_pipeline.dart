import 'package:flutter/foundation.dart';

import '../ws/ws_events.dart';
import 'jitter_buffer.dart';
import 'pcm_player.dart';
import 'recv.dart';
import 'utterance_assembler.dart';

/// 流式播音管线门面：`Recv → Assembler → JitterBuffer → Player`。
///
/// 与设计一致的行为：
/// - 只接受 `ws_binary_audio` + PCM s16le / 16 kHz / mono；
/// - 按 `utteranceId` FIFO 串行，不 barge-in（上一句播完才开下一句）；
/// - 边收边播（不落临时文件、不等整句）；
/// - `Flushing`（离开 Home / 会话被替换 / 重连）清空队列并重置水位。
///
/// 依赖全部可注入（播放器 / 抖动缓冲 / 组装器），便于单测与降级。
class TtsPipeline {
  TtsPipeline({
    PcmPlayer? player,
    JitterBuffer? jitter,
    UtteranceAssembler? assembler,
    int Function()? now,
  })  : _player = player ?? NativePcmPlayer(),
        jitter = jitter ?? JitterBuffer(),
        assembler = assembler ?? UtteranceAssembler(),
        _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final PcmPlayer _player;
  final JitterBuffer jitter;
  final UtteranceAssembler assembler;
  final int Function() _now;

  bool _opened = false;
  String? _currentUtterance;
  WsAudioHeader? _pendingHeader;

  /// 已拒收的句（`speech` 元数据不合法）：其后续片一律不入队。
  final Set<String> _rejectedUtterances = <String>{};

  /// 统计：已写入播放器的片数与字节数（验收与联调用）。
  int writtenChunks = 0;
  int writtenBytes = 0;

  /// 最近一次拒收原因（UI 映射到 `hint.audio_format_error`）。
  AudioRejection? lastRejection;

  /// 当前播放状态（UI 播报指示）。
  PlaybackState get state => jitter.state;

  /// 需要弱网提示（`hint.network_audio`）时为 true。
  bool get networkHint => jitter.hintNetworkAudio;

  /// 有未播完的句或片时为 true。
  bool get hasPendingAudio => assembler.depth > 0;

  /// 打开原生播放 sink（进入 Home 时调用一次；失败降级为 Noop，不阻断链路）。
  Future<bool> ensureOpen({int sampleRate = 16000, int channels = 1}) async {
    if (_opened) return true;
    _opened = await _player.open(sampleRate: sampleRate, channels: channels);
    return _opened;
  }

  /// 收到 `speech` 元数据。
  void onSpeech(WsSpeechMeta meta, {String? sessionId}) {
    final rejection = validateSpeech(meta, sessionId: sessionId);
    if (rejection != null) {
      lastRejection = rejection;
      // 拒收整句：其后的 audio.header / Binary 一律不入队（含 inline_fallback）。
      _rejectedUtterances.add(meta.utteranceId);
      debugPrint('[tts] reject speech ${meta.utteranceId}: ${rejection.name}');
      return;
    }
    lastRejection = null;
    _rejectedUtterances.remove(meta.utteranceId);
    assembler.declare(meta.utteranceId, text: meta.text);
  }

  /// 收到 `audio.header`：校验并记住，等紧随的二进制配对。
  void onHeader(WsAudioHeader header, {String? sessionId}) {
    final rejection = validateHeader(header, sessionId: sessionId);
    if (rejection != null) {
      lastRejection = rejection;
      debugPrint(
        '[tts] reject header ${header.utteranceId}#${header.seq}: ${rejection.name}',
      );
      return;
    }
    if (_rejectedUtterances.contains(header.utteranceId)) {
      lastRejection = AudioRejection.unsupportedDelivery;
      return;
    }
    lastRejection = null;
    _pendingHeader = header;
    // 目录项可能因丢包缺失；缺声明时按 header 兜底声明（幂等）。
    assembler.declare(header.utteranceId);
  }

  /// 收到二进制音频帧：与 `audio.header` 配对后交组装器与播放器。
  Future<void> onBinary(List<int> bytes, {WsAudioHeader? header}) async {
    final effective = header ?? _pendingHeader;
    _pendingHeader = null;
    if (effective == null) {
      lastRejection = AudioRejection.unknownUtterance;
      debugPrint('[tts] binary without header, dropped ${bytes.length} bytes');
      return;
    }
    final rejection = validateHeader(effective);
    if (rejection != null) {
      lastRejection = rejection;
      return;
    }
    if (_rejectedUtterances.contains(effective.utteranceId)) {
      lastRejection = AudioRejection.unsupportedDelivery;
      return;
    }
    assembler.declare(effective.utteranceId);
    assembler.addChunk(
      effective.utteranceId,
      effective.seq,
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
      last: effective.last,
    );
    await _pump();
  }

  /// 把可播片按 `utteranceId` 串行写入播放器，并刷新水位。
  Future<void> _pump() async {
    await ensureOpen();
    var chunk = assembler.nextChunk();
    while (chunk != null) {
      if (_currentUtterance != chunk.utteranceId) {
        _currentUtterance = chunk.utteranceId;
        jitter.onUtteranceStart();
      }
      await _player.write(chunk.bytes);
      writtenChunks += 1;
      writtenBytes += chunk.bytes.length;

      final frames = await _player.bufferedFrames();
      jitter.onBufferedFrames(frames, _now());

      if (chunk.last) {
        jitter.onUtteranceEnd(_now());
        _currentUtterance = null;
      }
      chunk = assembler.nextChunk();
    }
  }

  /// 原生水位刷新（无新片时也可调用，用于欠载判定与 UI 状态）。
  Future<void> refreshWaterLevel() async {
    if (!_opened) return;
    final frames = await _player.bufferedFrames();
    jitter.onBufferedFrames(frames, _now());
  }

  /// `Flushing`：清空队列、丢弃未播数据、回到 idle。
  Future<void> flush() async {
    jitter.beginFlush();
    assembler.flush();
    _pendingHeader = null;
    _currentUtterance = null;
    _rejectedUtterances.clear();
    lastRejection = null;
    await _player.flush();
    jitter.completeFlush();
  }

  /// 释放播放器（离开 Home / dispose）。
  Future<void> close() async {
    await flush();
    await _player.close();
    _opened = false;
  }
}