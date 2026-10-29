# ws/

`/ws/app` 连接与帧路由。

握手：`Authorization: Bearer <jwt>` Header；Query 仅 `deviceId`、`protocolVersion`、`sessionId`。

一期 App **不**发送 `session.start` / `session.stop`。
