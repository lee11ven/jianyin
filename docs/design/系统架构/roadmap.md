# 非功能指标、评测与里程碑

本期为架构文档；**不含编码任务**。

## 非功能指标（MVP）

| 类别 | 指标 |
|------|------|
| 开声延迟 | 识别出词后 **&lt; 1.5s** 开始播报；记 P50/P95 |
| TTS 首包 | 流式；经 WS 二进制尽快首包 |
| 关键点上行 | 约 15–30 Hz；积压丢旧 |
| 音频下行 | WS 二进制 PCM/Opus；客户端小抖动缓冲边收边播 |
| 连接 | 心跳 15s；死连接 45s；退避重连 ≤30s |
| 协议 | `protocolVersion: 1`；`delivery=ws_binary_audio` 默认 |
| 成本 | 主路径**无视频进云**；云侧重在识别 + TTS |

## 识别评测

| 层级 | 门禁 |
|------|------|
| 演示 | 有字幕 + WS 音频可播；延迟达标 |
| 生产 | WER（或等价）+ `vocabVersion`；P95 延迟 |

## 架构文档里程碑（本期）

| 文档 | 说明 |
|------|------|
| [index.md](./index.md) | 总览（方案 A） |
| [architecture.md](./architecture.md) | 架构 |
| [websocket.md](./websocket.md) | WS 行为 |
| [modules.md](./modules.md) | 模块 |
| [risks.md](./risks.md) | 风险 |
| [../../api/protocol.md](../../api/protocol.md) | 契约 |
| 本文 | 指标与里程碑 |

## 实现期里程碑（日后）

### 第一期

| 阶段 | 目标 |
|------|------|
| P1-0 | 骨架与契约 |
| P1-1 | REST + `/ws/app|edge|wearable` |
| P1-2 | 关键点识别 + 流式 TTS 二进制下行 |
| P1-3 | Flutter：本地 MediaPipe + 播 WS 音频 |
| P1-4 | edge-simulator / wearable mock |

**一期完成判据**：App 演示「本地抽点 → 字幕 → WS 音频流」；**无视频推流依赖**。

### 第二期

边缘本地抽点；穿戴收音频；App 控制与字幕。

## 不在本期范围

业务代码、模型训练。生产账号、发布和运维的实现不在本期编码，边界见 [客户端APP/roadmap.md](../客户端APP/roadmap.md)。

## 相关文档

- [index.md](./index.md) · [risks.md](./risks.md) · [../../api/protocol.md](../../api/protocol.md)
