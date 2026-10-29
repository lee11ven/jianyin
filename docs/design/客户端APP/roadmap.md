# Flutter App 里程碑与验收

> 一期 App 的实现阶段里程碑与验收指标；非功能总览见 [系统架构/roadmap.md](../系统架构/roadmap.md)。验收口径与 [index.md](./index.md) 相同。

## 实现期里程碑

| 阶段 | 目标 | 交付物 |
|------|------|--------|
| **P1-0** | 骨架与契约 | envelope catalog；身体、轨迹、手形的身份；SDK 接入 MediaPipe |
| **P1-1** | REST + /ws/app + Home 生命周期 | token、进 Home 建连、离 Home/退出全停、心跳、仅 Home 内重连。不发送 session.start / session.stop |
| **P1-2** | 多通道上行 | 多器官、轨迹、帧手势；信封产出 `csl_channels_v1` 并 WS 上行 |
| **P1-3** | 播音下行 | Recv + Asm + JitterBuffer + Player；UI 字幕。只接受 ws_binary_audio |
| **P1-4** | 联调依赖 | 边缘模拟器与穿戴 mock 在 [系统架构/roadmap.md](../系统架构/roadmap.md)，不是 App 模块 |

### P1-0 进度（仓库）

架构评估锁定三支路 + 信封，不推倒重来。`jianyin_app` 已落：

| 模块 | 路径 | 状态 |
|------|------|------|
| 信封 catalog / 打包 | `lib/envelope/` | 身份与 `csl_channels_v1` 投影已编码 |
| 抽帧时钟 | `lib/camera/` | Idle/Active + S 门控；Home `startImageStream` |
| 多器官 | `lib/body/` | MediaPipe Pose 鼻肩建系（Face/`nonmanual` 延后） |
| 轨迹 | `lib/trajectory/` | 腕 path + gap；Pose 腕，Hands 腕次拍注入 |
| 手形 / 槽位 | `lib/skeleton/` | MediaPipe Hands 42 点 + track 槽位融合 |
| 原生桥 | `lib/native/` + Android/iOS | MethodChannel Pose/Hands，RGBA 契约 |
| 同拍调度 | `lib/perception/` | `body → path → hands → pack`；`PerceptionRuntime` |

下一步（P1-1→P1-2）：`lib/ws` 建连并将 `csl_channels_v1` 真上行。云端窗口消费见 [算法/云端/滑动窗口识别.md](../算法/云端/滑动窗口识别.md)。

## 一期完成判据

> Flutter App 演示「**本地多通道抽点 → 字幕 → WS 音频流**」完整闭环，**无视频推流依赖**。

具体：
- 进入 Home → 自动后置摄像头 + WS → 对准手语 → 同一拍按多器官、轨迹、帧手势计算 → 信封产出 `csl_channels_v1` → WS 上行 → 云端识别 → WS 下行字幕 + PCM 音频 → App 实时播音；无手语时为 **就绪**。
- 离开 Home 或退出应用 → 相机与 WS 拆除，识别/转译/云请求停止。
- 仍停在 Home 时熄屏或进后台 → WS 与播音可续（见 [architecture.md](./architecture.md)）。
- 穿戴设备离线时 App 仍能正常播音（不依赖穿戴）。

## 一期 App 验收指标

没有实测数字的项，通过线写「实现期采数」。

### 感知侧

| 指标 | 口径 | 通过线 |
|------|------|--------|
| 漏帧率 | 手势活动区间内应保留关键动作却未抽中的比例 | 实现期采数 |
| 模糊拒帧率 | 因清晰度/拖影门控拒绝的帧占比（活动区间） | 实现期采数 |
| 抖动可控性 | 轻/重晃手机时误升 Active 率、抖峰误 PeakHold 率、机位提示误触发率；持稳后恢复延迟 ≤ T_shake_hold + 短防抖 | 恢复延迟按该不等式；误触发率实现期采数 |
| 远距/复杂背景可识别率 | 满足距离与背景条件时 Hands 检出并最终可上行比例 | 实现期采数 |
| 单双手状态正确率 | hand_state 与标注一致的帧比例 | 实现期采数 |
| 单手槽位正确率 | hand_state∈{left,right} 时上行槽与标注一致 | 实现期采数 |
| 拇指–手性一致率 | 掌心朝镜头子集中，T_thumb 非弃权时与标注手性一致 | 实现期采数 |
| 交叉错误对调率 | 交叉段内左右点集被错误交换的帧比例 | 实现期采数 |
| 遮挡错槽率 | 遮挡段因互遮导致错槽上行的比例 | 实现期采数；行为上宁可拒发不错槽 |
| 分机位可抽帧率 | N0 与 A1–A8 各自抽帧放行率 | 实现期采数 |
| 分机位抽中后可抽点率 | 抽帧放行后信封成功打包 landmarks 的比例（按机位分桶） | 实现期采数 |

