import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/tts/utterance_assembler.dart';

Uint8List bytes(int value, [int length = 2]) => Uint8List.fromList(List.filled(length, value));

void main() {
  group('UtteranceAssembler', () {
    test('按 seq 顺序交付，末片带 last 并出队', () {
      final assembler = UtteranceAssembler();
      assembler.declare('u1', text: '你好');
      assembler.addChunk('u1', 0, bytes(1), last: false);
      assembler.addChunk('u1', 1, bytes(2), last: true);

      final first = assembler.nextChunk();
      expect(first, isNotNull);
      expect(first!.seq, 0);
      expect(first.last, isFalse);
      expect(first.bytes.first, 1);

      final second = assembler.nextChunk();
      expect(second!.seq, 1);
      expect(second.last, isTrue);
      expect(second.bytes.first, 2);

      expect(assembler.nextChunk(), isNull);
      expect(assembler.depth, 0);
      expect(assembler.headUtteranceId, isNull);
    });

    test('乱序：重排窗内等待缺口补齐，不跳片', () {
      final assembler = UtteranceAssembler(reorderWindow: 4);
      assembler.declare('u1');
      assembler.addChunk('u1', 1, bytes(2), last: true);

      expect(assembler.nextChunk(), isNull, reason: 'seq 0 未到，应等待');

      assembler.addChunk('u1', 0, bytes(1), last: false);
      final chunk = assembler.nextChunk();
      expect(chunk!.seq, 0);
      expect(assembler.skippedChunks, 0);
    });

    test('缺片超过重排窗：跳过缺口继续，并计数', () {
      final assembler = UtteranceAssembler(reorderWindow: 2);
      assembler.declare('u1');
      assembler.addChunk('u1', 0, bytes(1), last: false);
      assembler.addChunk('u1', 5, bytes(6), last: true);

      expect(assembler.nextChunk()!.seq, 0);
      // 缺口 1..4 超过重排窗 → 跳到 5 继续
      final jumped = assembler.nextChunk();
      expect(jumped!.seq, 5);
      expect(jumped.last, isTrue);
      expect(assembler.skippedChunks, 1);
    });

    test('串行：队首句未播完，不交付下一句', () {
      final assembler = UtteranceAssembler();
      assembler.declare('u1');
      assembler.declare('u2');
      assembler.addChunk('u2', 0, bytes(9), last: true);
      assembler.addChunk('u1', 0, bytes(1), last: false);

      expect(assembler.headUtteranceId, 'u1');
      expect(assembler.nextChunk()!.bytes.first, 1, reason: '应仍是 u1 的片');
      expect(assembler.headUtteranceId, 'u1');
      expect(assembler.nextChunk(), isNull, reason: 'u1 还有未到的片，不应跳到 u2');

      assembler.addChunk('u1', 1, bytes(2), last: true);
      expect(assembler.nextChunk()!.bytes.first, 2);
      expect(assembler.headUtteranceId, 'u2');
      expect(assembler.nextChunk()!.bytes.first, 9);
    });

    test('未开播句深度超限：丢最旧未开播句', () {
      final assembler = UtteranceAssembler(maxQueue: 3);
      for (var i = 1; i <= 6; i++) {
        assembler.declare('u$i');
      }
      expect(assembler.depth, lessThanOrEqualTo(4));
      expect(assembler.droppedUtterances, greaterThan(0));
      expect(assembler.headUtteranceId, 'u1', reason: '队首（已可能开播）必须保留');
      expect(assembler.depth, 4);
    });

    test('重复 declare 幂等，flush 清空', () {
      final assembler = UtteranceAssembler();
      assembler.declare('u1');
      assembler.declare('u1');
      expect(assembler.depth, 1);
      assembler.addChunk('u1', 0, bytes(1), last: true);
      assembler.flush();
      expect(assembler.depth, 0);
      expect(assembler.nextChunk(), isNull);
    });

    test('未声明的句直接丢弃（防御）', () {
      final assembler = UtteranceAssembler();
      assembler.addChunk('ghost', 0, bytes(1), last: true);
      expect(assembler.nextChunk(), isNull);
      expect(assembler.depth, 0);
    });
  });
}