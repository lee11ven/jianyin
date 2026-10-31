# 一期冻结协议（protocolVersion: 1）

**本文是 REST 与 WebSocket 字段/帧格式的唯一事实来源。** 连接行为见 [../design/系统架构/websocket.md](../design/系统架构/websocket.md)。

方案 A：主路径传输**关键点 + 流式音频**，**不上行原始视频**。

扩展仅可增加可选字段；不兼容变更须提升 `protocolVersion`。

## 约定

| 平面 | 技术 | 用途 |
|------|------|------|
| 控制 | **REST + JSON** | 鉴权、会话、词表、设备、历史、会员 |
| 实时 | **WebSocket** | landmarks / 信封上行；recognition / 音频流下行 |

WebSocket 文本帧的 JSON **必须为压缩格式**（无空格/换行缩进）；坐标等浮点建议保留不超过 4 位小数。禁止 pretty-print 上行。

WS 文本帧公共字段：

```json
{
  "type": "event_name",
  "protocolVersion": 1,
  "ts": 1710000000000
}
```

---

## REST

Base URL：`http://<host>:<port>`（示例 `8000`）

| Method | Path | 鉴权 | 说明 |
|--------|------|------|------|
| GET | `/health` | 无 | 健康检查 |
| POST | `/api/v1/auth/register` | 无 | 手机号注册，返回 JWT |
| POST | `/api/v1/auth/login` | 无 | 手机号登录，返回 JWT |
| POST | `/api/v1/auth/demo-token` | 无 | 演示 JWT。仅 debug |
| GET | `/api/v1/me` | Bearer | 当前用户资料 |
| PATCH | `/api/v1/me` | Bearer | 更新 username / sex |
| GET | `/api/v1/history` | Bearer | 用户字幕历史（按日） |
| GET | `/api/v1/membership/plans` | Bearer | 会员套餐列表 |
| GET | `/api/v1/membership` | Bearer | 当前会员状态 |
| POST | `/api/v1/membership/subscribe` | Bearer | 开通套餐（无支付网关） |
| GET | `/api/v1/devices` | Bearer | 设备列表 |
| GET | `/api/v1/gestures` | Bearer | 词表（含 `vocabVersion`） |
| POST | `/api/v1/sessions` | Bearer | 创建会话 |
| GET | `/api/v1/sessions/{id}` | Bearer | 会话状态 |
| POST | `/api/v1/sessions/{id}/stop` | Bearer | 结束会话 |
| GET | `/api/v1/sessions/{id}/history` | Bearer | 该会话文本历史 |

鉴权：除表中标注「无」的接口外，**必须**携带：

```http
Authorization: Bearer <jwt>
```

服务端解码 JWT，用 `userId` 界定数据归属。token 不得写入日志。不增加 refresh；过期后重新登录。

### JWT

HS256。payload 至少包含：

| 字段 | 说明 |
|------|------|
| `userId` | 用户 ID |
| `username` | 显示名 |
| `phone` | 手机号 |
| `sex` | `male` \| `female` \| `unknown` |
| `role` | `app` \| `edge` \| `wearable` |
| `deviceId` | 可选；本机设备 ID |
| `iat` / `exp` | 标准声明 |

`deviceId` 是客户端生成的本机随机 ID，不是账号。同一 `userId` 只保留最新的 App 会话；新会话建立后，旧 App 连接收到 `session_replaced`。

### Token 响应（共用）

`register`、`login`、`demo-token` 成功时均返回同一形状：

```json
{
  "token": "<jwt>",
  "role": "app",
  "deviceId": "app-xxx",
  "protocolVersion": 1,
  "expiresInSec": 86400,
  "user": {
    "userId": "u-xxx",
    "username": "林晓",
    "phone": "13800138000",
    "sex": "unknown",
    "plan": "free"
  }
}
```

### POST `/api/v1/auth/register`

```json
{
  "phone": "13800138000",
  "password": "at-least-8-chars",
  "username": "optional",
  "sex": "unknown",
  "deviceId": "optional-string"
}
```

- `phone`：中国大陆 11 位手机号（`1` 开头）。
- `password`：至少 8 字符。确认密码仅客户端校验，不上行。
- `username`：可选；缺省为 `用户` + 手机后四位。
- `sex`：可选；`male` \| `female` \| `unknown`；缺省 `unknown`。
- 成功：`201` + Token 响应（`role` 固定 `app`）。
- 失败：`400` `{ "code": "invalid_phone" | "weak_password" | "invalid_sex", "message": "..." }`；`409` `{ "code": "phone_taken", "message": "..." }`。

