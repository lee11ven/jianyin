import test from 'node:test';
import assert from 'node:assert/strict';

import { synthesizePcmChunks } from '../src/pipeline/tts.js';
import { TtsDispatcher, wsTarget } from '../src/pipeline/tts_queue.js';
import { config } from '../src/config.js';

function fakeTarget({ buffered = 0 } = {}) {
  const target = {
    sent: [],
    buffered,
    sendJson(msg) {
      this.sent.push({ kind: 'json', msg });
    },
    sendBinary(buf) {
      this.sent.push({ kind: 'bin', bytes: buf.length, buf });
    },
    bufferedAmount() {
      return target.buffered;
    },
  };
  return target;
}

/** 手动计时器：显式驱动，避免测试里等真实时间。 */
function manualClock() {
  const timers = [];
  return {
    schedule: (fn, ms) => {
      const handle = { fn, ms, fired: false };
      timers.push(handle);
      return handle;
    },
    cancelTimer: (handle) => {
      if (handle) handle.fired = true;
    },
    /** 依次触发最早排队的计时器，返回是否还有未触发项。 */
    tick() {
      const handle = timers.find((t) => !t.fired);
      if (!handle) return false;
      handle.fired = true;
      handle.fn();
      return true;
    },
    get pending() {
      return timers.filter((t) => !t.fired).length;
    },
  };
}

test('合成器：PCM 分片尺寸与格式符合协议', () => {
  const out = synthesizePcmChunks('你好');
  assert.equal(out.sampleRate, config.ttsSampleRate);
  assert.equal(out.channels, 1);
  assert.equal(out.mimeType, 'audio/pcm');
  assert.equal(out.encoding, 's16le');
  assert.equal(out.charCount, 2);
  assert.ok(out.chunks.length >= 2, '两个字符应产生多片');
  for (const chunk of out.chunks.slice(0, -1)) {
    assert.equal(chunk.length, config.ttsChunkSamples * 2, '非末片必须是 100 ms 的 16-bit 单声道');
  }
  assert.ok(out.durationMs > 0);
});

test('合成器：确定性（同文本同字节）与空文本', () => {
  assert.deepEqual(synthesizePcmChunks('谢谢').chunks, synthesizePcmChunks('谢谢').chunks);
  const empty = synthesizePcmChunks('');
  assert.equal(empty.chunks.length, 0);
  assert.equal(empty.charCount, 0);

  const none = synthesizePcmChunks('你好', { backend: 'none' });
  assert.equal(none.chunks.length, 0);
});

test('调度器：首片立即发，speech → header → binary 成对且 seq 递增', () => {
  const clock = manualClock();
  const target = fakeTarget();
  const dispatcher = new TtsDispatcher({ schedule: clock.schedule, cancelTimer: clock.cancelTimer });
  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u1', text: '你好', targets: [target] });

  const first = target.sent;
  assert.equal(first[0].kind, 'json');
  assert.equal(first[0].msg.type, 'speech');
  assert.equal(first[0].msg.delivery, 'ws_binary_audio');
  assert.equal(first[1].msg.type, 'audio.header');
  assert.equal(first[1].msg.seq, 0);
  assert.equal(first[1].msg.last, false);
  assert.equal(first[2].kind, 'bin');

  // 末片必须 last:true，且片数 = chunks 数
  let guard = 0;
  while (clock.tick() && guard < 100) guard += 1;
  const headers = target.sent.filter((e) => e.kind === 'json' && e.msg.type === 'audio.header');
  assert.equal(headers[headers.length - 1].msg.last, true);
  assert.equal(headers.length, synthesizePcmChunks('你好').chunks.length);
  assert.equal(dispatcher.pendingCount, 0);
});

