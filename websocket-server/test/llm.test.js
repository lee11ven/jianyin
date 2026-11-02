import test from 'node:test';
import assert from 'node:assert/strict';

import {
  buildTranslateUserPrompt,
  parseLlmJson,
} from '../src/pipeline/llm.js';
import {
  envelopeToLandmarks,
  handsFromEnvelope,
  isEnvelopeMessage,
} from '../src/pipeline/envelope.js';

test('parseLlmJson：纯 JSON 与夹带文字均可解析', () => {
  assert.deepEqual(parseLlmJson('{"text":"你好","glossIds":["hello"],"confidence":0.9}'), {
    text: '你好',
    glossIds: ['hello'],
    confidence: 0.9,
  });
  assert.equal(parseLlmJson('答案：{"text":"谢谢","glossIds":["thanks"],"confidence":0.8}').text, '谢谢');
  assert.equal(parseLlmJson('not json'), null);
});

test('buildTranslateUserPrompt：包含词表与特征摘要', () => {
  const prompt = buildTranslateUserPrompt(
    {
      motion: { shape: 'arc', direction: 'E', repeats: 2, pathLength: 0.4 },
      place: 'chest',
      contactSite: null,
      handshape: { left: '11111', right: null },
      channels: { hands: true, path: true, body: false, nonmanual: false },
    },
    [{ id: 'hello', text: '你好', score: 0.75 }],
  );
  assert.match(prompt, /hello=你好/);
  assert.match(prompt, /hello:你好@0.75/);
  assert.match(prompt, /"shape":"arc"/);
});

test('envelope frame → landmarks 投影', () => {
  const frame = {
    envelope: 'gesture_skeleton_envelope_v1',
    kind: 'frame',
    ts: 123,
    sessionId: 'sess-1',
    hands: {
      left: {
        joints: [{ slot: 0, point: { x: 0.1, y: 0.2, z: 0, v: 1 } }],
      },
      right: { joints: [] },
    },
    path: { space: 'image', anchor: false, gap: false },
  };
  assert.equal(isEnvelopeMessage(frame), true);
  const lm = envelopeToLandmarks(frame, 'sess-1');
  assert.equal(lm.type, 'landmarks');
  assert.equal(lm.schema, 'csl_channels_v1');
  assert.equal(lm.hands.points[0].x, 0.1);
  assert.equal(lm.path.gap, false);

  assert.equal(envelopeToLandmarks({ ...frame, kind: 'catalog' }), null);
});

test('handsFromEnvelope：已是 42 点则透传', () => {
  const points = Array.from({ length: 42 }, (_, i) => ({ x: i, y: 0, z: 0, v: 1 }));
  const out = handsFromEnvelope({ schema: 'mediapipe_hands_v1', points });
  assert.equal(out.points.length, 42);
  assert.equal(out.points[3].x, 3);
});
