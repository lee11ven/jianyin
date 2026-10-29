import { config } from '../config.js';

/**
 * Track last activity; periodically ping and close dead sockets.
 * @param {import('ws').WebSocketServer} wss
 */
export function startHeartbeat(wss) {
  const interval = setInterval(() => {
    for (const ws of wss.clients) {
      if (ws.isAlive === false) {
        ws.terminate();
        continue;
      }
      const last = ws.lastActivityAt || 0;
      if (Date.now() - last > config.deadConnectionMs) {
        ws.terminate();
        continue;
      }
      ws.isAlive = false;
      try {
        ws.ping();
      } catch {
        ws.terminate();
      }
    }
  }, config.heartbeatIntervalMs);

  wss.on('close', () => clearInterval(interval));
  return interval;
}

export function markAlive(ws) {
  ws.isAlive = true;
  ws.lastActivityAt = Date.now();
}
