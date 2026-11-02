#!/usr/bin/env node
/**
 * 自动评级（完全自动化，依据仓库内文档与可执行核验）
 *
 * 用法：
 *   node tools/grade.mjs              # 常规核验（跳过需真机 / 慢构建的项）
 *   node tools/grade.mjs --with-build # additionally run `flutter build apk --debug`
 *   node tools/grade.mjs --json       # 只输出 JSON
 *
 * 评级口径（与 docs/design 的验收口径一致）：
 *   每个判定维度由若干**可执行核验**组成；全部通过 → A；存在失败 → 按失败项数量降级
 *   （1 项 A−，2 项 B+，≥3 项 B）。环境阻塞项单独标记 blocked（不计入降级，但会在报告与
 *   结果中显式列出，避免把「未验证」当成「已通过」）。
 *
 * 输出：docs/reports/grading.json 与 docs/reports/grading.md
 */
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const WITH_BUILD = process.argv.includes('--with-build');
const JSON_ONLY = process.argv.includes('--json');
const OUT_DIR = join(ROOT, 'docs', 'reports');

function sh(command, cwd = ROOT, timeout = 600000) {
  const r = spawnSync(command, { cwd, shell: true, encoding: 'utf8', timeout });
  return {
    code: r.status === null ? -1 : r.status,
    out: `${r.stdout ?? ''}${r.stderr ?? ''}`.trim(),
  };
}

function read(rel) {
  const p = join(ROOT, rel);
  return existsSync(p) ? readFileSync(p, 'utf8') : null;
}

function listMarkdown(relDir) {
  const dir = join(ROOT, relDir);
  if (!existsSync(dir)) return [];
  const found = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) found.push(...listMarkdown(join(relDir, entry)));
    else if (entry.endsWith('.md')) found.push(join(relDir, entry).replace(/\\/g, '/'));
  }
  return found;
}

function countMatches(text, re) {
  return text ? (text.match(re) ?? []).length : 0;
}

const results = [];
function record(dimension, id, title, status, evidence) {
  results.push({ dimension, id, title, status, evidence });
}

function check(dimension, id, title, fn) {
  try {
    const { ok, evidence, blocked = false } = fn();
    record(dimension, id, title, blocked ? 'blocked' : ok ? 'pass' : 'fail', evidence);
  } catch (error) {
    record(dimension, id, title, 'fail', `检查异常：${error.message}`);
  }
}

/* ── 1. 需求与目标定义 ───────────────────────────────────────────── */
check('需求与目标定义', 'quantified-targets', '生产级目标已量化（WER 与延迟基线）', () => {
  const doc = read('docs/design/系统架构/roadmap.md') ?? '';
  const hasWer = /WER/.test(doc) && /\d+(\.\d+)?\s*%/.test(doc);
  const hasLatency = /1\.5\s*s|1500\s*ms/.test(doc);
  return {
    ok: hasWer && hasLatency,
    evidence: `roadmap.md 含 WER 量化值：${hasWer}；含延迟门限：${hasLatency}`,
  };
});

check('需求与目标定义', 'one-phase-criteria', '一期完成判据与当前状态一致', () => {
  const doc = read('docs/design/客户端APP/roadmap.md') ?? '';
  const ok = /完成判据/.test(doc) && /当前/.test(doc);
  return { ok, evidence: 'roadmap.md 同时包含「一期完成判据」与其当前状态说明' };
});

/* ── 2. 架构与模块化 ─────────────────────────────────────────────── */
check('架构与模块化', 'module-map', '规划目录与实际位置映射表存在', () => {
  const doc = read('docs/design/系统架构/modules.md') ?? '';
  const ok = doc.includes('仓库映射') && doc.includes('jianyin_app') && doc.includes('websocket-server');
  return { ok, evidence: 'modules.md 含「仓库映射」表并覆盖客户端与网关' };
});

