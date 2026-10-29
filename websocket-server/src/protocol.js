import { config } from './config.js';

export function nowTs() {
  return Date.now();
}

export function frame(type, extra = {}) {
  return {
    type,
    protocolVersion: config.protocolVersion,
    ts: nowTs(),
    ...extra,
  };
}

export function errorFrame(code, message, extra = {}) {
  return frame('error', { code, message, ...extra });
}

export function sendJson(ws, payload) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(payload));
  }
}

export function sendBinary(ws, buffer) {
  if (ws.readyState === 1) {
    ws.send(buffer, { binary: true });
  }
}
