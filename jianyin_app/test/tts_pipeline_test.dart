import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jianyin_app/tts/jitter_buffer.dart';
import 'package:jianyin_app/tts/pcm_player.dart';
import 'package:jianyin_app/tts/tts_pipeline.dart';
import 'package:jianyin_app/ws/ws_events.dart';

class FakePcmPlayer implements PcmPlayer {
  FakePcmPlayer({this.available = true, this.buffered = 0});

  bool available;

  /// 由测试显式设定的原生水位（帧数）。
  int buffered;
  final List<Uint8List> writes = <Uint8List>[];
  int flushCount = 0;
  int closeCount = 0;

  @override
  Future<bool> open({required int sampleRate, required int channels}) async => available;

  @override
  Future<void> write(Uint8List bytes) async => writes.add(bytes);

  @override
  Future<int> bufferedFrames() async => buffered;

  @override
  Future<void> flush() async {
    flushCount += 1;
    buffered = 0;
  }

  @override
  Future<void> close() async {
    closeCount += 1;
  }

  @override
  int durationMsForBytes(int byteCount) => byteCount ~/ 32;
}

WsSpeechMeta speech(String utteranceId, {bool accepted = true, String delivery = 'ws_binary_audio'}) {
  return WsSpeechMeta(
    sessionId: 'sess-1',
    utteranceId: utteranceId,
    text: '你好',
    delivery: delivery,
    accepted: accepted,
  );
}

WsAudioHeader header(
  String utteranceId, {
  int seq = 0,
  bool last = false,
  int sampleRate = 16000,
  int channels = 1,
  String encoding = 's16le',
  String mimeType = 'audio/pcm',
}) {
  return WsAudioHeader(
    sessionId: 'sess-1',
    utteranceId: utteranceId,
    seq: seq,
    mimeType: mimeType,
    sampleRate: sampleRate,
    channels: channels,
    encoding: encoding,
    last: last,
  );
}

Uint8List pcm(int value, [int length = 64]) =>
    Uint8List.fromList(List<int>.filled(length, value));

