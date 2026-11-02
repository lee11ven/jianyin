import { Router } from 'express';
import { config, isDebugBuild } from '../config.js';
import {
  assertValidPhone,
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
import {
  extractBearer,
  issueDemoToken,
  issueToken,
  verifyToken,
} from '../auth/tokens.js';
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
import {
  storeOtp,
  verifyOtp as verifyOtpEntry,
} from '../auth/otp_store.js';

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

  // ---- OTP (短信验证码) ----

  /**
   * POST /api/v1/auth/send-otp
   * Body: { phone: string }
   * Response: { sent: true, phone } ; in non-production also includes `code`.
   */
  router.post('/api/v1/auth/send-otp', (req, res) => {
    try {
      const { phone } = req.body || {};
      if (!phone || typeof phone !== 'string') {
        return res.status(400).json({ code: 'bad_request', message: 'phone is required' });
      }
      const normalized = assertValidPhone(phone);
      const code = storeOtp(normalized);
      const payload = { sent: true, phone: normalized };
      if (isDebugBuild()) {
        payload.code = code;
        console.log(`[otp] ${normalized} => ${code}`);
      }
      res.json(payload);
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  /**
   * POST /api/v1/auth/verify-otp
   * Body: { phone: string, code: string }
   * Response: { valid: true } on success
   */
  router.post('/api/v1/auth/verify-otp', (req, res) => {
    try {
      const { phone, code } = req.body || {};
      if (!phone || !code) {
        return res.status(400).json({ code: 'bad_request', message: 'phone and code are required' });
      }
      const ok = verifyOtpEntry(phone.trim(), String(code).trim());
      if (!ok) {
        return res.status(400).json({
          code: 'invalid_otp',
          message: '验证码不正确或已过期，请重新获取',
        });
      }
      res.json({ valid: true, phone: phone.trim() });
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  // ---- Account ----

  /**
   * POST /api/v1/auth/register
   * Body: { phone, password, code, deviceId? }
   * Requires a valid OTP for the phone number (sent via send-otp).
   */
  router.post('/api/v1/auth/register', (req, res) => {
    try {
      const { phone, password, code, deviceId } = req.body || {};
      if (!phone || !password || !code) {
        return res.status(400).json({
          code: 'bad_request',
          message: 'phone, password, and code are required',
        });
      }
      const otpOk = verifyOtpEntry(phone.trim(), String(code).trim());
      if (!otpOk) {
        return res.status(400).json({
          code: 'invalid_otp',
          message: '验证码不正确或已过期，请重新获取',
        });
      }
      const account = registerAccount({ phone, password });
      res.status(201).json(tokenForUser(account, deviceId));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  /**
   * POST /api/v1/auth/login
   * Body: { phone, password, deviceId? }
   */
  router.post('/api/v1/auth/login', (req, res) => {
    try {
      const { phone, password, deviceId } = req.body || {};
      const account = authenticateAccount({ phone, password });
      res.json(tokenForUser(account, deviceId));
    } catch (err) {
      sendAuthError(res, err);
    }
  });

  /**
   * POST /api/v1/auth/demo-token
   * Body: { role?: 'app'|'edge'|'wearable', deviceId?: string }
   * **仅 debug 构建**（`NODE_ENV !== "production"`）；release 返回 404。
   * 契约见 docs/api/protocol.md。
   */
  router.post('/api/v1/auth/demo-token', (req, res) => {
    if (!isDebugBuild()) {
      return res.status(404).json({ code: 'not_found', message: 'demo-token is disabled' });
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

  router.get('/api/v1/devices', requireAuth, (req, res) => {
    // 只返回当前账号的设备（设备视图不再全局可见）。
    res.json({ devices: listDevices(req.auth.userId) });
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
