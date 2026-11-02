import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import WebSocket from 'ws';

/**
 * 端到端冒烟：真实起网关 → 建会话 → 连 `/ws/app` → 上行 `csl_channels_v1`
 * → 断言「识别 + 流式 TTS（audio.header + 二进制 PCM）」闭环与开声延迟。
 *
 * 覆盖设计口径：`recognition` 字段、`speech` / `audio.header` 时序、按
 * `utteranceId` 串行、首包不等整句（见 docs/design/系统架构/architecture.md）。
 */
const SERVER_DIR = join(dirname(fileURLToPath(import.meta.url)), '..');
const PORT = 8199;

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
      points[offset + tipIndex] =
        mask[i] === '1' ? point(0.72, 0.5, 1) : point(0.55, 0.5, 1);
      points[offset + pips[i]] = point(0.6, 0.5, 1);
    });
  }
  return points;
}

function landmarks(ts, x, sessionId) {
  return {
    type: 'landmarks',
    protocolVersion: 1,
    ts,
    sessionId,
    schema: 'csl_channels_v1',
    hands: { schema: 'mediapipe_hands_v1', points: hands42('11111') },
    path: {
      space: 'image',
      anchor: false,
      gap: false,
      left: { wrist: point(x, 0.5), palm: point(x, 0.5), tips: {} },
      right: { wrist: point(0, 0, 0), palm: point(0, 0, 0), tips: {} },
    },
  };
}

async function waitForHealth() {
  for (let i = 0; i < 60; i += 1) {
    try {
      const res = await fetch(`http://127.0.0.1:${PORT}/health`);
      if (res.ok) return;
    } catch {
      /* 未就绪 */
    }
    await delay(150);
  }
  throw new Error('gateway did not become healthy');
}

async function post(path, body, token) {
  const res = await fetch(`http://127.0.0.1:${PORT}${path}`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify(body ?? {}),
  });
  return { status: res.status, json: await res.json() };
}

test('端到端：上行手语 → recognition → speech + audio.header + PCM', async (t) => {
  const server = spawn(process.execPath, ['src/index.js'], {
    cwd: SERVER_DIR,
    env: { ...process.env, PORT: String(PORT), HOST: '127.0.0.1', NODE_ENV: 'development' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  t.after(() => server.kill());

  await waitForHealth();

  const demo = await post('/api/v1/auth/demo-token', { role: 'app', deviceId: 'e2e-app' });
  assert.equal(demo.status, 200);
  const token = demo.json.token;
  assert.ok(token);

  const created = await post('/api/v1/sessions', { usePhoneLandmarks: true }, token);
  assert.equal(created.status, 201);
  const { sessionId } = created.json;

  const ws = new WebSocket(
    `ws://127.0.0.1:${PORT}/ws/app?deviceId=e2e-app&protocolVersion=1&sessionId=${sessionId}`,
    { headers: { Authorization: `Bearer ${token}` } },
  );

  const events = { recognition: [], speech: [], headers: [], binary: 0, binaryBytes: 0 };
  let lastUplinkTs = 0;
  let firstHeaderAt = 0;

  ws.on('message', (raw, isBinary) => {
    if (isBinary) {
      events.binary += 1;
      events.binaryBytes += raw.length;
      return;
    }
    const msg = JSON.parse(raw.toString('utf8'));
    if (msg.type === 'recognition') events.recognition.push(msg);
    if (msg.type === 'speech') events.speech.push(msg);
    if (msg.type === 'audio.header') {
      events.headers.push(msg);
      if (!firstHeaderAt) firstHeaderAt = Date.now();
    }
  });

  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });

  // 9 帧摆动（≥ recognitionMinFrames=8，时长 ≥ 200 ms），随后一帧 gap 收段。
  const xs = [0.3, 0.45, 0.6, 0.45, 0.3, 0.45, 0.6, 0.45, 0.3];
  let ts = Date.now();
  for (const x of xs) {
    ts += 40;
    lastUplinkTs = ts;
    ws.send(JSON.stringify(landmarks(ts, x, sessionId)));
    await delay(40);
  }
  const gapTs = ts + 300;
  ws.send(
    JSON.stringify({
      type: 'landmarks',
      protocolVersion: 1,
      ts: gapTs,
      sessionId,
      schema: 'csl_channels_v1',
      path: { space: 'image', anchor: false, gap: true },
    }),
  );

  const deadline = Date.now() + 4000;
  while (Date.now() < deadline) {
    if (events.headers.some((h) => h.last === true)) break;
    await delay(50);
  }

  assert.equal(events.recognition.length, 1, '应产出且仅产出一条 recognition');
  assert.equal(events.recognition[0].text, '你好');
  assert.deepEqual(events.recognition[0].glossIds, ['hello']);
  assert.equal(events.recognition[0].sessionId, sessionId);
  assert.ok(events.recognition[0].vocabVersion);

  assert.equal(events.speech.length, 1, '每句一条 speech 元数据');
  assert.equal(events.speech[0].delivery, 'ws_binary_audio');
  assert.equal(events.speech[0].sampleRate, 16000);
  assert.equal(events.speech[0].encoding, 's16le');

  assert.ok(events.headers.length >= 2, 'PCM 应分成多个 100 ms 片');
  assert.equal(events.headers.at(-1).last, true, '末片必须 last:true');
  assert.ok(events.binary >= 2, '应有二进制音频帧');
  assert.ok(events.binaryBytes > 1600 * 2, '音频字节数应超过单片的 100 ms');
  // seq 连续（正式路径按序下发）
  events.headers.forEach((header, index) => {
    if (header.last) return;
    assert.equal(header.seq, index);
  });

  // 开声延迟：最后一次上行 → 首个 audio.header
  const latency = firstHeaderAt - lastUplinkTs;
  assert.ok(latency >= 0 && latency < 1500, `开声延迟应 < 1.5 s，实际 ${latency} ms`);

  ws.close();
  await delay(100);
});