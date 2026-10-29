# 模块职责与目标仓库结构

仅架构规划；本期不创建业务代码。协议见 [../../api/protocol.md](../../api/protocol.md)。

## 模块职责

### 1. Flutter App（一期必需）

**目录**：`apps/mobile/`

| 职责 | 说明 |
|------|------|
| 本地感知 | 相机预览 + 手形 / 轨迹 / 身体与非手控；算法见 [算法/客户端/index.md](../算法/客户端/index.md) |
| 连接 | REST 建会话；`/ws/app` 长连接 |
| 上行 | `landmarks` |
| 下行 | 字幕 + **二进制音频流**播放；抖动缓冲与串行策略见 [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md) |
| 非职责 | 不上行原始视频；不做云端级重推理 |

### 2. 云端 API / WS 网关（一期必需）

**目录**：`services/api/`

| 职责 | 说明 |
|------|------|
| REST | token、会话、词表、设备、历史 |
| WS | `/ws/app`、`/ws/edge`、`/ws/wearable` |
| 路由 | 按 `sessionId` 扇出 recognition/音频 |

### 3. 识别（一期必需，后端可替换）

**目录**：`services/inference/` — `csl_channels_v1` 窗口（手形、轨迹、身体、非手控）→ 文本 + `vocabVersion`。窗口对齐、特征契约与降级见 [算法/云端/滑动窗口识别.md](../算法/云端/滑动窗口识别.md)；运动描述与部位公式见 [算法/客户端/运动轨迹.md](../算法/客户端/运动轨迹.md)、[算法/客户端/多器官配合.md](../算法/客户端/多器官配合.md)。

### 4. 流式 TTS（一期必需）

**目录**：`services/tts/` — 流式出 **PCM s16le**（一期默认；经 WS 二进制下发）。Opus 非一期主路径。

### 5. 协议与词表

**目录**：`packages/proto/`

### 6. 边缘模拟器（一期建议）

**目录**：`edge/simulator/` — 伪造/回放 landmarks，验收 `/ws/edge`。

### 7. 硬件边缘（二期）

**目录**：`edge/agent/` — 本地抽点 + `/ws/edge`。

### 8. 穿戴（二期；一期仅契约）

**目录**：`edge/wearable/` — `/ws/wearable` 收音频流。

## 目标 Monorepo（规划）

```
apps/mobile/
services/api/                 # REST + WebSocket 网关
services/inference/
services/tts/
packages/proto/
edge/simulator/
edge/agent/
edge/wearable/
docs/design/ + docs/api/
```

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
