import { URL } from 'node:url';
import { WebSocketServer } from 'ws';
import { extractBearer, verifyToken } from '../auth/tokens.js';
import { config } from '../config.js';
import { errorFrame, frame, sendJson } from '../protocol.js';
import {
  attachWs,
  detachWs,
  getSession,
  listActiveSessions,
  setDeviceOnline,
  stopSession,
  touchSession,
} from '../session/store.js';
import { cancelTts, createMessageHandler, deliverRecognitionResult } from './handlers.js';
import { markAlive, startHeartbeat } from './heartbeat.js';
import { RecognitionPipeline } from '../pipeline/recognition.js';

const ROLE_PATHS = {
  '/ws/app': 'app',
  '/ws/edge': 'edge',
  '/ws/wearable': 'wearable',
};

/**
 * @param {import('http').Server} server
 */
export function attachWebSocketGateway(server) {
  const wss = new WebSocketServer({ noServer: true });
  const recognition = new RecognitionPipeline({
    onResult: deliverRecognitionResult,
  });
  const handleMessage = createMessageHandler({ recognition });

  startHeartbeat(wss);

  // Idle session reaper
  const idleTimer = setInterval(() => {
    const now = Date.now();
    for (const s of listActiveSessions()) {
if (now - s.lastActivityAt > config.sessionIdleMs) {
        notifyAndCloseSession(s, 'session idle timeout');
        stopSession(s.sessionId);
        recognition.reset(s.sessionId);
        cancelTts(s.sessionId);
      }
    }
  }, 60_000);

  wss.on('close', () => clearInterval(idleTimer));

  server.on('upgrade', (req, socket, head) => {
    let pathname;
    try {
      pathname = new URL(req.url || '/', 'http://localhost').pathname;
    } catch {
      socket.destroy();
      return;
    }

    const role = ROLE_PATHS[pathname];
    if (!role) {
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      wss.emit('connection', ws, req, role);
    });
  });

  wss.on('connection', (ws, req, role) => {
    markAlive(ws);
    ws.role = role;

    let url;
    try {
      url = new URL(req.url || '/', 'http://localhost');
    } catch {
      closeWithError(ws, 'unauthorized', 'bad request url');
      return;
    }

    const deviceId = url.searchParams.get('deviceId');
    const protocolVersion = Number(url.searchParams.get('protocolVersion') || '0');
    const sessionId = url.searchParams.get('sessionId');

    if (protocolVersion !== config.protocolVersion) {
      closeWithError(ws, 'unauthorized', `protocolVersion must be ${config.protocolVersion}`);
      return;
    }

    const token = extractBearer(req.headers.authorization);
    const auth = verifyToken(token);
    if (!auth) {
      closeWithError(ws, 'unauthorized', 'invalid or expired token');
      return;
    }

    if (auth.role !== role) {
      closeWithError(ws, 'unauthorized', `token role ${auth.role} cannot connect as ${role}`);
      return;
    }

    const resolvedDeviceId = deviceId || auth.deviceId;
    ws.deviceId = resolvedDeviceId;
    ws.userId = auth.userId;
    ws.accountKey = auth.userId;

    if (role === 'app') {
      if (!sessionId) {
        closeWithError(ws, 'session_not_found', 'sessionId is required for /ws/app');
        return;
      }
      const session = getSession(sessionId);
      if (!session || session.status !== 'active') {
        closeWithError(ws, 'session_not_found', 'session not found or stopped');
        return;
      }
      if (session.accountKey !== auth.accountKey) {
        closeWithError(ws, 'unauthorized', 'session does not belong to this account');
        return;
      }

      // Replace previous app socket on same session
      if (session.appWs && session.appWs !== ws && session.appWs.readyState === 1) {
        sendJson(
          session.appWs,
          errorFrame('session_replaced', 'app connection replaced on same session', {
            sessionId,
          }),
        );
        try {
          session.appWs.close(4000, 'session_replaced');
        } catch {
          /* ignore */
        }
      }

      ws.sessionId = sessionId;
      attachWs(sessionId, 'app', ws);
      touchSession(sessionId);
setDeviceOnline(resolvedDeviceId, 'app', true, auth.userId);
      broadcastDeviceOnline(session, resolvedDeviceId, 'app', true);
      sendJson(ws, frame('session.started', { sessionId }));
    } else if (role === 'edge') {
      // Edge may attach to an active session that claimed this edgeDeviceId
      let session = null;
      if (sessionId) {
        session = getSession(sessionId);
      }
      if (!session || session.status !== 'active') {
        // Allow edge online without session for device list; landmarks need a session.
        ws.sessionId = null;
      } else {
        if (session.edgeDeviceId && session.edgeDeviceId !== resolvedDeviceId) {
          closeWithError(ws, 'unauthorized', 'edge deviceId mismatch for session');
          return;
        }
        ws.sessionId = session.sessionId;
        attachWs(session.sessionId, 'edge', ws);
        touchSession(session.sessionId);
        broadcastDeviceOnline(session, resolvedDeviceId, 'edge', true);
      }
setDeviceOnline(resolvedDeviceId, 'edge', true, auth.userId);
    } else if (role === 'wearable') {
      let session = null;
      if (sessionId) {
        session = getSession(sessionId);
      }
      if (session && session.status === 'active') {
        ws.sessionId = session.sessionId;
        attachWs(session.sessionId, 'wearable', ws);
        touchSession(session.sessionId);
        broadcastDeviceOnline(session, resolvedDeviceId, 'wearable', true);
      } else {
        ws.sessionId = null;
      }
      setDeviceOnline(resolvedDeviceId, 'wearable', true, auth.userId);
    }

    ws.on('pong', () => markAlive(ws));
    ws.on('message', (data, isBinary) => {
      if (isBinary) return; // clients do not send binary on phase-1 uplink
      handleMessage(ws, data);
    });

    ws.on('close', () => {
      setDeviceOnline(resolvedDeviceId, role, false, auth.userId);
      if (ws.sessionId) {
        const session = getSession(ws.sessionId);
        detachWs(ws.sessionId, role, ws);
        if (session) {
          broadcastDeviceOnline(session, resolvedDeviceId, role, false);
        }
      }
    });

    ws.on('error', () => {
      /* close handler cleans up */
    });
  });

  return {
    wss,
    recognition,
    notifyAndCloseSession,
  };
}

function closeWithError(ws, code, message) {
  sendJson(ws, errorFrame(code, message));
  try {
    ws.close(4001, code);
  } catch {
    ws.terminate();
  }
}

function broadcastDeviceOnline(session, deviceId, role, online) {
  const msg = frame('device.online', {
    sessionId: session.sessionId,
    deviceId,
    role,
    online,
  });
  if (session.appWs && session.appWs.readyState === 1) {
    sendJson(session.appWs, msg);
  }
}

/**
 * @param {import('../session/store.js').Session} session
 * @param {string} [reason]
 */
export function notifyAndCloseSession(session, reason = 'session stopped') {
  // 收句：停止该会话正在下发与排队的音频，避免已结束会话继续推流。
  cancelTts(session.sessionId);

  const stopped = frame('session.stopped', {
    sessionId: session.sessionId,
    reason,
  });
  for (const sock of [session.appWs, session.edgeWs, session.wearableWs]) {
    if (sock && sock.readyState === 1) {
      sendJson(sock, stopped);
      try {
        sock.close(1000, 'session_stopped');
      } catch {
        sock.terminate();
      }
    }
  }
}
