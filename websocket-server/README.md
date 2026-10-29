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

## 局域网访问

本机 IP 示例为 `192.168.1.100` 时：

- 健康检查：`http://192.168.1.100:8000/health`
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

**REST**：`/health`、auth（register/login/demo-token）、`/me`、`/history`、membership、`/devices`、`/gestures`、`/sessions…`

账号/历史/会员持久化在 `data/*.json`（无数据库）。JWT 密钥：`JWT_SECRET`。

**WS**：`/ws/app`、`/ws/edge`、`/ws/wearable`

识别与 TTS 为演示 mock，可替换 `src/pipeline/recognition.js` 与 `src/pipeline/tts.js`。
