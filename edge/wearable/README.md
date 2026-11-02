# edge/wearable —— 穿戴（二期；一期仅契约）

连 `/ws/wearable` 收听 WS 音频流；一期只冻结契约并用 mock 验收。

- 契约：`docs/api/protocol.md`（`/ws/wearable`、`speech`、`audio.header`、二进制音频帧）。
- 会话规则：`docs/design/系统架构/websocket.md`（穿戴离线不阻断 App 播音）。
- 现状：**未实现**（二期范围；一期完成判据不依赖穿戴在线）。