本版不定义验证码、邮箱或第三方登录字段。

### POST `/api/v1/auth/login`

```json
{
  "phone": "13800138000",
  "password": "at-least-8-chars",
  "deviceId": "optional-string"
}
```

- 成功：`200` + Token 响应。
- 失败：`400` `{ "code": "invalid_phone", "message": "..." }`；`401` `{ "code": "invalid_credentials", "message": "..." }`。

### POST `/api/v1/auth/demo-token`

仅 debug 构建。release 构建不得调用。

```json
{ "role": "app", "deviceId": "optional-string" }
```

`role`：`app` | `edge` | `wearable`。成功：`200` + Token 响应（演示用户写入 JWT）。

### GET `/health`

```json
{ "status": "ok", "protocolVersion": 1 }
```

### GET `/api/v1/me`

```json
{
  "userId": "u-xxx",
  "username": "林晓",
  "phone": "13800138000",
  "sex": "female",
  "plan": "pro_month",
  "planExpiresAt": 1735689600000
}
```

`plan`：`free` \| 套餐 `id`。无会员或已过期时为 `free`，`planExpiresAt` 可为 `null`。

### PATCH `/api/v1/me`

```json
{ "username": "新昵称", "sex": "male" }
```

字段均可选；只更新提供的键。成功返回与 `GET /me` 相同形状。

### GET `/api/v1/history`

Query 可选：`from`、`to`（`YYYY-MM-DD`，含端点）。

```json
{
  "days": [
    {
      "iso": "2026-10-25",
      "label": "今天",
      "items": [
        { "id": "h-xxx", "time": "10:24", "text": "你好", "ts": 1710000000000 }
      ]
    }
  ]
}
```

仅返回当前 JWT `userId` 的记录。

### GET `/api/v1/membership/plans`

```json
{
  "plans": [
    {
      "id": "free",
      "title": "免费版",
      "price": "¥0",
      "unit": "/ 月",
      "features": ["每日有限识别时长", "标准播报音质", "最近 7 天字幕历史"],
      "featured": false
    }
  ]
}
```

### GET `/api/v1/membership`

```json
{
  "planId": "free",
  "title": "免费版",
  "expiresAt": null
}
```

### POST `/api/v1/membership/subscribe`

```json
{ "planId": "pro_month" }
```

无支付网关；服务端直接写入会员状态。不可订阅 `free`（回退用到期自然失效）。成功返回与 `GET /membership` 相同形状。失败：`400` `{ "code": "invalid_plan", "message": "..." }`。

### GET `/api/v1/gestures`

```json
{
  "vocabVersion": "2026.04.1",
  "language": "CSL",
  "gestures": [
    { "id": "hello", "text": "你好", "aliases": ["您好"] }
  ]
}
```

### POST `/api/v1/sessions`

```json
{
  "edgeDeviceId": "edge-001",
  "usePhoneLandmarks": true
}
```

```json
{
  "sessionId": "sess-xxx",
  "protocolVersion": 1,
  "wsUrl": "wss://example/ws/app"
}
```

创建成功后，同一 `userId` 上更早的 App 连接收到 WS `error.code = session_replaced`。边缘忙：HTTP `409`，`{ "code": "device_busy", "message": "..." }`。该错误拒绝后来者，不踢掉已附着的边缘会话。

---

## WebSocket

### 端点

| 路径 | 角色 | 一期 |
|------|------|------|
| `/ws/app` | App | 必需 |
| `/ws/edge` | 边缘 / simulator | 契约必需 |
| `/ws/wearable` | 穿戴 | 契约冻结 |

握手：

| 位置 | 字段 |
|------|------|
| **Header** | `Authorization: Bearer <jwt>`（必需） |
| Query | `deviceId`、`protocolVersion=1`；一期 App 另带 REST 返回的 `sessionId` |

**禁止**在 Query 中传 `token`。

### 文本事件

