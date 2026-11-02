import { frame, sendJson } from '../protocol.js';
import { appendHistory } from '../session/history.js';
import { appendUserHistory } from '../auth/user_history.js';
import { getSession, touchSession } from '../session/store.js';
import { TtsDispatcher, wsTarget } from '../pipeline/tts_queue.js';
import { markAlive } from './heartbeat.js';

/** 流式 TTS 调度器：按 `utteranceId` 串行、首包立即下发、背压丢最旧未发送片。 */
const ttsDispatcher = new TtsDispatcher();

/** 会话结束 / 被替换时清空该会话的 TTS 队列（由 gateway / REST 停止路径调用）。 */
export function cancelTts(sessionId) {
  ttsDispatcher.cancel(sessionId);
}

const ENVELOPE_ID = 'gesture_skeleton_envelope_v1';

/**
 * Pretty-print App uplink envelopes / landmarks to the gateway console.
 * @param {import('ws').WebSocket} ws
 * @param {object} msg
 */
function logAppEnvelope(ws, msg) {
  const role = ws.role || 'unknown';
  if (role !== 'app') return;

  const sid = ws.sessionId || msg.sessionId || '-';
  const envelope = msg.envelope;
  const kind = msg.kind;
  const type = msg.type;

  // Wire format is compact JSON (no whitespace); log the same way.
  if (envelope === ENVELOPE_ID) {
    console.log(
      `[ws/app] envelope sid=${sid} kind=${kind || '?'} ts=${msg.ts ?? '-'} ${JSON.stringify(msg)}`,
    );
    return;
  }

  if (type === 'landmarks') {
    console.log(
      `[ws/app] landmarks sid=${sid} ts=${msg.ts ?? '-'} schema=${msg.schema || '?'} ${JSON.stringify(msg)}`,
    );
  }
}

/**
 * @param {object} deps
 * @param {import('../pipeline/recognition.js').RecognitionPipeline} deps.recognition
 */
export function createMessageHandler({ recognition }) {
  return function handleMessage(ws, raw) {
    markAlive(ws);

    let msg;
    try {
      msg = JSON.parse(typeof raw === 'string' ? raw : raw.toString('utf8'));
    } catch {
      sendJson(ws, frame('error', { code: 'internal', message: 'invalid JSON' }));
      return;
    }

    const type = msg?.type;
    const isEnvelope = msg?.envelope === ENVELOPE_ID;

    if (type === 'ping') {
      sendJson(ws, frame('pong', { sessionId: ws.sessionId }));
      return;
    }

    if (ws.sessionId) {
      touchSession(ws.sessionId);
    }

    // Catalog / frame envelopes have no `type`; landmarks use type=landmarks.
    if (isEnvelope || type === 'landmarks') {
      logAppEnvelope(ws, msg);
    }

    if (isEnvelope) {
      // Accepted for logging / future recognition; no mock emit.
      return;
    }

    if (!type) return;

    if (type === 'landmarks') {
      if (!ws.sessionId) return;
      const session = getSession(ws.sessionId);
      if (!session || session.status !== 'active') {
        sendJson(ws, frame('error', { code: 'session_not_found', message: 'session inactive' }));
        return;
      }
      recognition.ingest(ws.sessionId, msg);
      return;
    }

    if (type === 'device.status') {
      // Accepted from edge/wearable; activity already touched above.
      return;
    }

    // Phase-1 App must not send session.start/stop; ignore if received.
    if (type === 'session.start' || type === 'session.stop') {
      return;
    }
  };
}

/**
 * Fan out recognition + streaming TTS to app / wearable sockets.
 */
export function deliverRecognitionResult(result) {
  const session = getSession(result.sessionId);
  if (!session || session.status !== 'active') return;

  appendHistory(result.sessionId, {
    utteranceId: result.utteranceId,
    text: result.text,
    confidence: result.confidence,
    glossIds: result.glossIds,
    ts: result.ts,
  });

  if (session.accountKey) {
    appendUserHistory(session.accountKey, {
      utteranceId: result.utteranceId,
      text: result.text,
      confidence: result.confidence,
      glossIds: result.glossIds,
      ts: result.ts,
      sessionId: result.sessionId,
    });
  }

  const recognitionMsg = frame('recognition', {
    sessionId: result.sessionId,
    utteranceId: result.utteranceId,
    text: result.text,
    confidence: result.confidence,
    glossIds: result.glossIds,
    vocabVersion: result.vocabVersion,
  });

const sockets = [session.appWs, session.wearableWs].filter(
    (sock) => sock && sock.readyState === 1,
  );

  // 字幕立即下发，不等音频。
  for (const socket of sockets) {
    sendJson(socket, recognitionMsg);
  }

  if (sockets.length === 0) return;

  // 音频交给调度器：按 utteranceId 串行、边合成边下发、背压丢片。
  ttsDispatcher.enqueue({
    sessionId: result.sessionId,
    utteranceId: result.utteranceId,
    text: result.text,
    targets: sockets.map((socket) => wsTarget(socket)),
  });
}
