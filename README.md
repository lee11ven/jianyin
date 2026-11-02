# 见音 · AI 手语转语音

面向听障 / 哑语场景：**端侧提取手语关键点 → 云端识别为文本 → 流式 TTS → 手机 App / 语音穿戴实时播放**。

主路径**不上行原始视频**：端侧抽点与骨架在设备内完成，云端只收关键点序列（`csl_channels_v1`）与下发字幕 + PCM 音频流。

## 仓库结构

| 目录 | 说明 |
|------|------|
| `jianyin_app/` | Flutter 客户端（规划名 `apps/mobile/`）：MediaPipe 端侧抽点、WS 上行、流式播音 |
| `websocket-server/` | Node 网关（规划名 `services/api/`）：Express REST + `ws` 网关 + 识别 / TTS 管线 |
| `docs/api/` | 冻结协议（`protocolVersion: 1`，唯一字段事实来源） |
| `docs/design/` | 设计文档体系：系统架构、客户端 APP、客户端算法、云端算法 |
| `.github/workflows/ci.yml` | CI：客户端 analyze + test；网关 test + 启动冒烟 |

规划目录与实际位置的映射见 `docs/design/系统架构/modules.md`。

## 快速开始

### 网关

```bash
cd websocket-server
npm install
npm test          # node:test 单测
npm start         # 默认监听 0.0.0.0:8000
curl http://127.0.0.1:8000/health
```

环境变量见 `.env.example`：`HOST` / `PORT` / `NODE_ENV` / `JWT_SECRET`（**production 必须改为强随机值，否则启动即失败**）/ `TTS_BACKEND`。

### 客户端

```bash
cd jianyin_app
flutter pub get
flutter analyze   # 要求零 issue
flutter test      # 单元测试
flutter run       # 设备 / 模拟器
```

客户端的接口地址在 `lib/config/api_config.dart`，**必须与网关地址一致**后才能联调。

## 实现现状（与设计文档对照）

| 部分 | 状态 |
|------|------|
| 端侧感知（抽帧四态机、多器官、轨迹、手形、信封投影、机位 A1–A8 与 4 阀） | 已落地 |
| 上行 `landmarks`（`csl_channels_v1`）、`/ws/app` 握手 / 心跳 / 退避重连 / 会话互斥 | 已落地 |
| 云端识别（多通道特征 + 规则词表）、流式 TTS（PCM 分片 + `audio.header` 时序 + 按句串行 + 背压） | 已落地（**演示级后端**，接口可替换为模型 / 真实合成器） |
| 客户端流式播音（Recv → Assembler → JitterBuffer → Player + 抖动缓冲 / 欠载 / 串行） | 已落地（原生桥：Android `AudioTrack` / iOS `AVAudioEngine`） |
| 端侧保活（Android 前台服务 + iOS 背景音频） | 已落地（iOS 后台不可用相机，口径见设计文档） |
| 穿戴 / 边缘硬件、生产模型与 WER 评测 | 未开始（二期） |

## 安全与数据

- 运行期数据（`websocket-server/data/*.json`：账号、会员、历史）**不纳入版本库**，仅存磁盘；首次运行会按需创建。
- `GET /api/v1/devices` 只返回当前账号的设备。
- token 只存客户端安全存储；服务端不落日志。主路径不上行原始视频。

## 设计文档索引

- 系统架构：[`docs/design/系统架构/index.md`](docs/design/系统架构/index.md)
- 冻结协议：[`docs/api/protocol.md`](docs/api/protocol.md)
- 客户端算法：[`docs/design/算法/客户端/index.md`](docs/design/算法/客户端/index.md)
- 云端识别：[`docs/design/算法/云端/滑动窗口识别.md`](docs/design/算法/云端/滑动窗口识别.md)