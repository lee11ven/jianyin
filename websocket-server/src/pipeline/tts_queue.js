/**
 * 流式 TTS 的**发送调度器**：按 `utteranceId` 串行、边合成边下发、背压丢片。
 *
 * 规则（docs/design/系统架构/architecture.md「流式 TTS 落地（最小可用）」）：
 * 1. 每句先发 `speech` 元数据，随后按 `seq` 递增发 `audio.header` + 二进制片；
 * 2. **严格串行**：上一句 `last:true` 之后才发下一句的 `speech` + 首片，不交错；
 * 3. 首包立即下发，服务端不整句缓存；
 * 4. 背压：某目标 `bufferedAmount` 超过阈值时丢该片（保实时），末片仍发
 *    `last:true` 的空二进制以正常收句。
 *
 * 依赖（合成器 / 计时器 / 阈值）全部可注入，便于单测。
 */
import { config } from '../config.js';
import { frame } from '../protocol.js';
import { synthesizePcmChunks } from './tts.js';

export class TtsDispatcher {
  constructor({
    synthesize = synthesizePcmChunks,
    chunkMs = 100,
    backpressureBytes = config.ttsBackpressureBytes,
    schedule = (fn, ms) => setTimeout(fn, ms),
    cancelTimer = (handle) => clearTimeout(handle),
    onDone = null,
  } = {}) {
    this.synthesize = synthesize;
    this.chunkMs = chunkMs;
    this.backpressureBytes = backpressureBytes;
    this.schedule = schedule;
    this.cancelTimer = cancelTimer;
    this.onDone = onDone;
    /** @type {Map<string, {queue: object[], current: object|null, timer: unknown}>} */
    this.states = new Map();
    this.stats = { utterances: 0, chunks: 0, droppedChunks: 0 };
  }

  _state(sessionId) {
    let state = this.states.get(sessionId);
    if (!state) {
      state = { queue: [], current: null, timer: null };
      this.states.set(sessionId, state);
    }
    return state;
  }

  get pendingCount() {
    let total = 0;
    for (const state of this.states.values()) {
      total += state.queue.length + (state.current ? 1 : 0);
    }
    return total;
  }

  /**
   * 排队一句。
   * @param {{ sessionId: string, utteranceId: string, text: string,
   *          targets: Array<{ sendJson: (msg: object) => void,
   *                            sendBinary: (buf: Buffer) => void,
   *                            bufferedAmount: () => number }> }} item
   */
  enqueue(item) {
    if (!item || !item.sessionId || !Array.isArray(item.targets) || item.targets.length === 0) {
      return;
    }
    const state = this._state(item.sessionId);
    state.queue.push(item);
    if (!state.current) this._begin(item.sessionId);
  }

  /** 会话结束 / 被替换：清空排队并停止当前句。 */
  cancel(sessionId) {
    const state = this.states.get(sessionId);
    if (!state) return;
    state.queue = [];
    if (state.timer) {
      this.cancelTimer(state.timer);
      state.timer = null;
    }
    const current = state.current;
    state.current = null;
    if (current) {
      // 不再补发任何帧：客户端由会话层（Flushing / 断开）收口，避免无头二进制。
      this._settle(sessionId, current, { cancelled: true });
    } else {
      this.states.delete(sessionId);
    }
  }

  _begin(sessionId) {
    const state = this._state(sessionId);
    const item = state.queue.shift();
    if (!item) {
      this.states.delete(sessionId);
      return;
    }
    state.current = item;
    this.stats.utterances += 1;

    const pcm = this.synthesize(item.text);
    item.pcm = pcm;
    item.seq = 0;

    const speechMeta = frame('speech', {
      sessionId,
      utteranceId: item.utteranceId,
      text: item.text,
      delivery: 'ws_binary_audio',
      mimeType: pcm.mimeType,
      sampleRate: pcm.sampleRate,
      channels: pcm.channels,
      encoding: pcm.encoding,
    });
    for (const target of item.targets) target.sendJson(speechMeta);

    this._step(sessionId);
  }

  _step(sessionId) {
    const state = this.states.get(sessionId);
    if (!state || !state.current) return;
    const item = state.current;
    const chunks = item.pcm.chunks ?? [];
    const seq = item.seq;
    const isLast = seq >= chunks.length - 1;

    const header = frame('audio.header', {
      sessionId,
      utteranceId: item.utteranceId,
      seq,
      mimeType: item.pcm.mimeType,
      sampleRate: item.pcm.sampleRate,
      channels: item.pcm.channels,
      encoding: item.pcm.encoding,
      last: isLast,
    });

    for (const target of item.targets) {
      const payload = isLast ? chunks[seq] ?? Buffer.alloc(0) : chunks[seq];
      const congested = target.bufferedAmount() > this.backpressureBytes;
      if (congested && !isLast) {
        this.stats.droppedChunks += 1;
        continue; // 丢该片保实时；末片必发，保证客户端正常收句
      }
      target.sendJson(header);
      target.sendBinary(payload ?? Buffer.alloc(0));
      this.stats.chunks += 1;
    }

    if (isLast) {
      this._settle(sessionId, item, {});
      return;
    }

    item.seq += 1;
    state.timer = this.schedule(() => {
      const live = this.states.get(sessionId);
      if (live) live.timer = null;
      this._step(sessionId);
    }, this.chunkMs);
  }

  _settle(sessionId, item, info) {
    const state = this.states.get(sessionId);
    if (state && state.current === item) state.current = null;
    if (this.onDone) this.onDone(sessionId, item, info);
    if (state && state.queue.length > 0 && !info.cancelled) {
      this._begin(sessionId);
    } else if (state) {
      state.timer = null;
      if (!state.current && state.queue.length === 0) this.states.delete(sessionId);
    }
  }
}

/** 把 ws 套接字适配成 dispatcher 需要的 target。 */
export function wsTarget(ws) {
  return {
    ws,
    sendJson: (msg) => {
      if (ws.readyState === 1) ws.send(JSON.stringify(msg));
    },
    sendBinary: (buf) => {
      if (ws.readyState === 1) ws.send(buf, { binary: true });
    },
    bufferedAmount: () => ws.bufferedAmount ?? 0,
  };
}