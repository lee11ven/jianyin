import { mkdirSync, readFileSync, renameSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'data');

function ensureDir() {
  if (!existsSync(root)) mkdirSync(root, { recursive: true });
}

/**
 * @param {string} name file under data/, e.g. "users.json"
 * @param {unknown} fallback
 */
export function readJson(name, fallback) {
  ensureDir();
  const path = join(root, name);
  if (!existsSync(path)) {
    writeJson(name, fallback);
    return structuredClone(fallback);
  }
  try {
    const raw = readFileSync(path, 'utf8');
    return JSON.parse(raw);
  } catch {
    return structuredClone(fallback);
  }
}

/**
 * @param {string} name
 * @param {unknown} data
 */
export function writeJson(name, data) {
  ensureDir();
  const path = join(root, name);
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
  renameSync(tmp, path);
}

/**
 * @template T
 * @param {string} name
 * @param {T} fallback
 * @param {(data: T) => T | void} mutator
 * @returns {T}
 */
export function updateJson(name, fallback, mutator) {
  const data = readJson(name, fallback);
  const next = mutator(data) ?? data;
  writeJson(name, next);
  return next;
}

export function dataPath(name) {
  return join(root, name);
}
