import { frame, sendBinary, sendJson } from '../protocol.js';
import { appendHistory } from '../session/history.js';
import { appendUserHistory } from '../auth/user_history.js';
import { getSession, touchSession } from '../session/store.js';
import { synthesizePcmChunks } from '../pipeline/tts.js';
import { markAlive } from './heartbeat.js';

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

  const targets = [session.appWs, session.wearableWs].filter(
    (s) => s && s.readyState === 1,
  );

  for (const target of targets) {
    sendJson(target, recognitionMsg);
  }

  const { mimeType, sampleRate, channels, encoding, chunks } = synthesizePcmChunks(result.text);

  const speechMeta = frame('speech', {
    sessionId: result.sessionId,
    utteranceId: result.utteranceId,
    text: result.text,
    delivery: 'ws_binary_audio',
    mimeType,
    sampleRate,
    channels,
    encoding,
  });

  for (const target of targets) {
    sendJson(target, speechMeta);
  }

  for (let seq = 0; seq < chunks.length; seq++) {
    const last = seq === chunks.length - 1;
    const header = frame('audio.header', {
      sessionId: result.sessionId,
      utteranceId: result.utteranceId,
      seq,
      mimeType,
      sampleRate,
      channels,
      encoding,
      last,
    });
    for (const target of targets) {
      sendJson(target, header);
      sendBinary(target, chunks[seq]);
    }
  }

  // Ensure last:true even if empty (protocol allows empty binary on last)
  if (chunks.length === 0) {
    const header = frame('audio.header', {
      sessionId: result.sessionId,
      utteranceId: result.utteranceId,
      seq: 0,
      mimeType,
      sampleRate,
      channels,
      encoding,
      last: true,
    });
    for (const target of targets) {
      sendJson(target, header);
      sendBinary(target, Buffer.alloc(0));
    }
  }
}
