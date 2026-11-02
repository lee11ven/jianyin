import http from 'node:http';
import express from 'express';
import { assertSecureConfig, config, isLlmEnabled } from './config.js';
import { createRestRouter } from './rest/routes.js';
import { mountSwagger } from './swagger/setup.js';
import { attachWebSocketGateway, notifyAndCloseSession } from './ws/gateway.js';
import { cancelTts } from './ws/handlers.js';

// 启动即校验配置（production 下默认 JWT 密钥直接失败）。
assertSecureConfig();

const app = express();
app.use(express.json({ limit: '1mb' }));

const server = http.createServer(app);

const { recognition } = attachWebSocketGateway(server);

mountSwagger(app);

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
  console.log(`[gateway] swagger UI http://${config.host}:${config.port}/docs`);
  console.log(`[gateway] env=${config.nodeEnv} protocolVersion=${config.protocolVersion}`);
  if (isLlmEnabled()) {
    console.log(
      `[gateway] llm=${config.llm.provider || 'custom'} model=${config.llm.model} base=${config.llm.apiBase}`,
    );
  } else {
    console.log('[gateway] llm=off (set LLM_API_KEY to enable sign→Chinese translation)');
  }
});
