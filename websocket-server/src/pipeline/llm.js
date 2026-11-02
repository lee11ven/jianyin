/**
 * OpenAI 兼容 Chat Completions 客户端：把切段特征译成中文。
 * 适配 DeepSeek / 通义 / OpenAI 等提供 `/v1/chat/completions` 的服务。
 */
import { config, isLlmEnabled } from '../config.js';
import { gesturesCatalog } from '../data/gestures.js';

const SYSTEM_PROMPT = [
  '你是中国手语（CSL）实时翻译助手。',
  '根据云端提取的手形 / 运动 / 部位特征，以及可选的规则候选词，输出一句简洁自然的中文口语。',
  '只输出一行 JSON，不要 markdown，不要解释：',
  '{"text":"中文译文","glossIds":["词条id"],"confidence":0.0}',
  '规则：',
  '- text 必须是中文，简短口语（如「你好」「谢谢你」），禁止英文与拼音。',
  '- glossIds 尽量选自给定词表 id；无法对应时可为空数组。',
  '- confidence 为 0~1；特征不足以判断时返回 {"text":"","glossIds":[],"confidence":0}。',
  '- 不要编造与特征无关的长句。',
].join('\n');

/**
 * @param {object} features extractSegmentFeatures 输出
 * @param {Array<{id:string,text:string,score:number}>} [candidates]
 */
export function buildTranslateUserPrompt(features, candidates = []) {
  const vocab = (gesturesCatalog.gestures || [])
    .map((g) => `${g.id}=${g.text}`)
    .join(', ');
  const top = (candidates || [])
    .slice(0, 5)
    .map((c) => `${c.id}:${c.text}@${Number(c.score).toFixed(2)}`)
    .join(', ');

  return [
    `词表(vocabVersion=${gesturesCatalog.vocabVersion}): ${vocab}`,
    `规则候选(可选): ${top || '无'}`,
    '特征摘要:',
    JSON.stringify(
      {
        motion: features?.motion ?? null,
        place: features?.place ?? null,
        contactSite: features?.contactSite ?? null,
        handshape: features?.handshape ?? null,
        channels: features?.channels ?? null,
      },
      null,
      0,
    ),
  ].join('\n');
}

/**
 * @param {{ messages: Array<{role:string,content:string}>, signal?: AbortSignal }} opts
 * @returns {Promise<string>} assistant content
 */
export async function chatCompletion({ messages, signal } = {}) {
  if (!isLlmEnabled()) {
    throw new Error('LLM is not configured (set LLM_API_KEY)');
  }

  const { apiBase, apiKey, model, temperature, timeoutMs } = config.llm;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  if (signal) {
    signal.addEventListener('abort', () => controller.abort(), { once: true });
  }

  try {
    const res = await fetch(`${apiBase}/v1/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        temperature,
        messages,
        stream: false,
      }),
      signal: controller.signal,
    });

    const raw = await res.text();
    if (!res.ok) {
      throw new Error(`LLM HTTP ${res.status}: ${raw.slice(0, 240)}`);
    }

    let data;
    try {
      data = JSON.parse(raw);
    } catch {
      throw new Error('LLM response is not JSON');
    }

    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== 'string' || !content.trim()) {
      throw new Error('LLM returned empty content');
    }
    return content.trim();
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 从模型文本里抠出 JSON 对象（容忍偶尔夹带说明文字）。
 * @param {string} content
 */
export function parseLlmJson(content) {
  if (!content || typeof content !== 'string') return null;
  const trimmed = content.trim();
  try {
    return JSON.parse(trimmed);
  } catch {
    const start = trimmed.indexOf('{');
    const end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(trimmed.slice(start, end + 1));
      } catch {
        return null;
      }
    }
    return null;
  }
}

/**
 * 特征 → 中文译文。
 * @returns {Promise<{ text: string, glossIds: string[], confidence: number } | null>}
 */
export async function translateSignToChinese({ features, candidates = [] } = {}) {
  if (!isLlmEnabled()) return null;

  const content = await chatCompletion({
    messages: [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: buildTranslateUserPrompt(features, candidates) },
    ],
  });

  const parsed = parseLlmJson(content);
  if (!parsed || typeof parsed !== 'object') {
    throw new Error(`LLM JSON parse failed: ${content.slice(0, 160)}`);
  }

  const text = typeof parsed.text === 'string' ? parsed.text.trim() : '';
  if (!text) return null;

  const glossIds = Array.isArray(parsed.glossIds)
    ? parsed.glossIds.map(String).filter(Boolean)
    : [];
  let confidence = Number(parsed.confidence);
  if (!Number.isFinite(confidence)) confidence = 0.7;
  confidence = Math.min(1, Math.max(0, confidence));

  return { text, glossIds, confidence };
}

export { isLlmEnabled };
