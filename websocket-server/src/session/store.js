import { randomBytes } from 'node:crypto';
import { config } from '../config.js';
import { clearHistory } from './history.js';

/**
 * @typedef {{
 *   sessionId: string,
 *   accountKey: string,
 *   edgeDeviceId: string | null,
 *   usePhoneLandmarks: boolean,
 *   status: 'active' | 'stopped',
 *   createdAt: number,
 *   lastActivityAt: number,
 *   appWs: import('ws').WebSocket | null,
 *   edgeWs: import('ws').WebSocket | null,
 *   wearableWs: import('ws').WebSocket | null,
 * }} Session
 */

/** @type {Map<string, Session>} */
const sessions = new Map();

/** accountKey -> sessionId (latest app session) */
const accountSessions = new Map();

/** edgeDeviceId -> sessionId */
const edgeBusy = new Map();

/** deviceId -> { deviceId, role, online, lastSeen } */
const devices = new Map();

function newSessionId() {
  return `sess-${randomBytes(8).toString('hex')}`;
}

export function listDevices() {
  return Array.from(devices.values());
}

export function setDeviceOnline(deviceId, role, online) {
  const prev = devices.get(deviceId) || { deviceId, role, online: false, lastSeen: 0 };
  devices.set(deviceId, {
    ...prev,
    role,
    online,
    lastSeen: Date.now(),
  });
}

/**
 * @param {{ accountKey: string, edgeDeviceId?: string, usePhoneLandmarks?: boolean }} opts
 * @returns {{ session: Session, replacedSessionId: string | null }}
 */
export function createSession({ accountKey, edgeDeviceId, usePhoneLandmarks = true }) {
  const edgeId = edgeDeviceId || null;

  if (edgeId) {
    const busySid = edgeBusy.get(edgeId);
    if (busySid) {
      const busy = sessions.get(busySid);
      if (busy && busy.status === 'active') {
        const err = new Error('edge device is busy');
        err.status = 409;
        err.code = 'device_busy';
        throw err;
      }
      edgeBusy.delete(edgeId);
    }
  }

  let replacedSessionId = null;
  const prevSid = accountSessions.get(accountKey);
  if (prevSid) {
    const prev = sessions.get(prevSid);
    if (prev && prev.status === 'active') {
      replacedSessionId = prevSid;
    }
  }

  const sessionId = newSessionId();
  const now = Date.now();
  /** @type {Session} */
  const session = {
    sessionId,
    accountKey,
    edgeDeviceId: edgeId,
    usePhoneLandmarks: Boolean(usePhoneLandmarks),
    status: 'active',
    createdAt: now,
    lastActivityAt: now,
    appWs: null,
    edgeWs: null,
    wearableWs: null,
  };

  sessions.set(sessionId, session);
  accountSessions.set(accountKey, sessionId);
  if (edgeId) {
    edgeBusy.set(edgeId, sessionId);
  }

  return { session, replacedSessionId };
}

export function getSession(sessionId) {
  return sessions.get(sessionId) || null;
}

export function touchSession(sessionId) {
  const s = sessions.get(sessionId);
  if (s) s.lastActivityAt = Date.now();
}

/**
 * @param {string} sessionId
 * @param {'app' | 'edge' | 'wearable'} role
 * @param {import('ws').WebSocket | null} ws
 */
export function attachWs(sessionId, role, ws) {
  const s = sessions.get(sessionId);
  if (!s) return null;
  if (role === 'app') s.appWs = ws;
  else if (role === 'edge') s.edgeWs = ws;
  else if (role === 'wearable') s.wearableWs = ws;
  s.lastActivityAt = Date.now();
  return s;
}

/**
 * @param {string} sessionId
 * @param {'app' | 'edge' | 'wearable'} role
 * @param {import('ws').WebSocket} ws
 */
export function detachWs(sessionId, role, ws) {
  const s = sessions.get(sessionId);
  if (!s) return;
  if (role === 'app' && s.appWs === ws) s.appWs = null;
  if (role === 'edge' && s.edgeWs === ws) s.edgeWs = null;
  if (role === 'wearable' && s.wearableWs === ws) s.wearableWs = null;
}

export function stopSession(sessionId) {
  const s = sessions.get(sessionId);
  if (!s) return null;
  s.status = 'stopped';
  s.lastActivityAt = Date.now();
  if (s.edgeDeviceId && edgeBusy.get(s.edgeDeviceId) === sessionId) {
    edgeBusy.delete(s.edgeDeviceId);
  }
  if (accountSessions.get(s.accountKey) === sessionId) {
    accountSessions.delete(s.accountKey);
  }
  return s;
}

export function removeSession(sessionId) {
  const s = stopSession(sessionId);
  if (!s) return;
  sessions.delete(sessionId);
  clearHistory(sessionId);
}

export function buildWsUrl(req, path = '/ws/app') {
  const host = req.get('host') || `localhost:${config.port}`;
  const xfProto = req.get('x-forwarded-proto');
  const proto = xfProto === 'https' ? 'wss' : 'ws';
  return `${proto}://${host}${path}`;
}

export function getSessionPublic(session) {
  return {
    sessionId: session.sessionId,
    status: session.status,
    edgeDeviceId: session.edgeDeviceId,
    usePhoneLandmarks: session.usePhoneLandmarks,
    createdAt: session.createdAt,
    lastActivityAt: session.lastActivityAt,
    connections: {
      app: Boolean(session.appWs && session.appWs.readyState === 1),
      edge: Boolean(session.edgeWs && session.edgeWs.readyState === 1),
      wearable: Boolean(session.wearableWs && session.wearableWs.readyState === 1),
    },
  };
}

export function listActiveSessions() {
  return Array.from(sessions.values()).filter((s) => s.status === 'active');
}
