/**
 * 正式服部署打包：生成可上传的 zip（不含 node_modules / .env / 本地 data）。
 * 用法：node scripts/pack-prod.mjs
 */
import { mkdirSync, rmSync, cpSync, writeFileSync, existsSync, readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execSync } from 'node:child_process';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
const now = new Date();
const stamp = [
  now.getFullYear(),
  String(now.getMonth() + 1).padStart(2, '0'),
  String(now.getDate()).padStart(2, '0'),
].join('');
const outName = `websocket-server-v${pkg.version}-${stamp}`;
const distDir = join(root, 'dist');
const stageDir = join(distDir, outName);
const zipPath = join(distDir, `${outName}.zip`);

rmSync(stageDir, { recursive: true, force: true });
mkdirSync(stageDir, { recursive: true });

const copyList = ['package.json', 'package-lock.json', 'README.md', '.env.example', 'src'];
for (const name of copyList) {
  const from = join(root, name);
  if (!existsSync(from)) {
    throw new Error(`missing required path: ${name}`);
  }
  cpSync(from, join(stageDir, name), { recursive: true });
}

mkdirSync(join(stageDir, 'data'), { recursive: true });
writeFileSync(join(stageDir, 'data', '.gitkeep'), '');

writeFileSync(
  join(stageDir, '.env.production.example'),
  [
    'HOST=0.0.0.0',
    'PORT=8000',
    'NODE_ENV=production',
    'JWT_SECRET=change-me-to-a-long-random-secret',
    '# 演示/占位后端；接真模型或真 TTS 时再改',
    'TTS_BACKEND=tone',
    'RECOGNITION_BACKEND=rules',
    '',
    '# 大模型（OpenAI 兼容；LLM_API_KEY 留空则关闭，仅用规则词表）',
    'LLM_PROVIDER=deepseek',
    'LLM_API_BASE=https://api.deepseek.com',
    'LLM_API_KEY=',
    'LLM_MODEL=deepseek-flash',
    'LLM_TEMPERATURE=0.0',
    '',
  ].join('\n'),
);

writeFileSync(
  join(stageDir, 'DEPLOY.md'),
  `# 正式服部署（websocket-server v${pkg.version}）

## 环境

- Node.js >= 18（建议 20 LTS / 22）
- 开放入站 TCP \`8000\`（或你在 \`.env\` 里改的 \`PORT\`）

## 解压与安装

\`\`\`bash
unzip ${outName}.zip
cd ${outName}
cp .env.production.example .env
# 编辑 .env：务必修改 JWT_SECRET
npm ci --omit=dev
\`\`\`

## 启动命令

前台：

\`\`\`bash
export $(grep -v '^#' .env | xargs)   # Linux
npm start
\`\`\`

或（Node >= 20，推荐）：

\`\`\`bash
node --env-file=.env src/index.js
\`\`\`

后台（nohup）：

\`\`\`bash
nohup node --env-file=.env src/index.js >> logs/gateway.log 2>&1 &
echo $! > gateway.pid
\`\`\`

PM2：

\`\`\`bash
npm i -g pm2
pm2 start src/index.js --name jianyin-ws --node-args="--env-file=.env"
pm2 save
pm2 startup
\`\`\`

## 健康检查与文档

\`\`\`bash
curl http://127.0.0.1:8000/health
\`\`\`

Swagger UI：\`http://127.0.0.1:8000/docs\`  
OpenAPI：\`http://127.0.0.1:8000/openapi.json\`

\`NODE_ENV=production\` 时 \`/api/v1/auth/demo-token\` 不可用。
账号/历史写入 \`data/*.json\`，请定期备份该目录。

手语→中文：在 \`.env\` 填写 \`LLM_API_KEY\` 等项后，切段特征会送大模型翻译；
留空则仅用规则词表。密钥勿提交到仓库。
`,
);

if (existsSync(zipPath)) rmSync(zipPath);

const isWin = process.platform === 'win32';
if (isWin) {
  execSync(
    `powershell -NoProfile -Command "Compress-Archive -Path '${stageDir.replace(/'/g, "''")}' -DestinationPath '${zipPath.replace(/'/g, "''")}' -Force"`,
    { stdio: 'inherit' },
  );
} else {
  execSync(`tar -a -cf "${zipPath}" -C "${distDir}" "${outName}"`, { stdio: 'inherit' });
}

console.log(`[pack] staged: ${stageDir}`);
console.log(`[pack] artifact: ${zipPath}`);