### 播音侧

| 指标 | 口径 | 通过线 |
|------|------|--------|
| 端侧开声缓冲时延 | 自队首句首片入队到开声 ≈ T_prime | ≈ T_prime |
| 欠载率 | 活动播报区间内处于 Underrun 的时长占比 | 实现期采数 |
| 句间无叠音 | 同会话任意时刻至多一路 PCM 出声 | 设计锁定 |
| 串行正确性 | 多 utteranceId 在未丢弃前提下按 FIFO 完整播放 | 设计锁定 |
| 弱网播音可恢复 | 重连 / Flushing 后队列空；新句可再次 Priming | 设计锁定 |

### 综合

| 指标 | 口径 | 通过线 |
|------|------|--------|
| 开声延迟 | 识别出词后到扬声器出声 | P50 与 P95 均 < 1.5s |
| 关键点上行频率 | 约 15–30 Hz；积压丢旧 | 设计锁定 |
| 连接稳定性 | 心跳 15s；死连接 45s；退避重连 ≤ 30s（仅 Home 内） | 设计锁定 |
| Home 生命周期 | 进 Home 自动后置相机+WS；离页/退出全停；Home 熄屏/后台不拆会话 | 设计锁定 |

## 生产边界

写边界，不写商店物料，也不写 CI 脚本。账号服务、发布流水线和运维系统的实现不在本期编码。

### 账号

- `deviceId` 是本机随机 ID，首次生成后持久化，随握手上传。它不是账号，不绑定个人身份。
- 同一账号只保留最新的 App 会话。新会话建立后，旧连接收到 `session_replaced`。
- App 正式路径：`POST /api/v1/auth/register` / `login`，返回 JWT（含 userId/username/phone/sex 等）与 `user` 摘要。
- 除 health/login/register（及 debug demo-token）外，REST 与 WS 均须 `Authorization: Bearer <jwt>`。
- debug 可调 `demo-token`；release 不得调用，也不回退 demo-token。
- token 只进入系统安全存储，不写入日志。过期后重新登录。不增加 refresh、验证码或第三方登录字段。

### 发布门

- release 只走 `ws_binary_audio`，编码为 PCM s16le / 16 kHz / mono。
- release 拒收 `inline_fallback` / `audioBase64`。
- 权限限于相机和音频播放；Home 后台保活所需的系统能力（前台服务 / 背景音频等）仅服务于 Home 会话。
- 不持久化预览、坐标和 PCM。主路径不上行原始视频。
- 默认使用**后置**摄像头。

### 运维

- 日志和崩溃不含画面、PCM、landmarks 坐标。历史只有 `recognition.text`。
- 感知侧同一时刻只处理最新一帧，旧帧丢掉。WS 发送队列继续丢旧 landmarks。
- `ts` 用相机帧时钟，轨迹节拍与它相同。
- 阀门冷启动加载，不热更新。
- 离开 Home 或退出应用：停相机，Flushing，关 WS，REST stop。
- 仍停在 Home 时熄屏或进后台：保持 WS 与会话；尽量保持采帧与播音。来电 / 音频焦点丢失不单独拆会话。

## 不在本期范围

- 业务代码 UI 细节（颜色、字体、布局）。
- 模型训练与词表扩充。
- 账号服务、CI 脚本和商店物料的实现。
- 穿戴设备硬件适配。

## 相关文档

- [architecture.md](./architecture.md) · [websocket.md](./websocket.md) · [index.md](./index.md)
- [系统架构/roadmap.md](../系统架构/roadmap.md) · [系统架构/risks.md](../系统架构/risks.md)
- [../../api/protocol.md](../../api/protocol.md)
