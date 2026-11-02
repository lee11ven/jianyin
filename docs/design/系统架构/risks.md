# 风险、开放问题与已采纳优化

## 已采纳优化

| # | 结论 |
|---|------|
| 1 | **方案 A**：端侧关键点上行，主路径**不上行原始视频**，降低云带宽/解码/GPU 压力 |
| 2 | **实时通道仅 WebSocket**：关键点、字幕、流式音频同体系；**文档与实现均不采用其他实时媒体栈**，避免污染 |
| 3 | 语音正式路径：`ws_binary_audio`。一期 App 拒收 `audioBase64` / `inline_fallback` |
| 4 | 一期最小闭环 = App + 云；穿戴只冻契约 |
| 5 | 演示/生产识别后端可替换；`vocabVersion` + 评测 |
| 6 | 字段唯一源：`docs/api/protocol.md` |
| 7 | **多句 TTS 严格串行**：按 `utteranceId` FIFO；不允许 barge-in 打断当前句（算法见 [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md)） |
| 8 | **音频编码默认 PCM s16le / 16 kHz / mono**；一期不实现 Opus 解码主路径 |
| 9 | **关键点完整通道为 `csl_channels_v1`**：手形、轨迹、身体锚点、非手控。肩或鼻不可用时退回手形，轨迹改用图像坐标 |

## 失败与边界场景

| 场景 | 期望行为 |
|------|----------|
| 弱网 | landmarks/音频丢旧保实时；UI 显示重连 |
| Token 过期 | 关 WS；重新登录。不增加 refresh，也不回退 demo-token |
| 边缘互斥 | 同一 `edgeDeviceId` 拒绝后来者，`device_busy`。不踢掉已附着的边缘会话 |
| App 会话互斥 | 同一账号踢旧。旧 App 连接收到 `session_replaced` 后清空播音 |
| 端侧抽点失败 | 提示权限/光线/人手出框；不回退为视频上云 |
| 字幕与声音错位 | `utteranceId`；串行播句 |
| 穿戴离线 | 不阻断 App 播音 |

## 隐私与合规

主路径无原视频出端；关键点与日志仍需控制留存；历史默认文本。

**实现现状（2026-11）**：运行期数据当前以 JSON 文件存放在**仓库内**（`websocket-server/data/{users,membership,history}.json`，含手机号与密码哈希），与「控制留存 / 最小化」不一致，须移出版本库（保留示例文件 + `.gitignore`）并限制访问；`GET /api/v1/devices` 目前返回全局设备视图，未按账号过滤（见 [../../api/protocol.md](../../api/protocol.md)「实现现状」）。

## 开放问题

1. 设备互斥：已决。边缘拒绝后来者（`device_busy`）；同一账号的 App 会话踢旧（`session_replaced`）。
2. 穿戴与 App 是否允许双端同时出声？

## 相关文档

- [architecture.md](./architecture.md) · [websocket.md](./websocket.md) · [roadmap.md](./roadmap.md)
- [算法/客户端/流式语音播放.md](../算法/客户端/流式语音播放.md) · [算法/客户端/运动轨迹.md](../算法/客户端/运动轨迹.md) · [算法/客户端/多器官配合.md](../算法/客户端/多器官配合.md)
