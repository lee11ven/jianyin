export const config = {
  host: process.env.HOST || '0.0.0.0',
  port: Number(process.env.PORT) || 8000,
  nodeEnv: process.env.NODE_ENV || 'development',
  protocolVersion: 1,
  jwtSecret: process.env.JWT_SECRET || 'jianyin-dev-jwt-secret-change-me',
  tokenTtlSec: 86400,
  heartbeatIntervalMs: 15_000,
  deadConnectionMs: 45_000,
  sessionIdleMs: 10 * 60_000,
  recognitionWindowMs: 1000,
  recognitionMinFrames: 8,
  ttsSampleRate: 16_000,
  ttsChannels: 1,
  ttsChunkSamples: 1600, // 100ms @ 16kHz
};

export function isDebugBuild() {
  return config.nodeEnv !== 'production';
}
