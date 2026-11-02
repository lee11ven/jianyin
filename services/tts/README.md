# services/tts —— 流式 TTS（规划目录）

本目录为**规划中的独立服务目录**（对应 `docs/design/系统架构/modules.md` 的仓库映射表）。

- **当前承载位置**：`websocket-server/src/pipeline/`（`tts.js` 合成与分片、`tts_queue.js` 发送调度）。
- **契约来源**：`docs/design/系统架构/architecture.md`「流式 TTS 落地（最小可用）」与 `docs/api/protocol.md` 的 `speech` / `audio.header` / 二进制音频帧。
- **可替换点**：`tts.js` 的 `synthesizePcmChunks(text, options)` 视为接口；接入真实合成器时，分片长度（100 ms）、`audio.header` 时序与按 `utteranceId` 串行规则不变。
- **迁移触发条件**：需要独立扩容、独立计费或接入第三方合成服务时，把合成与调度迁入本目录。