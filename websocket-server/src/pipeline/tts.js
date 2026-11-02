/**
 * 流式 TTS 的**离线确定性合成后端**（一期最小可用）。
 *
 * 输出协议锁定的 **PCM s16le / 16 kHz / mono**，按 `config.ttsChunkSamples`
 * （1600 采样 = 100 ms）切片。接口 `synthesizePcmChunks(text, options)` 视为
 * **可替换点**：接入真实合成器（云厂商流式 TTS 或本地模型）时，只替换本函数，
 * 分片长度、`audio.header` 时序与按 `utteranceId` 串行规则保持不变。
 *
 * 说明：本后端按字符生成确定性语音状波形（基频 + 谐波 + 包络），不是真实
 * 语音合成；仅用于打通链路与联调，生产须设置 `TTS_BACKEND` 为真实后端。
 * 契约见 docs/design/系统架构/architecture.md「流式 TTS 落地（最小可用）」。
 */
import { config } from '../config.js';

/** 协议锁定的音频格式。 */
export const PCM_FORMAT = {
  mimeType: 'audio/pcm',
  encoding: 's16le',
};

/** 每字符发音时长与字符间静音（ms）。 */
const CHAR_DURATION_MS = 200;
const GAP_MS = 60;

/** 峰值幅度（留混音余量，避免削顶）。 */
const AMPLITUDE = 0.22;

function envelopeAt(ratio) {
  const attack = 0.12;
  const release = 0.22;
  if (ratio < attack) return ratio / attack;
  if (ratio > 1 - release) return ((1 - ratio) / release) * 0.75;
  return 0.75;
}

/** 字符 → 基频：确定性映射，同一字符永远同一音高（便于测试与回放）。 */
function baseFrequency(char) {
  return 170 + (char.codePointAt(0) % 60);
}

function toInt16(value) {
  const clamped = Math.max(-1, Math.min(1, value));
  return Math.round(clamped * 32767);
}

function pushCharSamples(out, char, sampleRate) {
  const sampleCount = Math.round((CHAR_DURATION_MS * sampleRate) / 1000);
  const gapCount = Math.round((GAP_MS * sampleRate) / 1000);
  const base = baseFrequency(char);
  for (let i = 0; i < sampleCount; i += 1) {
    const ratio = i / sampleCount;
    const contour = 1 + 0.07 * Math.sin(2 * Math.PI * 1.25 * ratio);
    const frequency = base * contour;
    const t = i / sampleRate;
    const wave =
      Math.sin(2 * Math.PI * frequency * t) * 0.6 +
      Math.sin(2 * Math.PI * 2 * frequency * t) * 0.25 +
      Math.sin(2 * Math.PI * 3 * frequency * t) * 0.15;
    out.push(toInt16(wave * envelopeAt(ratio) * AMPLITUDE));
  }
  for (let i = 0; i < gapCount; i += 1) out.push(0);
}

/**
 * @param {string} text 待合成文本（`recognition.text`）
 * @param {{ sampleRate?: number, channels?: number, chunkSamples?: number, backend?: string }} [options]
 * @returns {{ mimeType: string, encoding: string, sampleRate: number, channels: number,
 *             chunks: Buffer[], durationMs: number, charCount: number }}
 */
export function synthesizePcmChunks(text, options = {}) {
  const sampleRate = options.sampleRate ?? config.ttsSampleRate;
  const channels = options.channels ?? config.ttsChannels;
  const chunkSamples = options.chunkSamples ?? config.ttsChunkSamples;
  const backend = options.backend ?? config.ttsBackend;

  const chars =
    typeof text === 'string' ? [...text].filter((char) => char.trim().length > 0) : [];

  const samples = [];
  if (backend !== 'none') {
    for (const char of chars) pushCharSamples(samples, char, sampleRate);
  }

  const chunks = [];
  for (let i = 0; i < samples.length; i += chunkSamples) {
    const slice = samples.slice(i, i + chunkSamples);
    const buffer = Buffer.allocUnsafe(slice.length * 2);
    for (let j = 0; j < slice.length; j += 1) buffer.writeInt16LE(slice[j], j * 2);
    chunks.push(buffer);
  }

  return {
    ...PCM_FORMAT,
    sampleRate,
    channels,
    chunks,
    durationMs: Math.round((samples.length / sampleRate) * 1000),
    charCount: chars.length,
  };
}