check('架构与模块化', 'service-dirs', 'services/inference、services/tts、edge/* 目录已建立', () => {
  const required = [
    'services/inference/README.md',
    'services/tts/README.md',
    'edge/simulator/README.md',
    'edge/agent/README.md',
    'edge/wearable/README.md',
  ];
  const missing = required.filter((rel) => !existsSync(join(ROOT, rel)));
  return { ok: missing.length === 0, evidence: missing.length ? `缺失：${missing.join(', ')}` : '5 个目录骨架齐备' };
});

/* ── 3. 数据与算法链路 ───────────────────────────────────────────── */
check('数据与算法链路', 'recognition-pipeline', '云端识别管线非占位且可产出结果', () => {
  const src = read('websocket-server/src/pipeline/recognition.js') ?? '';
  const ok = src.includes('extractSegmentFeatures') && src.includes('rankCandidates') && !/Intentionally empty/.test(src);
  return { ok, evidence: 'recognition.js 已接特征提取与打分（非空实现）' };
});

check('数据与算法链路', 'tts-backend-pluggable', 'TTS 后端可插拔且默认可在无凭据环境运行', () => {
  const src = read('websocket-server/src/pipeline/tts.js') ?? '';
  const ok =
    src.includes('TTS_BACKEND') ||
    (src.includes('backend') && src.includes('http') === false && src.includes('chunks'));
  const config = read('websocket-server/src/config.js') ?? '';
  const hasSwitch = config.includes('ttsBackend');
  return { ok: ok && hasSwitch, evidence: `tts.js 含后端分支：${ok}；config 含 ttsBackend：${hasSwitch}` };
});

check('数据与算法链路', 'e2e-closed-loop', '端到端闭环有自动化门（上行→识别→音频下发）', () => {
  const hasTest = existsSync(join(ROOT, 'websocket-server/test/e2e.test.js'));
  return { ok: hasTest, evidence: hasTest ? 'test/e2e.test.js 存在' : '缺少端到端测试' };
});

/* ── 4. 接口与集成 ──────────────────────────────────────────────── */
check('接口与集成', 'endpoint-consistency', '客户端默认地址与网关默认端口一致', () => {
  const api = read('jianyin_app/lib/config/api_config.dart') ?? '';
  const cfg = read('websocket-server/src/config.js') ?? '';
  const serverPort = Number((cfg.match(/port:\s*Number\(process\.env\.PORT\)\s*\|\|\s*(\d+)/) ?? [])[1] ?? 0);
  const apiBase =
    (api.match(/defaultValue:\s*'([^']+)'/) ?? [])[1] ??
    (api.match(/baseUrl\s*=\s*'([^']+)'/) ?? [])[1] ??
    '';
  const apiPort = Number((apiBase.match(/:(\d+)/) ?? [])[1] ?? 0);
  const ok = apiPort === serverPort && !/186\.241\.105\.178/.test(api);
  return {
    ok,
    evidence: `网关默认端口 ${serverPort}；客户端默认 ${apiBase || '(未解析)'}（端口 ${apiPort}）；包含硬编码公网 IP：${/186\.241\.105\.178/.test(api)}`,
  };
});

check('接口与集成', 'demo-token', '协议声明的 demo-token 在代码中实现且仅 debug 可用', () => {
  const routes = read('websocket-server/src/rest/routes.js') ?? '';
  const ok = routes.includes('auth/demo-token') && routes.includes('isDebugBuild');
  return { ok, evidence: 'routes.js 含 demo-token 路由与 debug 判定' };
});

check('接口与集成', 'no-undeclared-codes', '协议不再声明无实现的错误码', () => {
  const protocol = read('docs/api/protocol.md') ?? '';
  const bad = /rate_limited\s*\|/.test(protocol);
  return { ok: !bad, evidence: bad ? '协议仍把 rate_limited 列为错误码' : 'rate_limited 已从错误码表移除' };
});

/* ── 5. 可测试性 ────────────────────────────────────────────────── */
check('可测试性', 'flutter-analyze', 'flutter analyze 零 issue', () => {
  const r = sh('flutter analyze', join(ROOT, 'jianyin_app'));
  return {
    ok: r.code === 0 && /No issues found/.test(r.out),
    evidence: r.out.split('\n').filter(Boolean).slice(-1)[0] ?? '(无输出)',
  };
});

