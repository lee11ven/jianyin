/**
 * 演示用**规则词表（可替换后端）**。
 *
 * 每个词条由若干谓词组成，命中权重占比即置信度。模板只描述演示词表里的 8 个词，
 * 与 `src/data/gestures.json` 的 `id` 对应；替换为模型推理时，只需换掉本文件的
 * `rankCandidates`，前后（缓冲 / 对齐 / 段切分 / 特征契约 / 输出字段）保持不变。
 *
 * 谓词语义见 docs/design/算法/云端/滑动窗口识别.md「一期最小可用实现」。
 */
import { gesturesCatalog } from '../data/gestures.js';

/** 出词阈值（可被 config 覆盖）。 */
export const DEFAULT_SCORE_THRESHOLD = 0.6;

const P = {
  repeatsMin: (min) => ({
    name: `repeats>=${min}`,
    weight: 1,
    test: (f) => f.motion.repeats >= min,
  }),
  shape: (...any) => ({
    name: `shape:${any.join('|')}`,
    weight: 1,
    test: (f) => any.includes(f.motion.shape),
  }),
  direction: (...any) => ({
    name: `dir:${any.join('|')}`,
    weight: 1,
    test: (f) => any.includes(f.motion.direction),
  }),
  place: (...any) => ({
    name: `place:${any.join('|')}`,
    weight: 1,
    test: (f) => any.includes(f.place),
  }),
  handshape: (...any) => ({
    name: `hand:${any.join('|')}`,
    weight: 1,
    test: (f) => any.includes(f.handshape.left) || any.includes(f.handshape.right),
  }),
};

/**
 * 8 个演示词的模板。
 * 手形位掩码顺序 `[thumb, index, middle, ring, pinky]`。
 */
export const DEMO_TEMPLATES = {
  hello: [
    P.handshape('11111'),
    P.repeatsMin(2),
    P.shape('arc', 'multi'),
    P.direction('E', 'W'),
  ],
  goodbye: [
    P.handshape('01111'),
    P.repeatsMin(2),
    P.shape('arc', 'multi'),
    P.direction('E', 'W'),
  ],
  thanks: [
    P.handshape('01111'),
    P.shape('straight', 'arc'),
    P.direction('S', 'SE', 'SW'),
    P.place('chest', 'head'),
  ],
  yes: [
    P.handshape('00000'),
    P.shape('straight', 'arc'),
    P.direction('S', 'SE', 'SW'),
  ],
  no: [
    P.handshape('01000'),
    P.repeatsMin(2),
    P.direction('E', 'W'),
  ],
  ok: [
    P.handshape('11000'),
    P.shape('arc', 'straight'),
    P.direction('E', 'SE', 'NE'),
  ],
  help: [
    P.handshape('01111'),
    P.place('chest'),
    P.direction('N', 'NE', 'NW'),
  ],
  sorry: [
    P.handshape('00000'),
    P.place('chest', 'head'),
    P.repeatsMin(1),
  ],
};

/**
 * 对一段特征按演示词表打分，返回按分数降序的候选。
 * @param {object} features extractSegmentFeatures 的输出
 */
export function rankCandidates(features) {
  const rows = [];
  for (const gesture of gesturesCatalog.gestures ?? []) {
    const template = DEMO_TEMPLATES[gesture.id];
    if (!template) continue;
    let matchedWeight = 0;
    let totalWeight = 0;
    const matchedNames = [];
    for (const predicate of template) {
      totalWeight += predicate.weight;
      if (predicate.test(features)) {
        matchedWeight += predicate.weight;
        matchedNames.push(predicate.name);
      }
    }
    rows.push({
      id: gesture.id,
      text: gesture.text,
      aliases: gesture.aliases ?? [],
      score: totalWeight > 0 ? matchedWeight / totalWeight : 0,
      matchedWeight,
      totalWeight,
      matchedNames,
    });
  }
  rows.sort(
    (a, b) =>
      b.score - a.score ||
      b.matchedWeight - a.matchedWeight ||
      a.id.localeCompare(b.id),
  );
  return rows;
}