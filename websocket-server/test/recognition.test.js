import test from 'node:test';
import assert from 'node:assert/strict';

import { RecognitionPipeline, splitSegments } from '../src/pipeline/recognition.js';
import { gesturesCatalog } from '../src/data/gestures.js';

function point(x, y, v = 1) {
  return { x, y, z: 0, v };
}

function hands42(mask = '11111') {
  const points = new Array(42).fill(null).map(() => point(0.5, 0.5, 1));
  const order = [4, 8, 12, 16, 20];
  const pipOrder = [3, 6, 10, 14, 18];
  for (const offset of [0, 21]) {
    points[offset] = point(0.5, 0.5, 1);
    order.forEach((tipIndex, i) => {
      points[offset + tipIndex] =
        mask[i] === '1' ? point(0.5 + 0.2, 0.5, 1) : point(0.5 + 0.05, 0.5, 1);
      points[offset + pipOrder[i]] = point(0.5 + 0.1, 0.5, 1);
    });
  }
  return points;
}

function landmarks(ts, x, mask = '11111') {
  return {
    type: 'landmarks',
    protocolVersion: 1,
    ts,
    sessionId: 'sess-abcdef01',
    schema: 'csl_channels_v1',
    hands: { schema: 'mediapipe_hands_v1', points: hands42(mask) },
    path: {
      space: 'image',
      anchor: false,
      gap: false,
      left: { wrist: point(x, 0.5), palm: point(x, 0.5), tips: {} },
      right: { wrist: point(0, 0, 0), palm: point(0, 0, 0), tips: {} },
    },
  };
}

function gap(ts) {
  return {
    type: 'landmarks',
    protocolVersion: 1,
    ts,
    sessionId: 'sess-abcdef01',
    schema: 'csl_channels_v1',
    path: { space: 'image', anchor: false, gap: true },
  };
}

function collect() {
  const results = [];
  return { results, onResult: (r) => results.push(r) };
}

/** 9 帧 ≈ 320 ms 的横向摆动；帧数需 ≥ recognitionMinFrames（8）。 */
const WAVE = [0.30, 0.45, 0.60, 0.45, 0.30, 0.45, 0.60, 0.45, 0.30];

function feedWave(pipeline, startTs, step = 40) {
  let produced = [];
  WAVE.forEach((x, i) => {
    produced = produced.concat(pipeline.ingest('sess-abcdef01', landmarks(startTs + i * step, x)));
  });
  return produced;
}

test('splitSegments：按 gap 切开，未闭合尾段留在 rest', () => {
  const frames = [
    { ts: 0, path: { gap: false } },
    { ts: 40, path: { gap: false } },
    { ts: 80, path: { gap: false } },
    { ts: 400, path: { gap: true } },
    { ts: 440, path: { gap: false } },
  ];
  const { segments, rest } = splitSegments(frames, { gapMs: 200, maxSegmentMs: 1500 });
  assert.equal(segments.length, 1);
  assert.equal(segments[0].frames.length, 3);
  assert.equal(segments[0].closedByGap, true);
  assert.equal(rest.length, 1);
});

test('主线：摆动 → 产出 recognition，字段与词表一致', () => {
  const { results, onResult } = collect();
  const pipeline = new RecognitionPipeline({ onResult });
  const produced = feedWave(pipeline, 1_000_000);
  produced.push(...pipeline.ingest('sess-abcdef01', gap(1_000_000 + WAVE.length * 40 + 300)));

  assert.equal(results.length, 1);
  const result = results[0];
  assert.deepEqual(result.glossIds, ['hello']);
  assert.equal(result.text, '你好');
  assert.equal(result.sessionId, 'sess-abcdef01');
  assert.equal(result.vocabVersion, gesturesCatalog.vocabVersion);
  assert.ok(result.confidence >= 0.6);
  assert.match(result.utteranceId, /^utt-/);
  assert.ok(Number.isFinite(result.ts));
});

test('节流：同词在抑制窗口内不重复出词', () => {
  const { results, onResult } = collect();
  const pipeline = new RecognitionPipeline({ onResult });
  feedWave(pipeline, 2_000_000);
  pipeline.ingest('sess-abcdef01', gap(2_000_000 + WAVE.length * 40 + 300));
  feedWave(pipeline, 2_000_000 + 600);
  pipeline.ingest('sess-abcdef01', gap(2_000_000 + 600 + WAVE.length * 40 + 300));
  assert.equal(results.length, 1, '抑制窗口内不应重复出词');
});

test('降级：段太短（帧数不足）不出词', () => {
  const { results, onResult } = collect();
  const pipeline = new RecognitionPipeline({ onResult });
  pipeline.ingest('sess-abcdef01', landmarks(0, 0.3));
  pipeline.ingest('sess-abcdef01', landmarks(40, 0.6));
  pipeline.ingest('sess-abcdef01', gap(400));
  assert.equal(results.length, 0);
});

test('降级：无位移（still）不出词', () => {
  const { results, onResult } = collect();
  const pipeline = new RecognitionPipeline({ onResult });
  [0, 40, 80, 120, 160, 200, 240, 280].forEach((offset, i) => {
    pipeline.ingest('sess-abcdef01', landmarks(offset, 0.5));
    void i;
  });
  pipeline.ingest('sess-abcdef01', gap(600));
  assert.equal(results.length, 0);
});

test('会话隔离与 reset', () => {
  const { results, onResult } = collect();
  const pipeline = new RecognitionPipeline({ onResult });
  feedWave(pipeline, 3_000_000);
  pipeline.reset('sess-abcdef01');
  pipeline.ingest('sess-abcdef01', gap(3_000_000 + WAVE.length * 40 + 300));
  assert.equal(results.length, 0, 'reset 后缓冲应清空');

  // 另一会话不受影响
  const other = new RecognitionPipeline({ onResult: (r) => results.push(r) });
  WAVE.forEach((x, i) => other.ingest('sess-99999999', { ...landmarks(i * 40, x), sessionId: 'sess-99999999' }));
  other.ingest('sess-99999999', gap(WAVE.length * 40 + 300));
  assert.equal(results.length, 1);
  assert.equal(results[0].sessionId, 'sess-99999999');
});

test('ingest 参数防御：缺 sessionId / 非对象直接忽略', () => {
  const pipeline = new RecognitionPipeline({ onResult: () => {} });
  assert.deepEqual(pipeline.ingest(null, landmarks(0, 0.5)), []);
  assert.deepEqual(pipeline.ingest('sess-abcdef01', null), []);
});

test('中枢超长段：超过 maxSegmentMs 强制切段并出词', () => {
  const results = [];
  const pipeline = new RecognitionPipeline({
    onResult: (r) => results.push(r),
    options: { maxSegmentMs: 400, minFrames: 4, minSegmentMs: 100 },
  });
  WAVE.forEach((x, i) => pipeline.ingest('sess-abcdef01', landmarks(i * 40, x)));
  // 400 ms 处应已强制切段（WAVE 共 7 帧 = 280 ms，此处追加更长的摆动）
  WAVE.forEach((x, i) => pipeline.ingest('sess-abcdef01', landmarks(280 + i * 40, x)));
  assert.ok(results.length >= 1);
});