import jwt from 'jsonwebtoken';
import { randomBytes } from 'node:crypto';
import { config } from '../config.js';

const ROLES = new Set(['app', 'edge', 'wearable']);

/**
 * @param {{
 *   userId: string,
 *   username: string,
 *   phone: string,
 *   sex: string,
 *   role: string,
 *   deviceId?: string,
 *   plan?: string,
 * }} user
 */
export function issueToken(user) {
  if (!ROLES.has(user.role)) {
    const err = new Error(`invalid role: ${user.role}`);
    err.status = 400;
    err.code = 'invalid_role';
    throw err;
  }

  const deviceId = user.deviceId || `${user.role}-device`;
  const payload = {
    userId: user.userId,
    username: user.username,
    phone: user.phone,
    sex: user.sex || 'unknown',
    role: user.role,
    deviceId,
  };

  const token = jwt.sign(payload, config.jwtSecret, {
    expiresIn: config.tokenTtlSec,
  });

  return {
    token,
    role: user.role,
    deviceId,
    protocolVersion: config.protocolVersion,
    expiresInSec: config.tokenTtlSec,
    user: {
      userId: user.userId,
      username: user.username,
      phone: user.phone,
      sex: user.sex || 'unknown',
      plan: user.plan || 'free',
    },
  };
}

export function issueDemoToken({ role = 'app', deviceId } = {}) {
  const resolvedDeviceId = deviceId || `${role}-demo`;
  const userId = `demo-${role}-${randomBytes(4).toString('hex')}`;
  return issueToken({
    userId,
    username: `演示${role}`,
    phone: '10000000000',
    sex: 'unknown',
    role,
    deviceId: resolvedDeviceId,
    plan: 'free',
  });
}

/**
 * @returns {{ userId: string, username: string, phone: string, sex: string, role: string, deviceId?: string, accountKey: string } | null}
 */
export function verifyToken(token) {
  if (!token) return null;
  try {
    const decoded = jwt.verify(token, config.jwtSecret);
    if (!decoded || typeof decoded !== 'object') return null;
    const userId = decoded.userId;
    if (!userId) return null;
    return {
      userId,
      username: decoded.username || '',
      phone: decoded.phone || '',
      sex: decoded.sex || 'unknown',
      role: decoded.role || 'app',
      deviceId: decoded.deviceId,
      // Sessions keyed by userId
      accountKey: userId,
    };
  } catch {
    return null;
  }
}

export function extractBearer(authHeader) {
  if (!authHeader || typeof authHeader !== 'string') return null;
  const m = authHeader.match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}