void main() {
  group('TtsPipeline 接收与串行', () {
    test('只走 ws_binary_audio：inline_fallback 拒收且不入队', () async {
      final player = FakePcmPlayer();
      final pipeline = TtsPipeline(player: player);
      pipeline.onSpeech(speech('u1', accepted: false, delivery: 'inline_fallback'));
      expect(pipeline.lastRejection, isNotNull);
      expect(pipeline.hasPendingAudio, isFalse);
      await pipeline.onBinary(pcm(1), header: header('u1', last: true));
      expect(player.writes, isEmpty);
    });

    test('非 PCM 格式头拒收（采样率/编码不符）', () async {
      final player = FakePcmPlayer();
      final pipeline = TtsPipeline(player: player);

      pipeline.onHeader(header('u1', sampleRate: 8000));
      expect(pipeline.lastRejection, isNotNull);
      await pipeline.onBinary(pcm(1), header: header('u1', sampleRate: 8000, last: true));
      expect(player.writes, isEmpty);

      pipeline.onHeader(header('u2', mimeType: 'audio/opus', encoding: 'opus'));
      expect(pipeline.lastRejection, isNotNull);
      expect(player.writes, isEmpty);
    });

    test('按 utteranceId 串行写入：后到的句不强插', () async {
      final player = FakePcmPlayer(buffered: 3200); // 200 ms 水位
      final pipeline = TtsPipeline(player: player);

      pipeline.onSpeech(speech('u1'));
      pipeline.onHeader(header('u1', seq: 0, last: false));
      await pipeline.onBinary(pcm(1), header: header('u1', seq: 0));

      // u2 的片先到：必须排在 u1 之后
      await pipeline.onBinary(pcm(3), header: header('u2', seq: 0, last: true));

      pipeline.onHeader(header('u1', seq: 1, last: true));
      await pipeline.onBinary(pcm(2), header: header('u1', seq: 1, last: true));

      expect(player.writes.map((w) => w.first).toList(), [1, 2, 3]);
      expect(pipeline.writtenChunks, 3);
    });

    test('水位到位后进入 playing，末片收句回到 idle', () async {
      final player = FakePcmPlayer(buffered: 3200);
      final pipeline = TtsPipeline(player: player);
      expect(pipeline.state, PlaybackState.idle);

      pipeline.onSpeech(speech('u1'));
      pipeline.onHeader(header('u1', seq: 0, last: false));
      await pipeline.onBinary(pcm(1), header: header('u1', seq: 0));
      expect(pipeline.state, PlaybackState.playing);

      await pipeline.onBinary(pcm(2), header: header('u1', seq: 1, last: true));
      expect(pipeline.state, PlaybackState.idle);
      expect(pipeline.hasPendingAudio, isFalse);
    });

    test('降级：原生不可用时仍计数不发声（链路不中断）', () async {
      final player = FakePcmPlayer(available: false);
      final pipeline = TtsPipeline(player: player);
      final opened = await pipeline.ensureOpen();
      expect(opened, isFalse);
      await pipeline.onBinary(pcm(1), header: header('u1', last: true));
      expect(pipeline.writtenChunks, 1);
    });

    test('flush：清空队列与水位，播放器收到 flush', () async {
      final player = FakePcmPlayer(buffered: 3200);
      final pipeline = TtsPipeline(player: player);
      pipeline.onSpeech(speech('u1'));
      await pipeline.onBinary(pcm(1), header: header('u1', seq: 0, last: false));

      await pipeline.flush();
      expect(pipeline.hasPendingAudio, isFalse);
      expect(pipeline.state, PlaybackState.idle);
      expect(player.flushCount, 1);
    });

    test('无 header 的二进制帧被丢弃', () async {
      final player = FakePcmPlayer();
      final pipeline = TtsPipeline(player: player);
      await pipeline.onBinary(pcm(1));
      expect(player.writes, isEmpty);
      expect(pipeline.lastRejection, isNotNull);
    });
  });

  group('JitterBuffer 水位与欠载', () {
    test('priming → playing 需要达到 T_prime', () {
      final jitter = JitterBuffer();
      jitter.onUtteranceStart();
      expect(jitter.state, PlaybackState.priming);
      jitter.onBufferedFrames(800, 0); // 50 ms
      expect(jitter.state, PlaybackState.priming);
      jitter.onBufferedFrames(3200, 40); // 200 ms
      expect(jitter.state, PlaybackState.playing);
    });

    test('低于 T_low 持续超过 T_underrun_wait → underrun，恢复后回 playing', () {
      final jitter = JitterBuffer();
      jitter.onUtteranceStart();
      jitter.onBufferedFrames(3200, 0);
      expect(jitter.state, PlaybackState.playing);

      jitter.onBufferedFrames(320, 100); // 20 ms，低于 40 ms
      expect(jitter.state, PlaybackState.playing, reason: '未超过等待上限');
      jitter.onBufferedFrames(320, 180);
      expect(jitter.state, PlaybackState.underrun);
      expect(jitter.underrunCount, 1);

      jitter.onBufferedFrames(3200, 260);
      expect(jitter.state, PlaybackState.playing);
    });

    test('2 s 内欠载达到 N_underrun_hint 次 → 弱网提示', () {
      final jitter = JitterBuffer();
      jitter.onUtteranceStart();
      jitter.onBufferedFrames(3200, 0);
      var now = 0;
      for (var i = 0; i < 3; i++) {
        now += 300;
        jitter.onBufferedFrames(0, now);
        jitter.onBufferedFrames(0, now + 80); // 持续低于 T_low 超过 T_underrun_wait
        jitter.onBufferedFrames(3200, now + 120); // 恢复
      }
      expect(jitter.underrunCount, greaterThanOrEqualTo(3));
      expect(jitter.hintNetworkAudio, isTrue);

      jitter.completeFlush();
      expect(jitter.hintNetworkAudio, isFalse);
      expect(jitter.underrunCount, 0);
    });

    test('参数约束：必须满足 T_low < T_prime ≤ T_target', () {
      expect(
        () => JitterBuffer(primeMs: 40, lowMs: 40),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}