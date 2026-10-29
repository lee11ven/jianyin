import http from 'node:http';
import express from 'express';
import { config } from './config.js';
import { createRestRouter } from './rest/routes.js';
import { attachWebSocketGateway, notifyAndCloseSession } from './ws/gateway.js';

const app = express();
app.use(express.json({ limit: '1mb' }));

const server = http.createServer(app);

const { recognition } = attachWebSocketGateway(server);

app.use(
  createRestRouter({
    onSessionReplaced: (_sessionId, ws) => {
      try {
        ws.close(4000, 'session_replaced');
      } catch {
        ws.terminate();
      }
    },
    onSessionStopped: (session) => {
      if (!session) return;
      recognition.reset(session.sessionId);
      notifyAndCloseSession(session, 'stopped via REST');
    },
  }),
);

app.use((err, _req, res, _next) => {
  console.error(err);
  res.status(500).json({ code: 'internal', message: 'internal error' });
});

server.listen(config.port, config.host, () => {
  console.log(
    `[gateway] listening on http://${config.host}:${config.port} (ws://<lan-ip>:${config.port}/ws/app)`,
  );
  console.log(`[gateway] env=${config.nodeEnv} protocolVersion=${config.protocolVersion}`);
});
