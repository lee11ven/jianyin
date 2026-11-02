# edge/agent —— 硬件边缘（二期）

本地抽点并连 `/ws/edge` 的设备侧代理，替代一期「手机采集」路径。

- 契约：`docs/api/protocol.md`（`/ws/edge`、`landmarks`、`device.status`）。
- 算法边界：`docs/design/算法/客户端/index.md`（抽帧、骨架、轨迹、多器官；边缘复用同一算法边界）。
- 现状：**未实现**（二期范围）。