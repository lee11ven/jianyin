#!/usr/bin/env node
/**
 * 网关并发/延迟压测（可复现）。
 *
 * 用法：
 *   node scripts/load-test.mjs [--sessions 50] [--seconds 10] [--url http://127.0.0.1:8000]
 *
 * 行为：为每个并发会话取 demo-token → 建会话 → 连 /ws/app → 以 25 Hz 上行
 * `csl_channels_v1` 摆动帧 → 统计「上行 sentAt → 收到 recognition/audio.header」
 * 的延迟分布与吞吐；结束时输出 JSON 摘要（供 docs/reports/scalability.md 引用）。
 *
 * 说明：本脚本对**本机网关**施压，用于容量口径；生产压测需在同规格环境复跑。
 */
import { setTimeout as delay } from 'node:timers/promises';
import WebSocket from 'ws';

function arg(name, fallback) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const BASE = arg('url', 'http://127.0.0.1:8000');
const SESSIONS = Number(arg('sessions', '50'));
const SECONDS = Number(arg('seconds', '10'));

function point(x, y, v = 1) {
  return { x, y, z: 0, v };
}

function hands42(mask = '11111') {
  const points = new Array(42).fill(null).map(() => point(0.5, 0.5, 1));
  const tips = [4, 8, 12, 16, 20];
  const pips = [3, 6, 10, 14, 18];
  for (const offset of [0, 21]) {
    points[offset] = point(0.5, 0.5, 1);
    tips.forEach((tipIndex, i) => {
      points[offset + tipIndex] = mask[i] === '1' ? point(0.72, 0.5, 1) : point(0.55, 0.5, 1);
      points[offset + pips[i]] = point(0.6, 0.5, 1);
    });
  }
  return points;
}

const WAVE = [0.3, 0.45, 0.6, 0.45, 0.3, 0.45, 0.6, 0.45, 0.3];

async function post(path, body, token) {
  const res = await fetch(`${BASE}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body ?? {}),
  });
  return { status: res.status, json: await res.json() };
}

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const idx = Math.min(sorted.length - 1, Math.floor((p / 100) * sorted.length));
  return sorted[idx];
}

async function runSession(index) {
  const token = (await post('/api/v1/auth/demo-token', { role: 'app', deviceId: `load-${index}` })).json.token;
  const session = (await post('/api/v1/sessions', { usePhoneLandmarks: true }, token)).json;
  // 握手地址：主机/端口取压测目标，路径固定 /ws/app，并按协议带上 query。
  const base = new URL(BASE);
  const wsUrl =
    `ws://${base.host}/ws/app?deviceId=load-${index}&protocolVersion=1&sessionId=${session.sessionId}`;
  const ws = new WebSocket(wsUrl, { headers: { Authorization: `Bearer ${token}` } });

  const stats = { sent: 0, recognition: 0, headers: 0, binaryBytes: 0, latencies: [], firstPacketMs: null };
  let pendingSentAt = new Map();

  ws.on('message', (raw, isBinary) => {
    if (isBinary) {
      stats.binaryBytes += raw.length;
      return;
    }
    const msg = JSON.parse(raw.toString('utf8'));
    if (msg.type === 'recognition' || msg.type === 'audio.header') {
      stats.recognition += msg.type === 'recognition' ? 1 : 0;
      stats.headers += msg.type === 'audio.header' ? 1 : 0;
      const sentAt = pendingSentAt.get('last');
      if (sentAt) {
        const latency = Date.now() - sentAt;
        stats.latencies.push(latency);
        if (msg.type === 'audio.header' && stats.firstPacketMs === null) stats.firstPacketMs = latency;
      }
    }
  });

  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });

  const deadline = Date.now() + SECONDS * 1000;
  let tick = 0;
  while (Date.now() < deadline) {
    const x = WAVE[tick % WAVE.length];
    const ts = Date.now();
    ws.send(
      JSON.stringify({
        type: 'landmarks',
        protocolVersion: 1,
        ts,
        sessionId: session.sessionId,
        schema: 'csl_channels_v1',
        hands: { schema: 'mediapipe_hands_v1', points: hands42('11111') },
        path: {
          space: 'image',
          anchor: false,
          gap: false,
          left: { wrist: point(x, 0.5), palm: point(x, 0.5), tips: {} },
          right: { wrist: point(0, 0, 0), palm: point(0, 0, 0), tips: {} },
        },
      }),
    );
    pendingSentAt.set('last', ts);
    stats.sent += 1;
    tick += 1;
    await delay(40);
  }

  ws.close();
  return stats;
}

const started = Date.now();
const all = await Promise.all(
  Array.from({ length: SESSIONS }, (_unused, index) => runSession(index)),
);
const elapsedSec = (Date.now() - started) / 1000;
const latencies = all.flatMap((s) => s.latencies).sort((a, b) => a - b);
const firstPackets = all.map((s) => s.firstPacketMs).filter((v) => v !== null).sort((a, b) => a - b);

const summary = {
  url: BASE,
  sessions: SESSIONS,
  secondsTarget: SECONDS,
  elapsedSec: Number(elapsedSec.toFixed(2)),
  uplinkMessages: all.reduce((sum, s) => sum + s.sent, 0),
  uplinkRatePerSec: Number((all.reduce((sum, s) => sum + s.sent, 0) / elapsedSec).toFixed(1)),
  recognitions: all.reduce((sum, s) => sum + s.recognition, 0),
  audioHeaders: all.reduce((sum, s) => sum + s.headers, 0),
  audioBytes: all.reduce((sum, s) => sum + s.binaryBytes, 0),
  measuredLatencies: latencies.length,
  latencyMs: {
    p50: percentile(latencies, 50),
    p95: percentile(latencies, 95),
    max: latencies.length ? latencies[latencies.length - 1] : null,
  },
  ttsFirstPacketMs: {
    p50: percentile(firstPackets, 50),
    p95: percentile(firstPackets, 95),
    samples: firstPackets.length,
  },
  sessionsWithAudio: all.filter((s) => s.headers > 0).length,
};

console.log(JSON.stringify(summary, null, 2));