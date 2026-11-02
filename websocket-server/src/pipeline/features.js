/**
 * 端侧上行 `csl_channels_v1` 的**段落特征提取**（纯函数，可单测）。
 *
 * 只做观测积分，不做识别：把一段连续非 `gap` 的活动段换算成
 * 运动（direction / shape / repeats）、部位（place）、手形（handshape）
 * 三组特征，并记录各通道是否出现（用于降级矩阵与特征日志）。
 *
 * 契约见 docs/design/算法/云端/滑动窗口识别.md 与 docs/api/protocol.md。
 */

const MIN_JOINT_V = 0.5;

/** 单指伸直判定的阈值：tip–wrist 距离 > pip–wrist 距离 × 该系数。 */
const EXTENSION_RATIO = 1.05;

/** 8 方位（图像坐标，y 向下）：0° = → 东，顺时针。 */
const DIRECTIONS = ['E', 'SE', 'S', 'SW', 'W', 'NW', 'N', 'NE'];

/** MediaPipe 单手局部索引：0=wrist。 */
const FINGERS = [
  { name: 'thumb', tip: 4, pip: 3 },
  { name: 'index', tip: 8, pip: 6 },
  { name: 'middle', tip: 12, pip: 10 },
  { name: 'ring', tip: 16, pip: 14 },
  { name: 'pinky', tip: 20, pip: 18 },
];

const HAND_OFFSET = { left: 0, right: 21 };

function numOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/** 把 `{x,y,z,v}` 读成可用点；缺 `v` 视为可见，`v < MIN_JOINT_V` 视为不可用。 */
function pointOf(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const x = numOrNull(raw.x);
  const y = numOrNull(raw.y);
  if (x === null || y === null) return null;
  const v = numOrNull(raw.v);
  if (v !== null && v < MIN_JOINT_V) return null;
  return { x, y, z: numOrNull(raw.z) ?? 0, v: v ?? 1 };
}

function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function isMotionFrame(frame) {
  return Boolean(
    frame && frame.path && typeof frame.path === 'object' && frame.path.gap !== true,
  );
}

/** 取该侧轨迹点：腕优先，缺腕降级掌心，再降级指尖。 */
export function pathPointOf(path, side) {
  if (!path || typeof path !== 'object') return null;
  const hand = path[side];
  if (!hand || typeof hand !== 'object') return null;
  const wrist = pointOf(hand.wrist);
  if (wrist) return wrist;
  const palm = pointOf(hand.palm);
  if (palm) return palm;
  const tips = hand.tips;
  if (tips && typeof tips === 'object') {
    for (const key of ['index', 'middle', 'ring', 'pinky', 'thumb']) {
      const p = pointOf(tips[key]);
      if (p) return p;
    }
  }
  return null;
}

/**
 * 单手 5 指伸直位掩码，顺序 `[thumb, index, middle, ring, pinky]`。
 * 任一指缺少可用 tip/pip 点时返回 null（宁缺勿错，不插值）。
 */
export function handshapeMask(points, side) {
  const offset = HAND_OFFSET[side];
  if (!Array.isArray(points) || points.length < offset + 21) return null;
  const wrist = pointOf(points[offset]);
  if (!wrist) return null;

  let mask = '';
  for (const finger of FINGERS) {
    const tip = pointOf(points[offset + finger.tip]);
    const pip = pointOf(points[offset + finger.pip]);
    if (!tip || !pip) return null;
    const extended = distance(tip, wrist) > distance(pip, wrist) * EXTENSION_RATIO;
    mask += extended ? '1' : '0';
  }
  return mask;
}

function modeOf(counts) {
  let best = null;
  let bestCount = 0;
  for (const [value, count] of counts) {
    if (count > bestCount) {
      best = value;
      bestCount = count;
    }
  }
  return best;
}

function quantizeDirection(netX, netY) {
  const angle = (Math.atan2(netY, netX) * 180) / Math.PI;
  const normalized = ((angle % 360) + 360) % 360;
  const index = Math.round(normalized / 45) % 8;
  return DIRECTIONS[index];
}

/** 主轴上符号反转次数（带死区），作为“往复/摆动”的重复计数代理。 */
function countReversals(points, dominant) {
  const deadband = 0.005;
  let reversals = 0;
  let lastSign = 0;
  for (let i = 1; i < points.length; i += 1) {
    const delta =
      dominant === 'x' ? points[i].x - points[i - 1].x : points[i].y - points[i - 1].y;
    if (Math.abs(delta) < deadband) continue;
    const sign = Math.sign(delta);
    if (lastSign !== 0 && sign !== lastSign) reversals += 1;
    lastSign = sign;
  }
  return reversals;
}

