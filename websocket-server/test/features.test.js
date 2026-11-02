import test from 'node:test';
import assert from 'node:assert/strict';

import {
  extractSegmentFeatures,
  handshapeMask,
  pathPointOf,
} from '../src/pipeline/features.js';
import { rankCandidates, DEFAULT_SCORE_THRESHOLD } from '../src/pipeline/lexicon.js';

const BODY_FRAME = {
  origin: { x: 0.5, y: 0.4, z: 0 },
  shoulderWidth: 0.24,
  right: { x: 1, y: 0, z: 0 },
  up: { x: 0, y: -1, z: 0 },
  zSign: 1,
};

function point(x, y, v = 1) {
  return { x, y, z: 0, v };
}

/** 造 42 点：左右手各自按 5 位掩码伸直/蜷曲。 */
function hands42(leftMask = '11111', rightMask = '11111') {
  const points = new Array(42).fill(null).map(() => point(0.5, 0.5, 1));
  const order = [4, 8, 12, 16, 20];
  const pipOrder = [3, 6, 10, 14, 18];
  for (const [offset, mask] of [
    [0, leftMask],
    [21, rightMask],
  ]) {
    points[offset] = point(0.5, 0.5, 1); // wrist
    order.forEach((tipIndex, i) => {
      const extended = mask[i] === '1';
      points[offset + tipIndex] = extended ? point(0.5 + 0.2, 0.5, 1) : point(0.5 + 0.05, 0.5, 1);
      points[offset + pipOrder[i]] = point(0.5 + 0.1, 0.5, 1);
    });
  }
  return points;
}

function motionFrame(ts, x, { y = 0.5, space = 'image', anchor = false, mask = '11111' } = {}) {
  return {
    ts,
    hands: { schema: 'mediapipe_hands_v1', points: hands42(mask, mask) },
    path: {
      space,
      anchor,
      gap: false,
      left: { wrist: point(x, y), palm: point(x, y), tips: {} },
      right: { wrist: point(0, 0, 0), palm: point(0, 0, 0), tips: {} },
    },
  };
}

function gapFrame(ts) {
  return { ts, path: { space: 'image', anchor: false, gap: true } };
}

test('gap 段：无运动特征，通道计数为 0', () => {
  const features = extractSegmentFeatures([gapFrame(0), gapFrame(40)]);
  assert.equal(features.channels.path, 0);
  assert.equal(features.motion.shape, 'still');
  assert.equal(features.motion.direction, null);
  assert.equal(features.place, null);
  assert.equal(features.handshape.left, null);
});

test('往复摆动：识别为 multi/arc 且 repeats ≥ 2', () => {
  const xs = [0.30, 0.45, 0.60, 0.45, 0.30, 0.45, 0.60];
  const frames = xs.map((x, i) => motionFrame(i * 40, x));
  const features = extractSegmentFeatures(frames);
  assert.ok(features.motion.repeats >= 2, `repeats=${features.motion.repeats}`);
  assert.ok(['arc', 'multi'].includes(features.motion.shape));
  assert.equal(features.pathSamples, 7);
  assert.equal(features.channels.hands, 7);
});

test('直线位移：direction=E、shape=straight', () => {
  const xs = [0.20, 0.30, 0.40, 0.50, 0.60, 0.70];
  const features = extractSegmentFeatures(xs.map((x, i) => motionFrame(i * 40, x)));
  assert.equal(features.motion.direction, 'E');
  assert.equal(features.motion.shape, 'straight');
  assert.equal(features.motion.repeats, 0);
});

test('部位：body 坐标系分档（chest / shoulderR），image 空间不给部位', () => {
  const frames = [0.42, 0.5, 0.58].map((x, i) =>
    motionFrame(i * 40, x, { y: 0.3, space: 'body', anchor: true }),
  );
  for (const frame of frames) frame.body = { nose: point(0.5, 0.2), frame: BODY_FRAME };
  assert.equal(extractSegmentFeatures(frames).place, 'chest');

  const sideFrames = [0.6, 0.65, 0.7].map((x, i) =>
    motionFrame(i * 40, x, { y: 0.3, space: 'body', anchor: true }),
  );
  for (const frame of sideFrames) frame.body = { nose: point(0.5, 0.2), frame: BODY_FRAME };
  assert.equal(extractSegmentFeatures(sideFrames).place, 'shoulderR');

  const noInfoFrames = [0.42, 0.5, 0.58].map((x, i) =>
    motionFrame(i * 40, x, { y: 0.3 }),
  );
  assert.equal(extractSegmentFeatures(noInfoFrames).place, null);
});

test('手形掩码：全伸/全曲/缺可见点', () => {
  assert.equal(handshapeMask(hands42('11111', '00000'), 'left'), '11111');
  assert.equal(handshapeMask(hands42('11111', '00000'), 'right'), '00000');

  const broken = hands42('11111', '11111');
  broken[0].v = 0; // wrist 不可见
  assert.equal(handshapeMask(broken, 'left'), null);

  const curled = hands42('00000', '00000');
  curled[4].v = 0; // 拇指 tip 不可见 → 整手拒判，不插值
  assert.equal(handshapeMask(curled, 'left'), null);
});

test('pathPointOf：腕缺失时降级到掌心', () => {
  const path = {
    space: 'image',
    anchor: false,
    gap: false,
    left: { wrist: point(0, 0, 0), palm: point(0.3, 0.4), tips: {} },
  };
  const p = pathPointOf(path, 'left');
  assert.ok(p);
  assert.equal(p.x, 0.3);
});

test('打分：单次摆动无量级位移时不出词（低于阈值）', () => {
  const frames = [0.5, 0.5, 0.5, 0.5, 0.5].map((x, i) => motionFrame(i * 40, x));
  const features = extractSegmentFeatures(frames);
  const ranked = rankCandidates(features);
  assert.ok(ranked[0].score < DEFAULT_SCORE_THRESHOLD, `top=${ranked[0].id}:${ranked[0].score}`);
});

test('打分：伸直五指横向摆动命中 hello 且分数最高', () => {
  const xs = [0.3, 0.5, 0.7, 0.5, 0.3, 0.5, 0.7];
  const framed = xs.map((x, i) => motionFrame(i * 40, x, { mask: '11111' }));
  const features = extractSegmentFeatures(framed);
  const ranked = rankCandidates(features);
  assert.equal(ranked[0].id, 'hello');
  assert.ok(ranked[0].score >= DEFAULT_SCORE_THRESHOLD);
  assert.equal(ranked[0].text, '你好');
  assert.ok(ranked[0].matchedNames.length >= 3);
});