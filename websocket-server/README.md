# WebSocket 网关（protocolVersion: 1）

Node.js REST + WebSocket 网关，对齐仓库 `docs/api/protocol.md`。监听 `0.0.0.0:8000`，支持局域网访问。

## 启动

```bash
cd websocket-server
npm install
npm start
# 开发热重载：npm run dev
```

可选环境变量（见 `.env.example`）：

| 变量 | 默认 | 说明 |
|------|------|------|
| `HOST` | `0.0.0.0` | 必须绑定 `0.0.0.0` 才能被局域网访问 |
| `PORT` | `8000` | HTTP / WS 共用端口 |
| `NODE_ENV` | `development` | `production` 时关闭 demo-token |
| `JWT_SECRET` | 开发默认值 | **正式服必须改成强随机串** |
| `TTS_BACKEND` | `tone` | TTS 后端 |
| `RECOGNITION_BACKEND` | `rules` | 规则词表；模型打分见 `lexicon.js` |
| `LLM_PROVIDER` | （空） | 如 `deepseek`（仅标记） |
| `LLM_API_BASE` | `https://api.deepseek.com` | OpenAI 兼容 Base（无尾斜杠） |
| `LLM_API_KEY` | （空） | **非空即启用**信封/切段 → 大模型 → 中文 |
| `LLM_MODEL` | `deepseek-flash` | 按供应商实际模型名填写 |
| `LLM_TEMPERATURE` | `0` | 建议翻译用 `0.0` |

## 正式服打包

本机生成可上传的 zip（不含 `node_modules` / `.env` / 本地 `data`）：

```bash
cd websocket-server
npm run pack
# 产物：dist/websocket-server-v1.0.0-YYYYMMDD.zip
```

## 正式服部署与启动

```bash
# 1) 上传并解压 zip
unzip websocket-server-v1.0.0-YYYYMMDD.zip
cd websocket-server-v1.0.0-YYYYMMDD

# 2) 配置环境
cp .env.production.example .env
# 编辑 .env：NODE_ENV=production，并修改 JWT_SECRET

# 3) 安装生产依赖
npm ci --omit=dev

# 4) 启动（任选其一）
npm run start:prod
# 等价：node --env-file=.env src/index.js

# 后台（nohup）
mkdir -p logs
nohup node --env-file=.env src/index.js >> logs/gateway.log 2>&1 &
echo $! > gateway.pid

# 或 PM2
pm2 start src/index.js --name jianyin-ws --node-args="--env-file=.env"
pm2 save && pm2 startup
```

健康检查：`curl http://127.0.0.1:8000/health`  
`NODE_ENV=production` 时 `demo-token` 接口不可用。请定期备份 `data/`。

## API 文档（Swagger）

启动后打开：

- Swagger UI：`http://127.0.0.1:8000/docs`
- OpenAPI JSON：`http://127.0.0.1:8000/openapi.json`

规范源码：`src/swagger/openapi.js`（与 `docs/api/protocol.md` 对齐）。WebSocket 帧细节以协议文档为准，Swagger 中仅含握手与事件摘要。

## 局域网访问

本机 IP 示例为 `192.168.1.100` 时：

- 健康检查：`http://192.168.1.100:8000/health`
- Swagger：`http://192.168.1.100:8000/docs`
- App WS：`ws://192.168.1.100:8000/ws/app?deviceId=...&protocolVersion=1&sessionId=...`，握手 Header：`Authorization: Bearer <jwt>`

请用 `ipconfig`（Windows）确认本机局域网 IP。Windows 防火墙需放行入站 TCP `8000`。

`POST /api/v1/sessions` 返回的 `wsUrl` 会按请求的 `Host` 头生成，客户端用局域网 IP 请求时即可得到 `ws://192.168.1.100:8000/ws/app`。

## 联调示例

```bash
# 1) health
curl http://127.0.0.1:8000/health

# 2a) register（或 login）
curl -s -X POST http://127.0.0.1:8000/api/v1/auth/register ^
  -H "Content-Type: application/json" ^
  -d "{\"phone\":\"13800138000\",\"password\":\"password1\",\"deviceId\":\"app-demo\"}"

# 2b) 或 debug demo token
curl -s -X POST http://127.0.0.1:8000/api/v1/auth/demo-token ^
  -H "Content-Type: application/json" ^
  -d "{\"role\":\"app\",\"deviceId\":\"app-demo\"}"

# 3) create session（把 TOKEN 换成上一步返回值）
curl -s -X POST http://127.0.0.1:8000/api/v1/sessions ^
  -H "Authorization: Bearer TOKEN" ^
  -H "Content-Type: application/json" ^
  -d "{\"usePhoneLandmarks\":true}"
```

连接 `/ws/app` 后发送 `{"type":"ping","protocolVersion":1,"ts":0}` 应收到 `pong`。  
连续发送约 8 帧 `landmarks`（1 秒内）会触发 mock 识别，下行 `recognition`、`speech`、`audio.header` + 二进制 PCM。

## 端点摘要

完整交互式列表见 `/docs`。

**REST**：`/health`、auth（send-otp / verify-otp / register / login / demo-token）、`/me`、`/history`、membership、`/devices`、`/gestures`、`/sessions…`

账号/历史/会员持久化在 `data/*.json`（无数据库）。JWT 密钥：`JWT_SECRET`。

**WS**：`/ws/app`、`/ws/edge`、`/ws/wearable`

识别：切段 + 特征 + 规则词表；配置 `LLM_API_KEY` 后，特征会送大模型译成中文（失败回退规则）。  
WS `gesture_skeleton_envelope_v1` 的 `kind:frame` 会投影为 landmarks 再进入同一管道。  
TTS 见 `src/pipeline/tts.js`。
