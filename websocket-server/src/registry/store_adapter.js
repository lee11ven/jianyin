/**
 * 存储适配层：把「数据存取」与「业务逻辑」解耦，支持按后端切换。
 *
 * 后端由 `STORAGE_BACKEND` 选择：
 * - `json`（默认）：单机文件存储，落 `websocket-server/data/<name>.json`（不入版本库）
 * - `memory`：进程内内存，用于压测与「无状态实例」验证
 * - `external`：预留外部存储（Redis / SQL）接入点——实现同一 `read/write/update` 契约即可替换
 *
 * 契约（三种后端一致）：
 *   read(name, fallback)        读取一个文档；不存在时返回 fallback（不写盘）
 *   write(name, value)          整体写入
 *   update(name, fallback, fn)  读 → fn(doc)（可原地改或返回新值）→ 写，返回最新文档
 *   backendName()               当前后端名（便于日志与自检）
 *
 * 迁移到多实例：接上 `external` 适配器并把会话路由改为粘性（见 docs/reports/scalability.md）。
 */
import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DATA_DIR = join(__dirname, '..', '..', 'data');

const memoryStore = new Map();

function filePathOf(name) {
  return join(DATA_DIR, name.endsWith('.json') ? name : `${name}.json`);
}

function readJsonFile(name, fallback) {
  const file = filePathOf(name);
  if (!existsSync(file)) return fallback;
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJsonFile(name, value) {
  const file = filePathOf(name);
  mkdirSync(dirname(file), { recursive: true });
  // 原子写：先写临时文件再 rename，避免半截 JSON。
  const tmp = `${file}.${process.pid}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
  renameSync(tmp, file);
  return value;
}

/** 数据文件路径（供运维/备份使用；memory 与 external 后端返回「本应落盘」的路径）。 */
export function dataPathOf(name) {
  return filePathOf(name);
}

const BACKENDS = {
  json: {
    name: 'json',
    // 读取缺失时按当前行为自动建档（保证首次运行即可用）。
    read: (name, fallback) => {
      const existing = readJsonFile(name, undefined);
      if (existing !== undefined) return existing;
      return writeJsonFile(name, fallback);
    },
    write: (name, value) => writeJsonFile(name, value),
  },
  memory: {
    name: 'memory',
    read: (name, fallback) => (memoryStore.has(name) ? memoryStore.get(name) : fallback),
    write: (name, value) => {
      memoryStore.set(name, value);
      return value;
    },
  },
  /**
   * 外部存储接入点：把下面三个方法接到 Redis / SQL 即可；
   * 未配置时抛错，避免「以为用了外部存储、其实还是本地文件」的静默错误。
   */
  external: {
    name: 'external',
    read: () => {
      throw new Error('STORAGE_BACKEND=external 尚未接入实现（预留适配点）');
    },
    write: () => {
      throw new Error('STORAGE_BACKEND=external 尚未接入实现（预留适配点）');
    },
  },
};

export function currentBackendName() {
  const name = process.env.STORAGE_BACKEND || 'json';
  return BACKENDS[name] ? name : 'json';
}

function currentBackend() {
  return BACKENDS[currentBackendName()];
}

export function read(name, fallback) {
  return currentBackend().read(name, fallback);
}

export function write(name, value) {
  return currentBackend().write(name, value);
}

export function update(name, fallback, mutator) {
  const doc = read(name, fallback);
  const next = mutator(doc) ?? doc;
  return write(name, next);
}

/** 供测试与运维自检使用。 */
export const __testing = {
  resetMemory() {
    memoryStore.clear();
  },
};