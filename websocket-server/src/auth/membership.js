import { readJson, updateJson } from '../data/json_store.js';

const MEMBERSHIP_FILE = 'membership.json';
const PLANS_FILE = 'plans.json';

const PLAN_TTL_MS = {
  pro_month: 30 * 24 * 60 * 60 * 1000,
  pro_year: 365 * 24 * 60 * 60 * 1000,
};

export function listPlans() {
  const data = readJson(PLANS_FILE, { plans: [] });
  return data.plans || [];
}

export function findPlan(planId) {
  return listPlans().find((p) => p.id === planId) || null;
}

export function getMembership(userId) {
  const all = readJson(MEMBERSHIP_FILE, {});
  const row = all[userId];
  if (!row) {
    return { planId: 'free', title: '免费版', expiresAt: null };
  }
  if (row.expiresAt && row.expiresAt < Date.now()) {
    return { planId: 'free', title: '免费版', expiresAt: null };
  }
  const plan = findPlan(row.planId);
  return {
    planId: row.planId,
    title: plan?.title || row.planId,
    expiresAt: row.expiresAt ?? null,
  };
}

export function planInfoForUser(userId) {
  const m = getMembership(userId);
  return {
    plan: m.planId,
    planExpiresAt: m.expiresAt,
  };
}

export function subscribe(userId, planId) {
  if (!planId || planId === 'free') {
    const err = new Error('cannot subscribe to free plan');
    err.status = 400;
    err.code = 'invalid_plan';
    throw err;
  }
  const plan = findPlan(planId);
  if (!plan) {
    const err = new Error('unknown plan');
    err.status = 400;
    err.code = 'invalid_plan';
    throw err;
  }
  const ttl = PLAN_TTL_MS[planId];
  if (!ttl) {
    const err = new Error('unknown plan duration');
    err.status = 400;
    err.code = 'invalid_plan';
    throw err;
  }
  const expiresAt = Date.now() + ttl;
  updateJson(MEMBERSHIP_FILE, {}, (all) => {
    all[userId] = { planId, expiresAt, updatedAt: Date.now() };
    return all;
  });
  return getMembership(userId);
}
