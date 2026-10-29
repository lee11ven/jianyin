# 系统架构（方案 A）

字段与 API 以 [../../api/protocol.md](../../api/protocol.md) 为准；连接行为见 [websocket.md](./websocket.md)。

## 目标态总览

```
┌─────────────────┐                      ┌──────────────────────────┐
│ Camera / Phone  │                      │   Cloud                  │
│ 本地 MediaPipe  │ ── landmarks (WS) ─► │  API + WebSocket Gateway │
│                 │                      │  Recognition (可替换)    │
└─────────────────┘                      │  Streaming TTS           │
┌─────────────────┐                      │  Gesture Library         │
│ Flutter App     │ ◄── text + audio ─── │                          │
│ 字幕 / 播音      │      (WS)            └────────────▲─────────────┘
└─────────────────┘                                   │
┌─────────────────┐                                   │
│ Wearable (P2)   │ ◄── audio (+ 契约) ───────────────┘
└─────────────────┘
```

- **主路径不上行原始视频**，从而降低云端带宽与解码压力。
- **一期最小闭环**：App 本地抽点 → WS 上行 → 识别 → 流式 TTS → WS 下行音频 + 字幕。
- **二期**：边缘设备本地抽点并连 WS；穿戴收听音频流；App 控制与字幕。

## 逻辑分层

| 层 | 职责 |
|----|------|
| 体验层 | 会话、字幕、播放 WS 音频流、连接状态、设备绑定 |
| 端侧感知层 | 摄像头预览（仅本地）+ MediaPipe 类关键点提取 |
| 接入层 | WebSocket：鉴权后长连接；按 `sessionId` 路由 |
| 控制面 | REST：token、建会话、词表、设备、历史 |
| 智能层 | 关键点序列 → 识别文本；流式 TTS |
| 设备层 | 边缘抽点；穿戴播音（二期） |

## 云端组件

| 组件 | 说明 |
|------|------|
| API | REST 鉴权与会话；WS 网关 |
| Recognition | 输入关键点窗口；演示/生产后端可替换 |
| Streaming TTS | 边合成边经 WS 下发二进制音频帧 |
| Gesture Library | CSL + `vocabVersion` |

**不部署视频媒体服务器**；云端不接收、不解码会话主路径视频。

## 端到端数据流

### 一期最小闭环

1. App 取 token → REST 创建会话 → 连接 `/ws/app`。
2. 本地相机预览；端侧输出手形、轨迹、身体锚点与非手控，按约 15–30 Hz 经 WS 发送 `landmarks`（`csl_channels_v1`）。
3. 云端滑动窗口按 `ts` 对齐各通道并识别 → `recognition`；流式 TTS → `audio` 二进制帧（带 `utteranceId`）。
4. App 显示字幕并实时播放音频流。
5. 结束会话 → 关 WS。

### 二期硬件路径

1. 边缘连 `/ws/edge`，本地抽点并上行 `landmarks`。
2. App 连 `/ws/app` 控制会话与收字幕；穿戴连 `/ws/wearable` 收音频（若在线）。
3. 云端识别与 TTS 逻辑同一期。

## 语音下行原则

| 路径 | 定位 |
|------|------|
| WS 二进制音频帧 + 流式 TTS | **正式主路径** |
| `speech` JSON 元数据 | `utteranceId`、文本对齐、播放控制 |
| 整段 `audioBase64` | 协议保留帧形状。一期 App 拒收，不入队 |

## 手语识别：演示 vs 生产

| 层级 | 输入 | 做法 | 评测 |
|------|------|------|------|
| 演示 | `csl_channels_v1` 多通道序列 | 轻量时序 + 有限词表；必须按 [算法/云端/滑动窗口识别.md](../算法/云端/滑动窗口识别.md) 消费 path/body/nonmanual；运动公式见客户端算法 | 冒烟 + 开声延迟 |
| 生产 | 同上（协议不变） | 更大模型 / 更多数据 | WER、P50/P95 |

## 安全与隐私

- REST / WS 使用 Bearer 或握手 token。
- 主路径无原视频出端，隐私面优于视频上云。
- 关键点与日志仍需脱敏；历史默认文本级 recognition。

## 相关文档

- [websocket.md](./websocket.md) · [modules.md](./modules.md) · [risks.md](./risks.md) · [../../api/protocol.md](../../api/protocol.md)
