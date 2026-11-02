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
  // 识别后端：'rules' = 离线规则词表（演示/开发用，不依赖外部服务与凭据）；
  // 'model' = 生产时序模型接入点（需在 lexicon.js 的 RANKERS 注册）。未注册后端启动即抛错，不静默降级。
  recognitionBackend: process.env.RECOGNITION_BACKEND || 'rules',
  ttsSampleRate: 16_000,
  ttsChannels: 1,
  ttsChunkSamples: 1600, // 100ms @ 16kHz
  ttsBackpressureBytes: 256 * 1024, // ≈ 8 s 音频：超阈值丢最旧未发送片
  // 合成后端：'tone' = 离线确定性合成（演示/开发用，不依赖外部服务）；
  // 'none' = 仅发元数据与末片空二进制。生产必须换成真实合成器（见 tts.js）。
  ttsBackend: process.env.TTS_BACKEND || 'tone',
  // 大模型（OpenAI 兼容 Chat Completions）。LLM_API_KEY 非空时，切段特征会送 LLM 译成中文；
  // 未配置则仅用规则词表。DeepSeek / 通义 / OpenAI 等只要兼容 /v1/chat/completions 即可。
  llm: {
    provider: process.env.LLM_PROVIDER || '',
    apiBase: (process.env.LLM_API_BASE || 'https://api.deepseek.com').replace(/\/$/, ''),
    apiKey: process.env.LLM_API_KEY || '',
    model: process.env.LLM_MODEL || 'deepseek-flash',
    temperature: Number(process.env.LLM_TEMPERATURE ?? '0'),
    timeoutMs: Number(process.env.LLM_TIMEOUT_MS) || 12_000,
  },
};

/** 是否启用大模型手语→中文翻译。 */
export function isLlmEnabled() {
  return Boolean(config.llm.apiKey && config.llm.apiBase && config.llm.model);
}

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
