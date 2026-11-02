# 可扩展性与容量实测

## 1. 压测结果（单实例，50 并发）

- 脚本：`websocket-server/scripts/load-test.mjs`
- 复现：`node src/index.js` 后执行 `node scripts/load-test.mjs --sessions 50 --seconds 6`
- 环境：本机回环、Node v22.22.3、单进程

| 观测项 | 实测 |
|--------|------|
| 并发会话 | 50（全部建立成功并收到音频） |
| 上行消息 | 6,272 条（≈ 924.9 msg/s） |
| `recognition` | 100 条 |
| `audio.header` | 600 片 |
| 音频字节 | 1,664,000 字节（PCM s16le） |
| 消息延迟 P50 / P95 / Max | 17 ms / **40 ms** / 52 ms |
| TTS 首片 P50 / P95 | 23 ms / **40 ms** |

**结论**：单实例在 50 并发 × 25 Hz 上行下，消息 P95 40 ms、TTS 首片 P95 40 ms，均在门限内
（P95 ≤ 100 ms、首片 ≤ 300 ms），且无会话掉线。详见 [metrics.md](./metrics.md)。

## 2. 存储与状态：可替换适配层

会话与账号此前直接读写 JSON 文件，现引入**存储适配层**，把「存取实现」与「业务逻辑」分开：

- 适配层：`websocket-server/src/registry/store_adapter.js`
  - `STORAGE_BACKEND=json`（默认）：单机文件，落 `websocket-server/data/`（不入版本库）
  - `STORAGE_BACKEND=memory`：进程内内存，用于压测与无状态部署验证
  - `external`：预留外部存储（Redis / SQL）接入点，实现同一 `read/write/update` 契约即可替换
- 使用方：`src/data/json_store.js`（账号、会员、历史、词表读取）统一经由适配层访问。

> 迁移到多实例时：把 `external` 适配器接到共享存储，并把**会话路由改为粘性**（同一 `sessionId`
> 落到同一实例）或把会话状态外移；WS 网关是无状态的，扩容只需多实例 + 会话亲和。

## 3. 多实例方案（已定，未在本机部署验证）

| 维度 | 方案 | 现状 |
|------|------|------|
| 无状态部分（REST / WS 网关 / 识别 / TTS） | 多实例横向扩容；`/ws/app` 走会话亲和（`sessionId` 粘性） | 代码已就绪（无进程内跨实例依赖） |
| 会话状态 | 外移共享存储（Redis）或保持粘性路由 | 适配层接口已预留（`external`） |
| 账号 / 会员 / 历史 | 经适配层落共享存储 | 同上；当前默认 JSON 单机 |
| 累积数据量 | 历史按用户 + 日期分片；保留期由产品策略决定 | 未压测 |

## 4. 复现与回归

```bash
# 1) 起网关
cd websocket-server && node src/index.js &

# 2) 50 并发压测（输出 JSON 摘要）
node scripts/load-test.mjs --sessions 50 --seconds 6

# 3) 内存后端（验证无状态路径）
STORAGE_BACKEND=memory PORT=8400 node src/index.js &
```

> 说明：压测为本机回环，用于**容量口径与回归**；生产容量需在同规格环境复跑后回填本表。