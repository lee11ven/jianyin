/// 抖动缓冲水位状态机（纯 Dart，可单测）。
///
/// 口径来自 docs/design/算法/客户端/流式语音播放.md：
/// - `T_prime`（默认 100 ms）：开声前需要的水位；
/// - `T_target`（120 ms）：稳态目标水位；
/// - `T_low`（40 ms）：欠载线；
/// - `T_underrun_wait`（60 ms）：欠载等待上限；
/// - `N_underrun_hint`（默认 3 次 / 2 s）：触发弱网提示。
///
/// 水位由原生缓冲回传（`bufferedFrames`）换算而来；本类不持有音频数据。
class JitterBuffer {
  JitterBuffer({
    this.primeMs = 100,
    this.targetMs = 120,
    this.lowMs = 40,
    this.underrunWaitMs = 60,
    this.underrunHintCount = 3,
    this.underrunHintWindowMs = 2000,
    this.sampleRate = 16000,
  }) : assert(lowMs < primeMs && primeMs <= targetMs, '须保持 T_low < T_prime ≤ T_target');

  final int primeMs;
  final int targetMs;
  final int lowMs;
  final int underrunWaitMs;
  final int underrunHintCount;
  final int underrunHintWindowMs;
  final int sampleRate;

  PlaybackState _state = PlaybackState.idle;
  int _bufferedMs = 0;
  int? _lowSinceMs;
  final List<int> _underrunAt = <int>[];
  bool hintNetworkAudio = false;

  PlaybackState get state => _state;
  int get bufferedMs => _bufferedMs;
  int get underrunCount => _underrunAt.length;

  /// 一次句首片入队：进入 `priming`。
  void onUtteranceStart() {
    if (_state == PlaybackState.idle || _state == PlaybackState.underrun) {
      _state = PlaybackState.priming;
    }
  }

  /// 原生水位更新（按帧数），驱动状态迁移。返回本次是否发生了状态变化。
  bool onBufferedFrames(int frames, int nowMs) {
    _bufferedMs = (frames * 1000 / sampleRate).round();
    final previous = _state;

    switch (_state) {
      case PlaybackState.idle:
      case PlaybackState.flushing:
        break;
      case PlaybackState.priming:
        if (_bufferedMs >= primeMs) {
          _state = PlaybackState.playing;
          _lowSinceMs = null;
        }
        break;
      case PlaybackState.playing:
        if (_bufferedMs <= lowMs) {
          _lowSinceMs ??= nowMs;
          final waited = nowMs - _lowSinceMs!;
          if (waited >= underrunWaitMs) {
            _state = PlaybackState.underrun;
            _recordUnderrun(nowMs);
            _lowSinceMs = null;
          }
        } else {
          _lowSinceMs = null;
        }
        break;
      case PlaybackState.underrun:
        if (_bufferedMs > lowMs) {
          _state = PlaybackState.playing;
        }
        break;
    }
    return previous != _state;
  }

  /// 一句播完（队首句末片且水位见底）：允许回到 `idle`。
  void onUtteranceEnd(int nowMs) {
    if (_state == PlaybackState.playing || _state == PlaybackState.priming) {
      _state = PlaybackState.idle;
      _lowSinceMs = null;
    }
    if (_state == PlaybackState.underrun && _bufferedMs == 0) {
      _state = PlaybackState.idle;
    }
  }

  /// 会话结束 / 重连 / 离开 Home：进入 `flushing`，调用方随后 [completeFlush]。
  void beginFlush() {
    _state = PlaybackState.flushing;
    _lowSinceMs = null;
  }

  /// `Flushing` 完成：回到 `idle`、清空水位与提示。
  void completeFlush() {
    _state = PlaybackState.idle;
    _bufferedMs = 0;
    _lowSinceMs = null;
    _underrunAt.clear();
    hintNetworkAudio = false;
  }

  void _recordUnderrun(int nowMs) {
    _underrunAt.add(nowMs);
    _underrunAt.removeWhere((ts) => nowMs - ts > underrunHintWindowMs);
    if (_underrunAt.length >= underrunHintCount) hintNetworkAudio = true;
  }
}

enum PlaybackState {
  /// 队列空，待命。
  idle,

  /// 首片已到，等 `T_prime` 水位。
  priming,

  /// 正在出声。
  playing,

  /// 句中缓冲排空，跳缺口继续。
  underrun,

  /// 会话结束 / 致命错误，清空队列。
  flushing,
}