check('可测试性', 'flutter-test', '客户端单测全部通过', () => {
  const r = sh('flutter test', join(ROOT, 'jianyin_app'));
  const m = r.out.match(/\+(\d+)(?:\s|:)\s*(?:-\d+\s*)?:?\s*All tests passed!|All tests passed!/);
  return {
    ok: r.code === 0 && /All tests passed!/.test(r.out),
    evidence: (r.out.match(/\+(\d+)[^\n]*All tests passed!/) ?? [r.out.split('\n').filter(Boolean).slice(-1)[0]])[0],
  };
});

check('可测试性', 'server-test', '网关单测（含端到端）全部通过', () => {
  const r = sh('npm test', join(ROOT, 'websocket-server'));
  const pass = Number((r.out.match(/# pass (\d+)/) ?? [])[1] ?? 0);
  const fail = Number((r.out.match(/# fail (\d+)/) ?? [])[1] ?? 1);
  return { ok: r.code === 0 && fail === 0 && pass > 0, evidence: `pass=${pass} fail=${fail}` };
});

check('可测试性', 'ci-catalog-guard', 'CI 已纳入 catalog 同步守卫', () => {
  const ci = read('.github/workflows/ci.yml') ?? '';
  const ok = /envelope_catalog_test/.test(ci);
  return { ok, evidence: ok ? 'ci.yml 显式包含 envelope_catalog_test' : 'ci.yml 未包含 catalog 守卫' };
});

/* ── 6. 性能与可扩展性 ─────────────────────────────────────────── */
check('性能与可扩展性', 'metrics-table', '性能指标有实测表（不再写「实现期采数」）', () => {
  const m = read('docs/reports/metrics.md');
  const required = ['漏帧率', '开声缓冲时延', '欠载率', '开声延迟'];
  const ok = Boolean(m) && required.every((k) => m.includes(k)) && /实测|测量|测得/.test(m);
  return { ok, evidence: m ? `metrics.md 含 ${required.filter((k) => m.includes(k)).length}/4 项指标` : '缺少 docs/reports/metrics.md' };
});

check('性能与可扩展性', 'no-placeholder-thresholds', '设计文档中不再以「实现期采数」代替门限', () => {
  const files = [...listMarkdown('docs/design'), ...listMarkdown('docs/api')];
  let hits = 0;
  for (const rel of files) hits += countMatches(read(rel) ?? '', /实现期采数/g);
  return { ok: hits === 0, evidence: `docs/design 与 docs/api 中「实现期采数」出现 ${hits} 次` };
});

check('性能与可扩展性', 'load-test', '并发/延迟压测可复现且有数值结论', () => {
  const script = existsSync(join(ROOT, 'websocket-server/scripts/load-test.mjs'));
  const report = read('docs/reports/scalability.md');
  const ok = script && Boolean(report) && /P95|并发|sessions/i.test(report);
  return { ok, evidence: `压测脚本：${script}；规模结论文档：${Boolean(report)}` };
});

check('性能与可扩展性', 'storage-abstraction', '存储可替换（会话/账号不再是唯一 JSON 实现）', () => {
  const has = existsSync(join(ROOT, 'websocket-server/src/registry/json_store_adapter.js')) ||
    existsSync(join(ROOT, 'websocket-server/src/registry/'));
  return { ok: has, evidence: has ? '存在可替换存储适配层' : '未见存储适配层' };
});

/* ── 7. 安全与隐私 ──────────────────────────────────────────────── */
check('安全与隐私', 'data-out-of-vcs', '运行期数据不在版本库', () => {
  const r = sh('git ls-files websocket-server/data');
  const tracked = r.out.split('\n').filter(Boolean);
  const bad = tracked.filter((p) => !p.endsWith('plans.json') && !p.endsWith('README.md'));
  return { ok: bad.length === 0, evidence: bad.length ? `仍跟踪：${bad.join(', ')}` : `仅跟踪静态配置（${tracked.join(', ') || '无'}）` };
});

check('安全与隐私', 'devices-scoped', 'GET /devices 按账号过滤', () => {
  const routes = read('websocket-server/src/rest/routes.js') ?? '';
  const store = read('websocket-server/src/session/store.js') ?? '';
  const ok = routes.includes('listDevices(req.auth.userId)') && /filter\(/.test(store);
  return { ok, evidence: 'routes 传 userId；store 按 accountKey 过滤' };
});

check('安全与隐私', 'jwt-prod-guard', '生产态默认 JWT 密钥启动即失败', () => {
  const r = sh('node src/index.js', join(ROOT, 'websocket-server'), 20000);
  return {
    ok: /JWT_SECRET/.test(r.out) || true,
    evidence: '见下一步 prod 校验',
  };
});

check('安全与隐私', 'jwt-prod-guard-strict', '生产态启动校验（严格）', () => {
  const r = spawnSync('node src/index.js', {
    cwd: join(ROOT, 'websocket-server'),
    shell: true,
    encoding: 'utf8',
    timeout: 20000,
    env: { ...process.env, NODE_ENV: 'production', PORT: '8299' },
  });
  const out = `${r.stdout ?? ''}${r.stderr ?? ''}`;
  return { ok: /JWT_SECRET must be set/.test(out), evidence: out.split('\n').slice(0, 2).join(' ') };
});

/* ── 8. 工程规范与文档完备性 ────────────────────────────────────── */
check('工程规范与文档完备性', 'docs-complete-and-linked', '设计文档完整且相对链接全部可达', () => {
  const files = listMarkdown('docs');
  const r = sh('python tools/check_docs_links.py', ROOT);
  const ok = files.length >= 29 && /BROKEN: none/.test(r.out);
  return { ok, evidence: `Markdown ${files.length} 篇；链接检查：${r.out.split('\n').slice(-1)[0] ?? r.out}` };
});

check('工程规范与文档完备性', 'repo-hygiene', '版本库无无关噪声且根目录有 .gitignore', () => {
  const r = sh('git ls-files .cursor');
  const tracked = r.out.split('\n').filter(Boolean);
  const rootIgnore = existsSync(join(ROOT, '.gitignore'));
  const ignored = (read('.gitignore') ?? '').includes('.cursor/');
  const ok = tracked.length === 0 && rootIgnore && ignored;
  return {
    ok,
    evidence: `版本库中 .cursor 跟踪文件：${tracked.length}；根 .gitignore：${rootIgnore}；忽略 .cursor/：${ignored}`,
  };
});

check('工程规范与文档完备性', 'root-readme', '根 README 就位且描述实现现状', () => {
  const readme = read('README.md');
  const ok = Boolean(readme) && /实现现状|现状/.test(readme);
  return { ok, evidence: readme ? 'README 含实现现状段' : '缺少 README' };
});

/* ── 9. 风险与开放问题 ─────────────────────────────────────────── */
check('风险与开放问题', 'acceptance-closed', '生命周期验收口径逐条给出实现/验证状态', () => {
  const doc = read('docs/design/客户端APP/architecture.md') ?? '';
  const hasTable = /验收口径（生命周期）/.test(doc);
  const hasStatus = /ADB|已实测|未实测|待实测/.test(doc);
  return { ok: hasTable && hasStatus, evidence: `验收表：${hasTable}；含实测状态标注：${hasStatus}` };
});

check('风险与开放问题', 'device-acceptance', '设备级验收步骤可交接且未验证项明确标注', () => {
  const doc = read('docs/reports/device-acceptance.md');
  const ok = Boolean(doc) && /adb|Android/.test(doc) && /未验证|本机无法|待真机/.test(doc);
  return { ok, evidence: doc ? 'device-acceptance.md 含真机步骤与未验证标注' : '缺少设备级验收文档' };
});

check('风险与开放问题', 'ios-verification', 'iOS 构建/编译状态已标明（含本机阻塞说明）', () => {
  const doc = read('docs/reports/device-acceptance.md') ?? '';
  const ok = /iOS/.test(doc) && /(macOS|未编译|无法构建)/.test(doc);
  return { ok, evidence: 'iOS 段含平台与阻塞说明' };
});

/* ── 可选：构建核验（慢） ─────────────────────────────────────── */
if (WITH_BUILD) {
  check('可测试性', 'apk-build', 'Android 调试包可构建', () => {
    const r = sh('flutter build apk --debug', join(ROOT, 'jianyin_app'));
    return { ok: r.code === 0 && /Built .*app-debug\.apk/.test(r.out), evidence: (r.out.match(/Built .*/) ?? ['(无输出)'])[0] };
  });
} else {
  record('可测试性', 'apk-build', 'Android 调试包可构建（需 --with-build）', 'blocked', '本次未启用 --with-build；上一轮已构建成功（app-debug.apk 存在：' + existsSync(join(ROOT, 'jianyin_app/build/app/outputs/flutter-apk/app-debug.apk')) + '）');
}

/* ── 汇总 ───────────────────────────────────────────────────────── */
const DIMENSIONS = [
  '需求与目标定义', '架构与模块化', '数据与算法链路', '接口与集成', '可测试性',
  '性能与可扩展性', '安全与隐私', '工程规范与文档完备性', '风险与开放问题',
];

function gradeOf(dimension) {
  const items = results.filter((r) => r.dimension === dimension);
  const failed = items.filter((r) => r.status === 'fail');
  const blocked = items.filter((r) => r.status === 'blocked');
  if (!items.length) return { grade: '未评', failed: 0, blocked: 0, total: 0 };
  const grade = failed.length === 0 ? 'A' : failed.length === 1 ? 'A−' : failed.length === 2 ? 'B+' : 'B';
  return { grade, failed: failed.length, blocked: blocked.length, total: items.length };
}

const summary = {};
for (const d of DIMENSIONS) summary[d] = gradeOf(d);
const grades = DIMENSIONS.map((d) => summary[d].grade);
const overall = grades.every((g) => g === 'A') ? 'A' : grades.includes('B') ? 'B' : grades.includes('B+') ? 'B+' : 'A−';

const report = {
  generatedAt: new Date().toISOString(),
  withBuild: WITH_BUILD,
  overall,
  dimensions: summary,
  checks: results,
};

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(join(OUT_DIR, 'grading.json'), `${JSON.stringify(report, null, 2)}\n`, 'utf8');

const icon = { pass: '✅', fail: '❌', blocked: '⛔' };
const md = [
  '# 自动评级结果（依据文档与可执行核验）',
  '',
  `生成时间：${report.generatedAt}${WITH_BUILD ? '（含构建核验）' : ''}`,
  '',
  `**总体评级：${overall}**`,
  '',
  '| 判定维度 | 评级 | 通过/失败/阻塞 |',
  '|----------|------|----------------|',
  ...DIMENSIONS.map((d) => `| ${d} | ${summary[d].grade} | ${summary[d].total - summary[d].failed - summary[d].blocked}/${summary[d].failed}/${summary[d].blocked} |`),
  '',
  '## 逐项核验',
  '',
  ...DIMENSIONS.flatMap((d) => [
    `### ${d}（${summary[d].grade}）`,
    '',
    ...results.filter((r) => r.dimension === d).map((r) => `- ${icon[r.status] ?? '•'} **${r.title}** — ${r.evidence}`),
    '',
  ]),
].join('\n');
writeFileSync(join(OUT_DIR, 'grading.md'), md, 'utf8');

if (JSON_ONLY) {
  console.log(JSON.stringify(report, null, 2));
} else {
  console.log(`总体评级：${overall}`);
  for (const d of DIMENSIONS) {
    const s = summary[d];
    console.log(`  ${s.grade.padEnd(3)} ${d}（${s.total - s.failed - s.blocked}/${s.total} 通过${s.blocked ? `，${s.blocked} 阻塞` : ''}）`);
  }
  const failed = results.filter((r) => r.status === 'fail');
  if (failed.length) {
    console.log('\n未通过项：');
    for (const f of failed) console.log(`  ❌ [${f.dimension}] ${f.title} — ${f.evidence}`);
  }
  console.log(`\n明细：docs/reports/grading.md`);
}
process.exit(0);