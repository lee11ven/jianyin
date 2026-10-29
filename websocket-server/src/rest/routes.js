import { Router } from 'express';
import { config, isDebugBuild } from '../config.js';
import {
  authenticateAccount,
  findUserById,
  registerAccount,
  toPublicUser,
  updateUserProfile,
} from '../auth/accounts.js';
import {
  getMembership,
  listPlans,
  planInfoForUser,
  subscribe,
} from '../auth/membership.js';
import { listUserHistoryDays } from '../auth/user_history.js';
import { extractBearer, issueDemoToken, issueToken, verifyToken } from '../auth/tokens.js';
import {
  buildWsUrl,
  createSession,
  getSession,
  getSessionPublic,
  listDevices,
  stopSession,
} from '../session/store.js';
import { getHistory } from '../session/history.js';
import { errorFrame, sendJson } from '../protocol.js';
import { gesturesCatalog } from '../data/gestures.js';

function requireAuth(req, res, next) {
  const token = extractBearer(req.get('authorization'));
  const record = verifyToken(token);
  if (!record) {
    return res.status(401).json({ code: 'unauthorized', message: 'invalid or expired token' });
  }
  req.auth = record;
  next();
}

function sendAuthError(res, err) {
  res.status(err.status || 400).json({
    code: err.code || 'bad_request',
    message: err.message,
  });
}

function tokenForUser(user, deviceId) {
  const planInfo = planInfoForUser(user.userId);
  return issueToken({
    userId: user.userId,
    username: user.username,
    phone: user.phone,
    sex: user.sex,
    role: 'app',
    deviceId,
    plan: planInfo.plan,
  });
}

/**
 * @param {{ onSessionReplaced?: (sessionId: string, ws: import('ws').WebSocket) => void, onSessionStopped?: (session: import('../session/store.js').Session) => void }} hooks
 */
export function createRestRouter(hooks = {}) {
  const router = Router();

  router.get('/health', (_req, res) => {
    res.json({ status: 'ok', protocolVersion: config.protocolVersion });
  });

  router.post('/api/v1/auth/register', (req, res) => {
    try {
      const { phone, password, username, sex, deviceId } = req.body || {};
      const account = registerAccount({ phone, password, username, sex });
      res.status(201).json(tokenForUser(account, deviceId));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  router.post('/api/v1/auth/login', (req, res) => {
    try {
      const { phone, password, deviceId } = req.body || {};
      const account = authenticateAccount({ phone, password });
      res.json(tokenForUser(account, deviceId));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  router.post('/api/v1/auth/demo-token', (req, res) => {
    if (!isDebugBuild()) {
      return res.status(404).json({ code: 'not_found', message: 'demo-token disabled in production' });
    }
    try {
      const { role = 'app', deviceId } = req.body || {};
      res.json(issueDemoToken({ role, deviceId }));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  router.get('/api/v1/me', requireAuth, (req, res) => {
    const user = findUserById(req.auth.userId);
    if (!user) {
      // demo-token users may not be in users.json
      return res.json({
        userId: req.auth.userId,
        username: req.auth.username,
        phone: req.auth.phone,
        sex: req.auth.sex,
        ...planInfoForUser(req.auth.userId),
      });
    }
    res.json(toPublicUser(user, planInfoForUser(user.userId)));
  });

  router.patch('/api/v1/me', requireAuth, (req, res) => {
    try {
      const { username, sex } = req.body || {};
      let user = findUserById(req.auth.userId);
      if (!user) {
        return res.status(404).json({ code: 'not_found', message: 'user not found' });
      }
      user = updateUserProfile(req.auth.userId, { username, sex });
      res.json(toPublicUser(user, planInfoForUser(user.userId)));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  router.get('/api/v1/history', requireAuth, (req, res) => {
    const from = typeof req.query.from === 'string' ? req.query.from : undefined;
    const to = typeof req.query.to === 'string' ? req.query.to : undefined;
    const days = listUserHistoryDays(req.auth.userId, { from, to });
    res.json({ days });
  });

  router.get('/api/v1/membership/plans', requireAuth, (_req, res) => {
    res.json({ plans: listPlans() });
  });

  router.get('/api/v1/membership', requireAuth, (req, res) => {
    res.json(getMembership(req.auth.userId));
  });

  router.post('/api/v1/membership/subscribe', requireAuth, (req, res) => {
    try {
      const { planId } = req.body || {};
      res.json(subscribe(req.auth.userId, planId));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  router.get('/api/v1/devices', requireAuth, (_req, res) => {
    res.json({ devices: listDevices() });
  });

  router.get('/api/v1/gestures', requireAuth, (_req, res) => {
    res.json(gesturesCatalog);
  });

  router.post('/api/v1/sessions', requireAuth, (req, res) => {
    try {
      const { edgeDeviceId, usePhoneLandmarks = true } = req.body || {};
      const { session, replacedSessionId } = createSession({
        accountKey: req.auth.userId,
        edgeDeviceId,
        usePhoneLandmarks,
      });

      if (replacedSessionId) {
        const old = getSession(replacedSessionId);
        if (old?.appWs) {
          sendJson(
            old.appWs,
            errorFrame('session_replaced', 'a newer app session was created', {
              sessionId: replacedSessionId,
            }),
          );
          hooks.onSessionReplaced?.(replacedSessionId, old.appWs);
        }
        if (old && old.status === 'active') {
          stopSession(replacedSessionId);
          hooks.onSessionStopped?.(old);
        }
      }

      res.status(201).json({
        sessionId: session.sessionId,
        protocolVersion: config.protocolVersion,
        wsUrl: buildWsUrl(req, '/ws/app'),
      });
    } catch (err) {
      res.status(err.status || 500).json({
        code: err.code || 'internal',
        message: err.message,
      });
    }
  });

  router.get('/api/v1/sessions/:id', requireAuth, (req, res) => {
    const session = getSession(req.params.id);
    if (!session) {
      return res.status(404).json({ code: 'session_not_found', message: 'session not found' });
    }
    if (session.accountKey !== req.auth.userId && req.auth.role === 'app') {
      return res.status(403).json({ code: 'unauthorized', message: 'session belongs to another account' });
    }
    res.json(getSessionPublic(session));
  });

  router.post('/api/v1/sessions/:id/stop', requireAuth, (req, res) => {
    const session = getSession(req.params.id);
    if (!session) {
      return res.status(404).json({ code: 'session_not_found', message: 'session not found' });
    }
    if (session.accountKey !== req.auth.userId && req.auth.role === 'app') {
      return res.status(403).json({ code: 'unauthorized', message: 'session belongs to another account' });
    }
    const stopped = stopSession(session.sessionId);
    hooks.onSessionStopped?.(stopped);
    res.json({ sessionId: session.sessionId, status: 'stopped' });
  });

  router.get('/api/v1/sessions/:id/history', requireAuth, (req, res) => {
    const session = getSession(req.params.id);
    if (!session) {
      return res.status(404).json({ code: 'session_not_found', message: 'session not found' });
    }
    if (session.accountKey !== req.auth.userId && req.auth.role === 'app') {
      return res.status(403).json({ code: 'unauthorized', message: 'session belongs to another account' });
    }
    res.json({ sessionId: session.sessionId, history: getHistory(session.sessionId) });
  });

  return router;
}
