import { config } from '../config.js';

/**
 * Mock streaming TTS: generate a short sine tone as s16le PCM chunks.
 * Duration scales lightly with text length.
 */
export function synthesizePcmChunks(text) {
  const sampleRate = config.ttsSampleRate;
  const channels = config.ttsChannels;
  const chunkSamples = config.ttsChunkSamples;
  const durationSec = Math.min(1.8, 0.35 + (text?.length || 1) * 0.08);
  const totalSamples = Math.floor(sampleRate * durationSec);
  const freq = 440;
  const amplitude = 0.25;

  /** @type {Buffer[]} */
  const chunks = [];
  for (let offset = 0; offset < totalSamples; offset += chunkSamples) {
    const n = Math.min(chunkSamples, totalSamples - offset);
    const buf = Buffer.alloc(n * 2 * channels);
    for (let i = 0; i < n; i++) {
      const t = (offset + i) / sampleRate;
      // Soft envelope to avoid clicks
      const env =
        Math.min(1, (offset + i) / (sampleRate * 0.02)) *
        Math.min(1, (totalSamples - offset - i) / (sampleRate * 0.02));
      const sample = Math.sin(2 * Math.PI * freq * t) * amplitude * env;
      const int16 = Math.max(-32768, Math.min(32767, Math.floor(sample * 32767)));
      buf.writeInt16LE(int16, i * 2);
    }
    chunks.push(buf);
  }

  return {
    mimeType: 'audio/pcm',
    sampleRate,
    channels,
    encoding: 's16le',
    chunks,
  };
}
