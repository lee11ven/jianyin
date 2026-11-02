import 'dart:collection';
import 'dart:typed_data';

/// 一句的组装状态。
class _Utterance {
  _Utterance({required this.utteranceId, required this.text});

  final String utteranceId;
  final String text;

  /// 已交付给播放器的下一个 seq。
  int deliveredUpTo = -1;

  /// 已收到的片（乱序容忍）。
  final SplayTreeMap<int, Uint8List> pending = SplayTreeMap<int, Uint8List>();

  bool ended = false;
  int? lastSeq;

  /// 本句因缺口跳过的片数。
  int skipped = 0;
}

/// 按 `utteranceId` 的 FIFO 句队列 + 片有序缓冲。
///
/// 规则（docs/design/算法/客户端/流式语音播放.md）：
/// - 严格按 `utteranceId` 串行：队首句未播完，不出下一句；
/// - 乱序/缺片：重排窗 `W_reorder`（seq 数）取严，超过则跳过缺口继续；
/// - 未开播句深度超过 `N_queue_max` 时丢最旧未开播句。
class UtteranceAssembler {
  UtteranceAssembler({this.maxQueue = 3, this.reorderWindow = 4});

  /// 未开播句上限（`N_queue_max`）。
  final int maxQueue;

  /// 重排窗（seq 数，`W_reorder`）。
  final int reorderWindow;

  final List<_Utterance> _queue = <_Utterance>[];
  final Map<String, _Utterance> _byId = <String, _Utterance>{};

  /// 被丢弃的未开播句数（对应 `hint.audio_dropped`）。
  int droppedUtterances = 0;

  /// 因缺口跳过的片数。
  int skippedChunks = 0;

  /// 当前队首句 id（无则为 null）。
  String? get headUtteranceId => _queue.isEmpty ? null : _queue.first.utteranceId;

  /// 队列深度（含已开播的队首）。
  int get depth => _queue.length;

  /// 声明一句（来自 `speech` 元数据）。
  void declare(String utteranceId, {String text = ''}) {
    if (utteranceId.isEmpty) return;
    if (_byId.containsKey(utteranceId)) return;
    final utterance = _Utterance(utteranceId: utteranceId, text: text);
    _queue.add(utterance);
    _byId[utteranceId] = utterance;
    _enforceQueueLimit();
  }

  /// 追加一片（`audio.header` + 紧随的二进制）。
  void addChunk(String utteranceId, int seq, List<int> bytes, {required bool last}) {
    final utterance = _byId[utteranceId];
    if (utterance == null) return;
    // 末片之后不应再有更大的 seq；但末片之前迟到的片仍要收下（乱序容忍）。
    if (utterance.ended && utterance.lastSeq != null && seq > utterance.lastSeq!) return;
    utterance.pending[seq] = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (last) {
      utterance.lastSeq = seq;
      utterance.ended = true;
    }
  }

  /// 取队首句下一个可播片；无可播片时返回 null。
  ///
  /// 交付顺序保证 seq 递增：缺口在重排窗内则等待，超过窗口则跳过并继续。
  ({String utteranceId, int seq, Uint8List bytes, bool last})? nextChunk() {
    while (_queue.isNotEmpty) {
      final head = _queue.first;
      final wanted = head.deliveredUpTo + 1;

      if (!head.pending.containsKey(wanted)) {
        final newest = head.pending.isEmpty ? -1 : head.pending.lastKey()!;
        final lastKnown = head.lastSeq ?? -1;
        final streamEnded = head.ended && wanted > lastKnown;
        if (streamEnded) {
          _removeHead();
          continue;
        }
        final gapTooLong = newest - wanted >= reorderWindow;
        if (!gapTooLong) return null;
        // 缺口超过重排窗：丢掉更早的残片，从当前最小可用 seq 继续。
        head.pending.removeWhere((key, _) => key < wanted);
        if (head.pending.isEmpty) return null;
        head.skipped += 1;
        skippedChunks += 1;
        head.deliveredUpTo = head.pending.firstKey()! - 1;
        continue;
      }

      final bytes = head.pending.remove(wanted)!;
      head.deliveredUpTo = wanted;
      final isLast = head.lastSeq == wanted;
      final utteranceId = head.utteranceId;
      if (isLast) _removeHead();
      return (
        utteranceId: utteranceId,
        seq: wanted,
        bytes: bytes,
        last: isLast,
      );
    }
    return null;
  }

  /// 丢弃全部排队（`Flushing`）。
  void flush() {
    _queue.clear();
    _byId.clear();
  }

  void _enforceQueueLimit() {
    // 只丢“未开播”的句：保留队首（可能已开播）与最新句。
    while (_queue.length > maxQueue + 1) {
      final victim = _queue.removeAt(1);
      _byId.remove(victim.utteranceId);
      droppedUtterances += 1;
    }
  }

  void _removeHead() {
    if (_queue.isEmpty) return;
    final head = _queue.removeAt(0);
    _byId.remove(head.utteranceId);
  }
}