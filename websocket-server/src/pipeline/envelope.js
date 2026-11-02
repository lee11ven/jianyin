/**
 * WS 信封 `gesture_skeleton_envelope_v1` → 识别管道可消费的 landmarks 形状。
 * catalog 仅用于身份对齐，不参与识别；frame 投影为 csl_channels_v1。
 */

export const ENVELOPE_ID = 'gesture_skeleton_envelope_v1';

/**
 * @param {unknown} msg
 */
export function isEnvelopeMessage(msg) {
  return Boolean(msg && typeof msg === 'object' && msg.envelope === ENVELOPE_ID);
}

/**
 * 把信封双手关节（slot）压成定长 42 点；已是 points 数组则原样返回。
 * @param {object | null | undefined} hands
 */
export function handsFromEnvelope(hands) {
  if (!hands || typeof hands !== 'object') return null;

  if (Array.isArray(hands.points) && hands.points.length >= 42) {
    return {
      schema: hands.schema || 'mediapipe_hands_v1',
      points: hands.points.slice(0, 42),
    };
  }

  const points = Array.from({ length: 42 }, () => ({ x: 0, y: 0, z: 0, v: 0 }));
  let any = false;
  for (const side of ['left', 'right']) {
    const hand = hands[side];
    const joints = hand?.joints;
    if (!Array.isArray(joints)) continue;
    for (const joint of joints) {
      const slot = joint?.slot;
      const p = joint?.point;
      if (typeof slot !== 'number' || slot < 0 || slot >= 42 || !p) continue;
      const x = Number(p.x);
      const y = Number(p.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) continue;
      points[slot] = {
        x,
        y,
        z: Number.isFinite(Number(p.z)) ? Number(p.z) : 0,
        v: Number.isFinite(Number(p.v)) ? Number(p.v) : 1,
      };
      any = true;
    }
  }
  if (!any) return null;
  return { schema: 'mediapipe_hands_v1', points };
}

/**
 * frame 信封 → landmarks 消息；catalog / 其它 kind 返回 null。
 * @param {object} msg
 * @param {string} [sessionId]
 */
export function envelopeToLandmarks(msg, sessionId) {
  if (!isEnvelopeMessage(msg) || msg.kind !== 'frame') return null;

  const landmarks = {
    type: 'landmarks',
    protocolVersion: 1,
    ts: Number.isFinite(msg.ts) ? msg.ts : Date.now(),
    sessionId: sessionId || msg.sessionId,
    schema: 'csl_channels_v1',
  };

  const hands = handsFromEnvelope(msg.hands);
  if (hands) landmarks.hands = hands;
  if (msg.path && typeof msg.path === 'object') landmarks.path = msg.path;
  if (msg.body && typeof msg.body === 'object') landmarks.body = msg.body;
  if (msg.nonmanual && typeof msg.nonmanual === 'object') {
    landmarks.nonmanual = msg.nonmanual;
  }

  return landmarks;
}
