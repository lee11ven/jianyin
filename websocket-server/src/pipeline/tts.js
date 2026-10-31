import { config } from '../config.js';

/**
 * TTS stub — no mock sine / placeholder audio.
 * Wire a real synthesizer here; until then returns an empty PCM stream.
 */
export function synthesizePcmChunks(_text) {
  const sampleRate = config.ttsSampleRate;
  const channels = config.ttsChannels;
  return {
    mimeType: 'audio/pcm',
    sampleRate,
    channels,
    encoding: 's16le',
    chunks: [],
  };
}
