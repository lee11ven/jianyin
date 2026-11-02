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
recognitionWindowMs: 1000, // 环形缓冲覆盖的最近窗口（起点 0.6–1.2 s）
  recognitionMinFrames: 8, // 单段参与积分的最少帧数
  recognitionMinSegmentMs: 200, // 单段最短时长
  recognitionMaxSegmentMs: 1500, // 单段最长时长（到时强制切段）
  recognitionGapMs: 200, // T_gap：连续 gap 超过该值必须切开，禁止假连接
  recognitionScoreThreshold: 0.6, // 出词阈值（宁缺勿错）
  recognitionRepeatSuppressMs: 2000, // 同词节流窗口
  ttsSampleRate: 16_000,
  ttsChannels: 1,
  ttsChunkSamples: 1600, // 100ms @ 16kHz
  ttsBackpressureBytes: 256 * 1024, // ≈ 8 s 音频：超阈值丢最旧未发送片
  // 合成后端：'tone' = 离线确定性合成（演示/开发用，不依赖外部服务）；
  // 'none' = 仅发元数据与末片空二进制。生产必须换成真实合成器（见 tts.js）。
  ttsBackend: process.env.TTS_BACKEND || 'tone',
};

/** 开发默认密钥：production 下使用它会在启动时直接失败。 */
export const DEFAULT_JWT_SECRET = 'jianyin-dev-jwt-secret-change-me';

export function isDebugBuild() {
  return config.nodeEnv !== 'production';
}

/**
 * 启动即校验：production 不得使用默认/空 JWT 密钥（避免“部署后忘记改”的静默风险）。
 * @throws {Error} 配置不安全时抛出，由 index.js 在监听前调用。
 */
export function assertSecureConfig() {
  if (config.nodeEnv === 'production' && config.jwtSecret === DEFAULT_JWT_SECRET) {
    throw new Error(
      'JWT_SECRET must be set to a strong random value when NODE_ENV=production',
    );
  }
  if (!config.jwtSecret || config.jwtSecret.length < 8) {
    throw new Error('JWT_SECRET is missing or too short');
  }
}
