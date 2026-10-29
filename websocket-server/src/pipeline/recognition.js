import { randomBytes } from 'node:crypto';
import { config } from '../config.js';
import { gesturesCatalog } from '../data/gestures.js';

/**
 * Per-session sliding window mock recognizer.
 * Triggers after enough frames within recognitionWindowMs.
 */
export class RecognitionPipeline {
  constructor({ onResult }) {
    /** @type {Map<string, { frames: Array<{ ts: number }>, lastEmitAt: number }>} */
    this.windows = new Map();
    this.onResult = onResult;
    this.gestures = gesturesCatalog.gestures;
    this.vocabVersion = gesturesCatalog.vocabVersion;
    this.roundRobin = 0;
  }

  reset(sessionId) {
    this.windows.delete(sessionId);
  }

  /**
   * @param {string} sessionId
   * @param {object} landmarksMsg
   */
  ingest(sessionId, landmarksMsg) {
    const now = Date.now();
    let win = this.windows.get(sessionId);
    if (!win) {
      win = { frames: [], lastEmitAt: 0 };
      this.windows.set(sessionId, win);
    }

    const ts = typeof landmarksMsg.ts === 'number' ? landmarksMsg.ts : now;
    win.frames.push({ ts });
    // Keep ~2 windows of frames
    const cutoff = now - config.recognitionWindowMs * 2;
    win.frames = win.frames.filter((f) => f.ts >= cutoff);

    const windowStart = now - config.recognitionWindowMs;
    const inWindow = win.frames.filter((f) => f.ts >= windowStart);
    const cooledDown = now - win.lastEmitAt >= config.recognitionWindowMs;

    if (inWindow.length >= config.recognitionMinFrames && cooledDown) {
      win.lastEmitAt = now;
      win.frames = [];
      const gesture = this.gestures[this.roundRobin % this.gestures.length];
      this.roundRobin += 1;
      const utteranceId = `utt-${randomBytes(6).toString('hex')}`;
      this.onResult({
        sessionId,
        utteranceId,
        text: gesture.text,
        confidence: 0.85 + Math.random() * 0.1,
        glossIds: [gesture.id],
        vocabVersion: this.vocabVersion,
        ts: now,
      });
    }
  }
}
