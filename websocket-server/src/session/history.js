/** @type {Map<string, Array<{ utteranceId: string, text: string, confidence: number, glossIds: string[], ts: number }>>} */
const histories = new Map();

export function appendHistory(sessionId, entry) {
  let list = histories.get(sessionId);
  if (!list) {
    list = [];
    histories.set(sessionId, list);
  }
  list.push(entry);
  return entry;
}

export function getHistory(sessionId) {
  return histories.get(sessionId) || [];
}

export function clearHistory(sessionId) {
  histories.delete(sessionId);
}
