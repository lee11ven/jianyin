import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import { readJson, updateJson } from '../data/json_store.js';

const USERS_FILE = 'users.json';
const PHONE_RE = /^1\d{10}$/;
const SEXES = new Set(['male', 'female', 'unknown']);

export function normalizePhone(phone) {
  return String(phone || '').trim();
}

export function assertValidPhone(phone) {
  const p = normalizePhone(phone);
  if (!PHONE_RE.test(p)) {
    const err = new Error('invalid phone number');
    err.status = 400;
    err.code = 'invalid_phone';
    throw err;
  }
  return p;
}

export function assertValidPassword(password) {
  const pw = String(password ?? '');
  if (pw.length < 8) {
    const err = new Error('password must be at least 8 characters');
    err.status = 400;
    err.code = 'weak_password';
    throw err;
  }
  return pw;
}

export function normalizeSex(sex) {
  if (sex == null || sex === '') return 'unknown';
  const s = String(sex).trim().toLowerCase();
  if (!SEXES.has(s)) {
    const err = new Error('invalid sex');
    err.status = 400;
    err.code = 'invalid_sex';
    throw err;
  }
  return s;
}

function defaultUsername(phone) {
  return `用户${phone.slice(-4)}`;
}

function hashPassword(password, saltB64) {
  const salt = Buffer.from(saltB64, 'base64');
  return scryptSync(password, salt, 32).toString('base64');
}

function loadUsers() {
  return readJson(USERS_FILE, {});
}

/**
 * Public profile fields (no password).
 */
export function toPublicUser(user, planInfo = { plan: 'free', planExpiresAt: null }) {
  return {
    userId: user.userId,
    username: user.username,
    phone: user.phone,
    sex: user.sex || 'unknown',
    plan: planInfo.plan || 'free',
    planExpiresAt: planInfo.planExpiresAt ?? null,
  };
}

export function findUserByPhone(phone) {
  const p = normalizePhone(phone);
  const users = loadUsers();
  return Object.values(users).find((u) => u.phone === p) || null;
}

export function findUserById(userId) {
  const users = loadUsers();
  return users[userId] || null;
}

/**
 * @returns {object} stored user
 */
export function registerAccount({ phone, password, username, sex }) {
  const p = assertValidPhone(phone);
  const pw = assertValidPassword(password);
  const sx = normalizeSex(sex);
  const name =
    username != null && String(username).trim()
      ? String(username).trim().slice(0, 32)
      : defaultUsername(p);

  if (findUserByPhone(p)) {
    const err = new Error('phone already registered');
    err.status = 409;
    err.code = 'phone_taken';
    throw err;
  }

  const userId = `u-${randomBytes(8).toString('hex')}`;
  const salt = randomBytes(16).toString('base64');
  const passwordHash = hashPassword(pw, salt);
  const user = {
    userId,
    phone: p,
    username: name,
    sex: sx,
    salt,
    passwordHash,
    createdAt: Date.now(),
  };

  updateJson(USERS_FILE, {}, (users) => {
    users[userId] = user;
    return users;
  });

  return user;
}

export function authenticateAccount({ phone, password }) {
  const p = assertValidPhone(phone);
  const pw = String(password ?? '');
  const user = findUserByPhone(p);
  const fail = () => {
    const err = new Error('invalid phone or password');
    err.status = 401;
    err.code = 'invalid_credentials';
    throw err;
  };
  if (!user) fail();
  const hash = hashPassword(pw, user.salt);
  const expected = Buffer.from(user.passwordHash, 'base64');
  const actual = Buffer.from(hash, 'base64');
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) {
    fail();
  }
  return user;
}

export function updateUserProfile(userId, { username, sex } = {}) {
  let updated = null;
  updateJson(USERS_FILE, {}, (users) => {
    const user = users[userId];
    if (!user) {
      const err = new Error('user not found');
      err.status = 404;
      err.code = 'not_found';
      throw err;
    }
    if (username != null) {
      const name = String(username).trim();
      if (!name) {
        const err = new Error('username required');
        err.status = 400;
        err.code = 'bad_request';
        throw err;
      }
      user.username = name.slice(0, 32);
    }
    if (sex != null) {
      user.sex = normalizeSex(sex);
    }
    users[userId] = user;
    updated = user;
    return users;
  });
  return updated;
}
