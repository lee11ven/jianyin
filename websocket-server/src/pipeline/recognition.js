/**
 * 云端滑动窗口识别的**一期最小可用实现**（替换原空 stub）。
 *
 * 职责：按 `ts` 对齐多通道上行 → 切出活动段 → 积分特征 → 规则词表打分 →
 * 产出 `recognition` 结果（由 `onResult` 扇出到 App / 穿戴）。
 *
 * 契约：docs/design/算法/云端/滑动窗口识别.md、docs/api/protocol.md。
 * 可替换点：`lexicon.rankCandidates` 换成模型推理即可，其余环节保持不变。
 */
import { config } from '../config.js';
import { gesturesCatalog } from '../data/gestures.js';
import { extractSegmentFeatures } from './features.js';
import { DEFAULT_SCORE_THRESHOLD, rankCandidates } from './lexicon.js';

function supportsMotion(frame) {
  return Boolean(frame && frame.path && typeof frame.path === 'object' && frame.path.gap !== true);
}

/**
 * 把缓冲切成**已闭合**的活动段；未闭合的尾段留在 `rest` 里等后续帧。
 * 闭合条件：后一帧与段末间隔 ≥ `gapMs`，或段自身时长 ≥ `maxSegmentMs`（强制切）。
 */
export function splitSegments(frames, { gapMs, maxSegmentMs }) {
  const segments = [];
  const list = Array.isArray(frames) ? frames : [];
  let i = 0;
  while (i < list.length && !supportsMotion(list[i])) i += 1;

  while (i < list.length) {
    let j = i;
    while (j + 1 < list.length && supportsMotion(list[j + 1])) j += 1;
    const duration = list[j].ts - list[i].ts;
    const nextTs = j + 1 < list.length ? list[j + 1].ts : null;
    const closedByGap = nextTs !== null && nextTs - list[j].ts >= gapMs;
    const forced = duration >= maxSegmentMs;
    if (!closedByGap && !forced) break;

    segments.push({ frames: list.slice(i, j + 1), closedByGap });
    i = j + 1;
    while (i < list.length && !supportsMotion(list[i])) i += 1;
  }

  return { segments, rest: list.slice(i) };
}

export class RecognitionPipeline {
  /**
   * @param {{ onResult?: (result: object) => void, now?: () => number, options?: object }} deps
   */
  constructor({ onResult, now, options } = {}) {
    this.onResult = typeof onResult === 'function' ? onResult : () => {};
    this.now = typeof now === 'function' ? now : () => Date.now();
    this.options = {
      windowMs: config.recognitionWindowMs,
      minFrames: config.recognitionMinFrames,
      minSegmentMs: config.recognitionMinSegmentMs,
      maxSegmentMs: config.recognitionMaxSegmentMs,
      gapMs: config.recognitionGapMs,
      threshold: config.recognitionScoreThreshold ?? DEFAULT_SCORE_THRESHOLD,
      suppressMs: config.recognitionRepeatSuppressMs,
      ...(options ?? {}),
    };
    /** @type {Map<string, {frames: object[], utteranceSeq: number, lastEmitted: {glossId: string, ts: number} | null}>} */
    this.sessions = new Map();
  }

  /** 保留窗口：至少覆盖最长活动段，便于闭合判定。 */
  get retentionMs() {
    return Math.max(this.options.windowMs, this.options.maxSegmentMs + this.options.gapMs);
  }

  get maxFrames() {
    return Math.max(64, Math.ceil(this.retentionMs / 20));
  }

  _state(sessionId) {
    let state = this.sessions.get(sessionId);
    if (!state) {
      state = { frames: [], utteranceSeq: 0, lastEmitted: null };
      this.sessions.set(sessionId, state);
    }
    return state;
  }

  reset(sessionId) {
    this.sessions.delete(sessionId);
  }

  /**
   * 收一拍上行。按 `ts` 升序入环；环满/超窗丢最旧拍，保实时。
   * @returns {object[]} 本次新产出的 recognition 结果（通常 0 或 1 条）
   */
  ingest(sessionId, msg) {
    if (!sessionId || !msg || typeof msg !== 'object') return [];
    const state = this._state(sessionId);
    state.frames.push({
      ts: Number.isFinite(msg.ts) ? msg.ts : this.now(),
      hands: msg.hands ?? null,
      path: msg.path ?? null,
      body: msg.body ?? null,
      nonmanual: msg.nonmanual ?? null,
    });
    state.frames.sort((a, b) => a.ts - b.ts);
    this._prune(state);

    const { segments, rest } = splitSegments(state.frames, this.options);
    state.frames = rest.slice(-this.maxFrames);

    const produced = [];
    for (const segment of segments) {
      const result = this._evaluate(sessionId, state, segment.frames);
      if (result) produced.push(result);
    }
    return produced;
  }

  _prune(state) {
    if (state.frames.length === 0) return;
    const newest = state.frames[state.frames.length - 1].ts;
    const floor = newest - this.retentionMs;
    let drop = 0;
    while (drop < state.frames.length && state.frames[drop].ts < floor) drop += 1;
    if (drop > 0) state.frames = state.frames.slice(drop);
    if (state.frames.length > this.maxFrames) {
      state.frames = state.frames.slice(state.frames.length - this.maxFrames);
    }
  }

  _evaluate(sessionId, state, frames) {
    const first = frames[0];
    const last = frames[frames.length - 1];
    const duration = last.ts - first.ts;
    if (frames.length < this.options.minFrames || duration < this.options.minSegmentMs) {
      return null;
    }

    const features = extractSegmentFeatures(frames);
    const ranked = rankCandidates(features);
    const best = ranked[0];

    if (!best || best.score < this.options.threshold) {
      this._logFeatures(sessionId, features, null);
      return null;
    }

    const previous = state.lastEmitted;
    if (
      previous &&
      previous.glossId === best.id &&
      last.ts - previous.ts < this.options.suppressMs
    ) {
      this._logFeatures(sessionId, features, { suppressed: best.id });
      return null;
    }

    state.utteranceSeq += 1;
    const result = {
      sessionId,
      utteranceId: `utt-${String(sessionId).slice(-4)}-${state.utteranceSeq}`,
      text: best.text,
      confidence: Number(best.score.toFixed(3)),
      glossIds: [best.id],
      vocabVersion: gesturesCatalog.vocabVersion,
      ts: last.ts,
    };
    state.lastEmitted = { glossId: best.id, ts: last.ts };
    this._logFeatures(sessionId, features, best);
    this.onResult(result);
    return result;
  }

  /** 特征日志：便于按验收口径抽查 shape / places / handshape / contactSite。 */
  _logFeatures(sessionId, features, decision) {
    const parts = [
      `[recognition] sid=${sessionId}`,
      `shape=${features.motion.shape ?? '-'}`,
      `dir=${features.motion.direction ?? '-'}`,
      `repeats=${features.motion.repeats}`,
      `pathLen=${features.motion.pathLength.toFixed(3)}`,
      `places=${features.place ?? 'none'}`,
      `contactSite=${features.contactSite ?? 'none'}`,
      `hand=L:${features.handshape.left ?? '-'}|R:${features.handshape.right ?? '-'}`,
      `channels=${features.channels.hands}/${features.channels.path}/${features.channels.body}/${features.channels.nonmanual}`,
    ];
    if (decision === null) parts.push('-> no-match');
    else if (decision && decision.suppressed) parts.push(`-> suppressed(${decision.suppressed})`);
    else if (decision) parts.push(`-> ${decision.id} score=${decision.score.toFixed(2)}`);
    console.log(parts.join(' '));
  }
}