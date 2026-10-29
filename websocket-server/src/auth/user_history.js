import { randomBytes } from 'node:crypto';
import { readJson, updateJson } from '../data/json_store.js';

const HISTORY_FILE = 'history.json';

function dayIso(ts) {
  const d = new Date(ts);
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

function dayLabel(iso, now = new Date()) {
  const today = dayIso(now.getTime());
  const y = new Date(now);
  y.setDate(y.getDate() - 1);
  const yesterday = dayIso(y.getTime());
  if (iso === today) return '今天';
  if (iso === yesterday) return '昨天';
  const [, mo, d] = iso.split('-');
  return `${Number(mo)}月${Number(d)}日`;
}

function timeLabel(ts) {
  const d = new Date(ts);
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

/**
 * Persist recognition text for a user.
 */
export function appendUserHistory(userId, entry) {
  if (!userId) return null;
  const row = {
    id: entry.id || `h-${randomBytes(6).toString('hex')}`,
    ts: entry.ts || Date.now(),
    text: entry.text,
    sessionId: entry.sessionId || null,
    utteranceId: entry.utteranceId || null,
    confidence: entry.confidence,
    glossIds: entry.glossIds,
  };
  updateJson(HISTORY_FILE, {}, (all) => {
    if (!all[userId]) all[userId] = [];
    all[userId].push(row);
    return all;
  });
  return row;
}

/**
 * @param {string} userId
 * @param {{ from?: string, to?: string }} range YYYY-MM-DD
 */
export function listUserHistoryDays(userId, { from, to } = {}) {
  const all = readJson(HISTORY_FILE, {});
  let items = all[userId] || [];
  if (from) {
    items = items.filter((e) => dayIso(e.ts) >= from);
  }
  if (to) {
    items = items.filter((e) => dayIso(e.ts) <= to);
  }
  items = [...items].sort((a, b) => b.ts - a.ts);

  /** @type {Map<string, object[]>} */
  const byDay = new Map();
  for (const e of items) {
    const iso = dayIso(e.ts);
    if (!byDay.has(iso)) byDay.set(iso, []);
    byDay.get(iso).push({
      id: e.id,
      time: timeLabel(e.ts),
      text: e.text,
      ts: e.ts,
    });
  }

  const days = [];
  for (const [iso, dayItems] of byDay) {
    days.push({
      iso,
      label: dayLabel(iso),
      items: dayItems,
    });
  }
  return days;
}