| type | 方向 | 说明 |
|------|------|------|
| `ping` / `pong` | 双向 | 心跳 |
| `session.start` / `session.stop` | 非一期 App | 一期 App 不发送。会话只由 REST 建立和结束 |
| `session.started` / `session.stopped` | 云 → App | 确认 |
| `landmarks` | App 或边缘 → 云 | 关键点帧 |
| `recognition` | 云 → App | 字幕 |
| `speech` | 云 → App / 穿戴 | 播音元数据（对齐二进制音频） |
| `device.status` | 边缘/穿戴 → 云 | 状态 |
| `device.online` | 云 → App | 上下线 |
| `error` | 云 → 客户端 | 错误 |
| `audio.header` | 云 → 客户端 | 随后二进制音频帧的说明（可选，见下） |

### `error.code`

| code | 含义 |
|------|------|
| `unauthorized` | 鉴权失败或过期 |
| `device_busy` | 边缘已被占用 |
| `session_not_found` | sessionId 无效 |
| `rate_limited` | 过载 |
| `internal` | 内部错误 |
| `session_replaced` | 同一账号已有更新的 App 会话，本连接被替换 |

### `landmarks`

线上传输示例（压缩 JSON，单行无空白；文档中的多行写法仅便于阅读）：

```json
{"type":"landmarks","protocolVersion":1,"ts":0,"sessionId":"sess-xxx","schema":"mediapipe_hands_v1","points":[{"x":0.12,"y":0.34,"z":0.01,"v":1}]}
```

- `schema` 标识关键点布局。`mediapipe_hands_v1` 只表示双手 42 点，语义保持不变。
- 轨迹、身体锚点与非手控使用新 schema 名 `csl_channels_v1`（见下）。未知通道忽略。
- **禁止**在主路径事件中附带 JPEG/视频 payload。

### `landmarks` · `csl_channels_v1`

手形、轨迹、身体与非手控分通道。某一拍没有的通道省略。算法语义见 [../design/算法/客户端/运动轨迹.md](../design/算法/客户端/运动轨迹.md)、[../design/算法/客户端/多器官配合.md](../design/算法/客户端/多器官配合.md)。

```json
{
  "type": "landmarks",
  "protocolVersion": 1,
  "ts": 0,
  "sessionId": "sess-xxx",
  "schema": "csl_channels_v1",
  "hands": {
    "schema": "mediapipe_hands_v1",
    "points": [
      { "x": 0.12, "y": 0.34, "z": 0.01, "v": 1.0 }
    ]
  },
  "path": {
    "space": "body",
    "anchor": true,
    "gap": false,
    "left": {
      "wrist": { "x": 0.10, "y": 1.40, "z": 0.80, "v": 0.95 },
      "palm": { "x": 0.12, "y": 1.55, "z": 0.90, "v": 0.90 },
      "tips": {
        "thumb": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
        "index": { "x": 0.18, "y": 1.90, "z": 1.00, "v": 0.88 },
        "middle": { "x": 0.10, "y": 1.95, "z": 1.00, "v": 0.86 },
        "ring": { "x": 0.02, "y": 1.88, "z": 0.98, "v": 0.84 },
        "pinky": { "x": -0.04, "y": 1.75, "z": 0.96, "v": 0.80 }
      }
    },
    "right": {
      "wrist": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
      "palm": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
      "tips": {
        "thumb": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
        "index": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
        "middle": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
        "ring": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 },
        "pinky": { "x": 0.0, "y": 0.0, "z": 0.0, "v": 0.0 }
      }
    }
  },
  "body": {
    "nose": { "x": 0.50, "y": 0.22, "z": -0.10, "v": 0.98 },
    "shoulderL": { "x": 0.38, "y": 0.42, "z": 0.00, "v": 0.97 },
    "shoulderR": { "x": 0.62, "y": 0.42, "z": 0.00, "v": 0.97 },
    "frame": {
      "origin": { "x": 0.50, "y": 0.42, "z": 0.00 },
      "shoulderWidth": 0.24,
      "right": { "x": 1.0, "y": 0.0, "z": 0.0 },
      "up": { "x": 0.0, "y": -1.0, "z": 0.0 },
      "zSign": 1
    }
  },
  "nonmanual": {
    "head": { "pitch": 0.10, "yaw": -0.05, "roll": 0.02, "v": 0.93 },
    "mouth": { "open": 0.35, "round": 0.10, "spread": 0.20, "v": 0.90 },
    "brow": { "raise": 0.15, "furrow": 0.05, "v": 0.88 },
    "eye": { "openL": 0.80, "openR": 0.78, "v": 0.86 }
  }
}
```

