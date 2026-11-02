import http from 'node:http';
import express from 'express';
import { assertSecureConfig, config } from './config.js';
import { createRestRouter } from './rest/routes.js';
import { attachWebSocketGateway, notifyAndCloseSession } from './ws/gateway.js';
import { cancelTts } from './ws/handlers.js';

// 启动即校验配置（production 下默认 JWT 密钥直接失败）。
assertSecureConfig();

const app = express();
app.use(express.json({ limit: '1mb' }));

const server = http.createServer(app);

const { recognition } = attachWebSocketGateway(server);

app.use(
  createRestRouter({
onSessionReplaced: (replacedSessionId, ws) => {
      cancelTts(replacedSessionId);
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