/** 身体坐标系内的部位判定（肩宽归一，u 向右肩为正，v 向上为正）。 */
function classifyPlace(bodyFrame, point) {
  const origin = pointOf({ ...bodyFrame.origin, v: 1 });
  const right = pointOf({ ...bodyFrame.right, v: 1 });
  const up = pointOf({ ...bodyFrame.up, v: 1 });
  const shoulderWidth = numOrNull(bodyFrame.shoulderWidth);
  if (!origin || !right || !up || shoulderWidth === null || shoulderWidth <= 0.01) {
    return null;
  }
  const dx = point.x - origin.x;
  const dy = point.y - origin.y;
  const u = (dx * right.x + dy * right.y) / shoulderWidth;
  const v = (dx * up.x + dy * up.y) / shoulderWidth;
  if (v > 1.0) return 'head';
  if (v > 0.15) {
    if (u > 0.6) return 'shoulderR';
    if (u < -0.6) return 'shoulderL';
    return 'chest';
  }
  return 'abdomen';
}

/**
 * 段落特征。
 * @param {Array<{ts:number,hands?:object,path?:object,body?:object,nonmanual?:object}>} frames
 */
export function extractSegmentFeatures(frames) {
  const list = Array.isArray(frames) ? frames : [];
  const channels = { hands: 0, path: 0, body: 0, nonmanual: 0 };
  const spaceCounts = new Map();
  const sideCounts = { left: 0, right: 0 };

  for (const frame of list) {
    if (frame.hands && typeof frame.hands === 'object') channels.hands += 1;
    if (frame.nonmanual && typeof frame.nonmanual === 'object') channels.nonmanual += 1;
    if (frame.body && typeof frame.body === 'object') channels.body += 1;
    if (isMotionFrame(frame)) {
      channels.path += 1;
      const space = typeof frame.path.space === 'string' ? frame.path.space : 'image';
      spaceCounts.set(space, (spaceCounts.get(space) ?? 0) + 1);
      if (pathPointOf(frame.path, 'left')) sideCounts.left += 1;
      if (pathPointOf(frame.path, 'right')) sideCounts.right += 1;
    }
  }

  let space = null;
  let spaceBest = 0;
  for (const [value, count] of spaceCounts) {
    if (count > spaceBest) {
      space = value;
      spaceBest = count;
    }
  }

  const side =
    sideCounts.right > sideCounts.left ? 'right' : sideCounts.left > 0 ? 'left' : null;

  const trace = [];
  for (const frame of list) {
    if (!isMotionFrame(frame)) continue;
    const frameSpace =
      typeof frame.path.space === 'string' ? frame.path.space : 'image';
    if (space !== null && frameSpace !== space) continue;
    const point = side ? pathPointOf(frame.path, side) : null;
    if (point) trace.push({ ts: frame.ts, x: point.x, y: point.y });
  }

  let pathLength = 0;
  for (let i = 1; i < trace.length; i += 1) {
    pathLength += Math.hypot(trace[i].x - trace[i - 1].x, trace[i].y - trace[i - 1].y);
  }

  const first = trace[0] ?? null;
  const last = trace.length ? trace[trace.length - 1] : null;
  const netX = first && last ? last.x - first.x : 0;
  const netY = first && last ? last.y - first.y : 0;
  const net = Math.hypot(netX, netY);

  let direction = null;
  let shape = null;
  if (net >= 0.02) {
    direction = quantizeDirection(netX, netY);
    const ratio = pathLength / net;
    shape = ratio <= 1.3 ? 'straight' : ratio <= 2.5 ? 'arc' : 'multi';
  } else {
    shape = pathLength > 0.05 ? 'multi' : 'still';
  }

  const dominant = Math.abs(netX) >= Math.abs(netY) ? 'x' : 'y';
  const repeats = trace.length > 1 ? countReversals(trace, dominant) : 0;

  let place = null;
  const bodyFrames = list.filter(
    (frame) =>
      frame.body &&
      typeof frame.body === 'object' &&
      frame.body.frame &&
      typeof frame.body.frame === 'object',
  );
  if (space === 'body' && bodyFrames.length > 0 && last) {
    const bodyFrame = bodyFrames[bodyFrames.length - 1].body.frame;
    place = classifyPlace(bodyFrame, last);
  }

  const maskCounts = { left: new Map(), right: new Map() };
  for (const frame of list) {
    const points = frame.hands && Array.isArray(frame.hands.points) ? frame.hands.points : null;
    if (!points) continue;
    for (const handSide of ['left', 'right']) {
      const mask = handshapeMask(points, handSide);
      if (mask) maskCounts[handSide].set(mask, (maskCounts[handSide].get(mask) ?? 0) + 1);
    }
  }

  const firstTs = list.length ? list[0].ts : 0;
  const lastTs = list.length ? list[list.length - 1].ts : 0;

  return {
    sampleCount: list.length,
    pathSamples: trace.length,
    durationMs: lastTs - firstTs,
    space,
    side,
    channels,
    motion: {
      direction,
      shape,
      repeats,
      net,
      netX,
      netY,
      pathLength,
      dominant,
    },
    place,
    handshape: {
      left: modeOf(maskCounts.left),
      right: modeOf(maskCounts.right),
    },
    /** 端侧协议当前不上行接触点，故恒为 null（降级矩阵按“无接触”处理）。 */
    contactSite: null,
  };
}