- `hands.points` 定长 42，布局与 `mediapipe_hands_v1` 相同。手形被拒时省略整个 `hands`。
- `path.gap = true` 时保留该拍 `ts`，点对象可省略。`path.space` 为 `body` 或 `image`；`anchor = false` 时坐标系是图像，云端不算身体部位。
- `body` 的点锁定为 `nose`、`eyeL`、`eyeR`、`earL`、`earR`、`mouthL`、`mouthR`、`shoulderL`、`shoulderR`、`elbowL`、`elbowR`、`wristL`、`wristR`、`hipL`、`hipR`，每点 `{x,y,z,v}`，坐标为图像归一化。`frame` 锁定为 `origin`、`shoulderWidth`、`right`、`up`、`zSign`。肩或鼻不足以建系时省略整个 `body`。示例只写出鼻、双肩与 `frame`，其余点同一结构。部位名与换算见多器官配合算法。
- `nonmanual` 可以低于轨迹节拍出现；没有脸部结果则省略。
- 方向、路径形状、重复次数、部位名、点头摇头由云端窗口计算，不是本事件字段。窗口契约见 [../design/算法/云端/滑动窗口识别.md](../design/算法/云端/滑动窗口识别.md)；部位查询点跟随段 `trace`（指尖段用该指尖，见多器官 / 运动轨迹算法）。

### `recognition`

```json
{
  "type": "recognition",
  "protocolVersion": 1,
  "ts": 0,
  "sessionId": "sess-xxx",
  "utteranceId": "utt-xxx",
  "text": "你好",
  "confidence": 0.91,
  "glossIds": ["hello"],
  "vocabVersion": "2026.04.1"
}
```

### `speech`（元数据）

正式默认：

```json
{
  "type": "speech",
  "protocolVersion": 1,
  "ts": 0,
  "sessionId": "sess-xxx",
  "utteranceId": "utt-xxx",
  "text": "你好",
  "delivery": "ws_binary_audio",
  "mimeType": "audio/pcm",
  "sampleRate": 16000,
  "channels": 1,
  "encoding": "s16le"
}
```

随后同一连接上下发**二进制音频帧**（见下）。`delivery` 必须为 `ws_binary_audio` 作为正式路径。

协议保留下面的帧形状，便于识别。一期 App 不实现这条路径；收到 `inline_fallback` 或 `audioBase64` 时拒收该句，不入队。

```json
{
  "type": "speech",
  "protocolVersion": 1,
  "ts": 0,
  "sessionId": "sess-xxx",
  "utteranceId": "utt-xxx",
  "text": "你好",
  "delivery": "inline_fallback",
  "audioBase64": "<base64>",
  "mimeType": "audio/wav"
}
```

### 二进制音频帧

推荐两种实现选一（文档冻结推荐 **A**）：

**A. `audio.header` + 裸二进制（推荐）**

1. 先发文本帧 `audio.header`：

```json
{
  "type": "audio.header",
  "protocolVersion": 1,
  "ts": 0,
  "sessionId": "sess-xxx",
  "utteranceId": "utt-xxx",
  "seq": 0,
  "mimeType": "audio/pcm",
  "sampleRate": 16000,
  "channels": 1,
  "encoding": "s16le",
  "last": false
}
```

2. 紧接着一条 **WebSocket Binary** 帧：原始 PCM/Opus 载荷。  
3. 流式多片递增 `seq`；最后一片 `last: true`（可空 binary）。

**B. 定长头 + binary（可选）**  
实现阶段若需更省往返，可用固定二进制头携带 `utteranceId` 哈希与 `seq`；须在实现说明中写死布局，且不改变文本事件语义。

客户端：按 `utteranceId` 组装播放队列；小缓冲边收边播。

---

## 会话流程（摘要）

1. Token（login/register）→ `POST /sessions` → 连接对应 `/ws/*`（Header Bearer）。
2. 端侧上行 `landmarks`。
3. 云端 `recognition` + `speech`（`ws_binary_audio`）+ 二进制音频；字幕写入用户历史。
4. `POST .../stop` 或 `session.stop` → 断开。

## 版本策略

- `protocolVersion: 1` 冻结。
- 兼容：新可选字段；忽略未知字段。
- 关键点 `schema` 演进用新 schema 名，勿复用旧名改语义。
