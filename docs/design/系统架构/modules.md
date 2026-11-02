# 模块职责与目标仓库结构

各模块的职责与**落地位置**。一期客户端与网关已落地，二期模块仍为规划；二者不一致时以实际仓库位置为准。协议见 [../../api/protocol.md](../../api/protocol.md)。

## 仓库映射（规划目录 → 实际位置）

| 规划目录 | 实际仓库位置 | 状态 |
|----------|--------------|------|
| `apps/mobile/` | `jianyin_app/`（Flutter；客户端源码在 `lib/`） | 已落地 |
| `services/api/` | `websocket-server/`（Node：Express REST + `ws` 网关） | 已落地 |
| `services/inference/` | 未独立建目录；当前占位 `websocket-server/src/pipeline/recognition.js` | 占位 |
| `services/tts/` | 未独立建目录；当前占位 `websocket-server/src/pipeline/tts.js` | 占位 |
| `packages/proto/` | 契约由 `docs/api/protocol.md` 承载；客户端投影在 `jianyin_app/lib/envelope/` | 以文档 + 代码承载 |
| `edge/simulator/` | 未创建 | 待建 |
| `edge/agent/`、`edge/wearable/` | 未创建 | 二期 |

**说明**：仓库当前是「客户端 + 网关」两目录形态，**未**采用下文 Monorepo 的 `apps/` / `services/` 布局；上表为唯一权威映射。新增独立服务时再按 Monorepo 布局迁入。

## 模块职责

### 1. Flutter App（一期必需）

**目录**：`apps/mobile/`（实际：`jianyin_app/`）

| 职责 | 说明 |
|------|------|
| 本地感知 | 相机预览 + 手形 / 轨迹 / 身体与非手控；算法见 [算法/客户端/index.md](../算法/客户端/index.md) |
| 连接 | REST 建会话；`/ws/app` 长连接 |
| 上行 | `landmarks` |
| 下行 | 字幕 + **二进制音频流**播放；抖动缓冲与串行策略见 [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md) |
| 非职责 | 不上行原始视频；不做云端级重推理 |

模块内部结构与落地路径见 [客户端APP/modules.md](../客户端APP/modules.md)。

### 2. 云端 API / WS 网关（一期必需）

**目录**：`services/api/`（实际：`websocket-server/`）

| 职责 | 说明 |
|------|------|
| REST | token、会话、词表、设备、历史 |
| WS | `/ws/app`、`/ws/edge`、`/ws/wearable` |
| 路由 | 按 `sessionId` 扇出 recognition/音频 |

当前实现要点：REST 见 `websocket-server/src/rest/routes.js`，WS 网关见 `src/ws/gateway.js`，会话存储见 `src/session/store.js`（进程内 Map + JSON 文件）。

### 3. 识别（一期必需，后端可替换）

**目录**：`services/inference/`（当前占位：`websocket-server/src/pipeline/recognition.js`）— `csl_channels_v1` 窗口（手形、轨迹、身体、非手控）→ 文本 + `vocabVersion`。窗口对齐、特征契约与降级见 [算法/云端/滑动窗口识别.md](../算法/云端/滑动窗口识别.md)；运动描述与部位公式见 [算法/客户端/运动轨迹.md](../算法/客户端/运动轨迹.md)、[算法/客户端/多器官配合.md](../算法/客户端/多器官配合.md)。最小可用实现与替换路径见该云端算法文档「一期最小可用实现」。

### 4. 流式 TTS（一期必需）

**目录**：`services/tts/`（当前占位：`websocket-server/src/pipeline/tts.js`）— 流式出 **PCM s16le**（一期默认；经 WS 二进制下发）。Opus 非一期主路径。落地要求（分片、首包、与 `speech`/`audio.header` 的对齐）见 [architecture.md](./architecture.md)。

### 5. 协议与词表

**目录**：`packages/proto/`（实际：契约 `docs/api/protocol.md`；词表 `websocket-server/src/data/gestures.json`）

### 6. 边缘模拟器（一期建议）

**目录**：`edge/simulator/`（未创建）— 伪造/回放 landmarks，验收 `/ws/edge`。

### 7. 硬件边缘（二期）

**目录**：`edge/agent/`（未创建）— 本地抽点 + `/ws/edge`。

### 8. 穿戴（二期；一期仅契约）

**目录**：`edge/wearable/`（未创建）— `/ws/wearable` 收音频流。

## 目标 Monorepo（规划；当前未采用）

```
apps/mobile/                  # 实际：jianyin_app/
services/api/                 # 实际：websocket-server/（REST + WebSocket 网关）
services/inference/           # 未独立建目录
services/tts/                 # 未独立建目录
packages/proto/               # 未独立建目录（契约在 docs/api/）
edge/simulator/
edge/agent/
edge/wearable/
docs/design/ + docs/api/
```

上表与「仓库映射」一致；迁移时以映射表为准逐项搬迁。

**不再规划**独立视频媒体服务目录。

## 依赖

```
App/Edge ── landmarks (WS) ──► API/WS Gateway ──► Inference
                                      │
                                      └──► Streaming TTS ── audio+text (WS) ──► App/Wearable
```

## 相关文档

- [architecture.md](./architecture.md) · [websocket.md](./websocket.md) · [roadmap.md](./roadmap.md) · [risks.md](./risks.md)
- [算法/客户端/index.md](../算法/客户端/index.md)（本地感知：抽帧与骨架；下行播音总述）
- [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md)（流式 PCM 播报算法）
- [客户端APP/modules.md](../客户端APP/modules.md)（客户端模块职责与落地路径）