test('调度器：多句严格串行（第二句的 speech 在首句 last 之后）', () => {
  const clock = manualClock();
  const target = fakeTarget();
  const dispatcher = new TtsDispatcher({ schedule: clock.schedule, cancelTimer: clock.cancelTimer });

  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u1', text: '你好', targets: [target] });
  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u2', text: '谢谢', targets: [target] });

  let guard = 0;
  while (clock.tick() && guard < 200) guard += 1;

  const events = target.sent;
  const firstLast = events.findIndex(
    (e) => e.kind === 'json' && e.msg.type === 'audio.header' && e.msg.utteranceId === 'u1' && e.msg.last === true,
  );
  const secondSpeech = events.findIndex(
    (e) => e.kind === 'json' && e.msg.type === 'speech' && e.msg.utteranceId === 'u2',
  );
  assert.ok(firstLast >= 0, 'u1 应有末片');
  assert.ok(secondSpeech > firstLast, 'u2 的 speech 必须在 u1 末片之后');
  assert.equal(dispatcher.pendingCount, 0);
});

test('背压：拥挤目标丢中间片，但末片仍发 last:true 空二进制收句', () => {
  const clock = manualClock();
  const congested = 1024 * 1024;
  const target = {
    sent: [],
    sendJson(msg) {
      this.sent.push({ kind: 'json', msg });
    },
    sendBinary(buf) {
      this.sent.push({ kind: 'bin', bytes: buf.length });
    },
    bufferedAmount: () => congested,
  };
  const dispatcher = new TtsDispatcher({
    schedule: clock.schedule,
    cancelTimer: clock.cancelTimer,
    backpressureBytes: 1024,
  });

  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u1', text: '你好', targets: [target] });
  let guard = 0;
  while (clock.tick() && guard < 100) guard += 1;

  const headers = target.sent.filter((e) => e.kind === 'json' && e.msg.type === 'audio.header');
  const binaries = target.sent.filter((e) => e.kind === 'bin');
  assert.equal(headers.length, 1, '中间片被丢弃，仅剩末片头');
  assert.equal(headers[0].msg.last, true);
  assert.equal(binaries.length, 1);
  assert.ok(binaries[0].bytes > 0, '末片仍携带最后一段 PCM；被丢的是中间片');
  assert.ok(dispatcher.stats.droppedChunks >= 1);
});

test('背压/空流：合成器返回空 chunks 时仍以 last:true 的空二进制收句', () => {
  const clock = manualClock();
  const target = fakeTarget();
  const dispatcher = new TtsDispatcher({
    synthesize: () => ({
      mimeType: 'audio/pcm',
      encoding: 's16le',
      sampleRate: 16000,
      channels: 1,
      chunks: [],
      durationMs: 0,
    }),
    schedule: clock.schedule,
    cancelTimer: clock.cancelTimer,
  });

  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u1', text: '', targets: [target] });
  const headers = target.sent.filter((e) => e.kind === 'json' && e.msg.type === 'audio.header');
  const binaries = target.sent.filter((e) => e.kind === 'bin');
  assert.equal(headers.length, 1);
  assert.equal(headers[0].msg.last, true);
  assert.equal(binaries.length, 1);
  assert.equal(binaries[0].bytes, 0);
  assert.equal(dispatcher.pendingCount, 0);
});

test('cancel：会话结束时清空队列并停止下发', () => {
  const clock = manualClock();
  const target = fakeTarget();
  const dispatcher = new TtsDispatcher({ schedule: clock.schedule, cancelTimer: clock.cancelTimer });
  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u1', text: '你好你好', targets: [target] });
  dispatcher.enqueue({ sessionId: 's1', utteranceId: 'u2', text: '谢谢', targets: [target] });

  dispatcher.cancel('s1');
  const sentBefore = target.sent.length;
  let guard = 0;
  while (clock.tick() && guard < 100) guard += 1;

  assert.equal(dispatcher.pendingCount, 0);
  const after = target.sent.slice(sentBefore);
  assert.equal(after.filter((e) => e.kind === 'json' && e.msg.type === 'speech').length, 0, '取消后不应再开始新句');
});

test('wsTarget：readyState 非 1 时不写套接字', () => {
  const written = [];
  const ws = {
    readyState: 3,
    bufferedAmount: 0,
    send: (...args) => written.push(args),
  };
  const target = wsTarget(ws);
  target.sendJson({ type: 'x' });
  target.sendBinary(Buffer.alloc(2));
  assert.equal(written.length, 0);
  assert.equal(target.bufferedAmount(), 0);

  ws.readyState = 1;
  target.sendJson({ type: 'y' });
  target.sendBinary(Buffer.alloc(2));
  assert.equal(written.length, 2);
});