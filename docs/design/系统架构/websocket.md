# WebSocket 会话与语音流行为

**本文只描述连接与播放行为。** 字段与帧格式以 [../../api/protocol.md](../../api/protocol.md) 为准。

## 角色与端点

| 角色 | 路径 | 一期 | 说明 |
|------|------|------|------|
| App | `/ws/app` | **必需** | 会话控制、上行 landmarks（手机采帧时）、收字幕与音频 |
| 边缘 | `/ws/edge` | 契约必需 / 客户端可选 | 上行 landmarks；simulator 或二期硬件 |
| 穿戴 | `/ws/wearable` | 仅契约 | 收音频流；一期 mock |

握手 Query：`token`、`deviceId`、`protocolVersion=1`。

## 通道内容

| 方向 | 内容 |
|------|------|
| 上行 | JSON：`landmarks`、`ping`；另有信封**身份消息**（`envelope: "gesture_skeleton_envelope_v1"` + `kind: "catalog"`，无 `type`，仅用于对齐身份与日志，不参与识别）。一期 App 不发送 `session.start` / `session.stop`。`device.status` 仅边缘/穿戴 |
| 下行 | JSON：`recognition`、`speech`（元数据）、`error`、`device.online` |
| 下行 | **二进制帧**：流式 TTS 音频（正式播音路径） |

同一条 WebSocket 连接混合文本帧与二进制帧；二进制帧前用短 JSON 或约定帧头关联 `utteranceId`（详见协议）。

## 时序

```
App                   Gateway                 Inference/TTS
  |-- REST 建会话 ----->|                         |
  |-- WS connect ------>|                         |
  |-- landmarks* ------>|------ 窗口 ----------->|
  |                     |<----- text ------------|
  |                     |------ 流式 TTS ------- >|
  |<-- recognition -----|                         |
  |<-- audio binary ----|                         |
  |-- REST stop ------->|                         |
```

## 低延迟播音

1. 流式 TTS，首包即下行，勿等整段文件。
2. 客户端维护 **小抖动缓冲**（约 60–150ms 量级起调），边收边播。
3. 多句按 `utteranceId` 串行；避免重叠播放。
4. 弱网：允许丢弃过旧音频块保实时；字幕仍可保留。

端侧接收、水位、欠载与会话清空等算法细节见 [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md)。

## 会话规则

- 一期 App 只走 REST 建停会话，握手必须带 `sessionId`。不发送 `session.start` / `session.stop`。
- 边缘互斥：同一 `edgeDeviceId` 同时一会话；后来者收到 `device_busy`，已附着的会话继续。
- App 会话互斥：同一账号只保留最新 App 会话。新会话建立后，旧 App 连接收到 `session_replaced`。
- 心跳 15s；死连接 45s；断线指数退避重连（上限 30s）。
- 空闲超时建议 10 分钟无 landmarks 且无控制消息则回收。

## 关键点上行建议

- 频率：15–30 Hz（识别侧可再抽稀）。
- 内容：`csl_channels_v1` 的手形、轨迹、身体锚点、非手控；带 `ts`、`sessionId`。缺锚点时可以只有手形。旧 `mediapipe_hands_v1` 仍表示纯 42 点。
- 背压：活动段轨迹均匀抽稀；手形与非手控可先降频。静默段可整段不发。

## 相关文档

- [architecture.md](./architecture.md) · [risks.md](./risks.md) · [../../api/protocol.md](../../api/protocol.md)
- [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md)
