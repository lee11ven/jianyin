# edge/simulator —— 边缘模拟器（一期建议）

伪造/回放 `landmarks`，用于验收 `/ws/edge` 与边缘互斥（`device_busy`）行为，不依赖真实硬件。

- 契约：`docs/api/protocol.md`（`/ws/edge` 握手与 `landmarks` 格式）。
- 行为要求：`docs/design/系统架构/websocket.md`（边缘互斥、心跳、空闲回收）。
- 现状：**未实现**（当前可用 `/ws/app` 路径与自测脚本覆盖主链路）。