# 设备级验收（真机 / iOS）交接清单

> 本文件是 **风险与开放问题** 维度的验收证据来源：给出「在 Android 真机与 macOS 上如何完成验收」的可执行步骤，并如实标注**本机无法完成**的项。凡本机（Windows，无真机与音频回路、无 macOS）无法执行的项，一律标为「待实测 / 未验证」，**不得当作已通过**。

## 1. 环境与前提

| 项 | 说明 |
|----|------|
| 网关 | `cd websocket-server && npm install && npm start`（默认 `0.0.0.0:8000`；运行期 `data/*.json` 仅存磁盘） |
| 客户端接口 | `lib/config/api_config.dart` 默认 `http://192.168.1.100:8000`；联调时用 `--dart-define=API_BASE_URL=http://<局域网IP>:8000` 覆盖 |
| Android 设备 | 真机（API ≥ 26），需 `adb` |
| iOS 设备 | 需 macOS + Xcode（本机为 Windows，**无法构建 iOS**） |
| 本机（Windows） | **无真机与音频回路、无 macOS**：下列 Android 联播与 iOS 编译/行为项在本机**无法执行** |

## 2. Android 真机联播步骤（可交接）

前置：手机与网关同局域网；`adb devices` 能看到设备。

1. 构建并安装：

   ```bash
   cd jianyin_app
   flutter build apk --debug
   adb install -r build/app/outputs/flutter-apk/app-debug.apk
   ```

2. 覆盖网关地址并启动：

   ```bash
   flutter run --dart-define=API_BASE_URL=http://<局域网IP>:8000
   ```

3. 进 Home → 授权相机 → 对准手语动作（演示词表 8 词）。

4. 观测与记录（逐条勾选）：

   - [ ] **对准手语 → 听到语音**：出现字幕且扬声器出声；记录「识别出词 → 出声」开声延迟（口径 < 1.5 s，P50 / P95）。
   - [ ] **熄屏 30 s 会话不拆**：Home 未离开时按电源键熄屏 ≥ 30 s，会话仍 `active`、心跳未断；`adb logcat` 无 REST stop。
   - [ ] **熄屏音频续播**：熄屏期间已下行音频继续播放。
   - [ ] **熄屏连续抽点（Android）**：前台服务就绪后，熄屏 ≥ 30 s 内 `landmarks` 上行未中断。
   - [ ] **离开 Home 全停**：进设置 / 个人中心后 1 s 内相机释放、WS 断开、无新 `landmarks`；前台服务与通知停止。
   - [ ] **退出全停**：杀进程后无僵尸上行；云端会话可被 REST stop 清理。

5. 采集命令（示例）：

   ```bash
   adb logcat -s flutter | grep -E "landmarks|audio.header|session"
   adb shell dumpsys activity services | grep -i jianyin   # 前台服务是否存活
   ```

## 3. iOS 构建与后台行为（需 macOS）

1. 在 macOS 上安装 Xcode / CocoaPods 后：

   ```bash
   cd jianyin_app
   flutter pub get
   flutter build ios --debug --no-codesign
   ```

2. 校验：`ios/Runner/AppDelegate.swift` 的 `PcmPlayerPlugin`（`AVAudioEngine`）+ `AVAudioSessionCategoryPlayback` 编译通过；`ios/Runner/Info.plist` 含 `UIBackgroundModes=[audio]`。
3. 行为口径：iOS **后台不允许继续使用相机**，验收口径为「熄屏 / 后台不拆会话、已下行音频可续播、回前台 ≤ 2 s 恢复抽点」。
4. 结论落点：把编译结果与真机行为回填到 [metrics.md](./metrics.md) 第 3 节与 [../design/客户端APP/architecture.md](../design/客户端APP/architecture.md) 的验收表。

## 4. 本机无法完成的项（如实标注，**未验证**）

| 项 | 状态 | 原因 |
|----|------|------|
| Android 真机联播与熄屏保活 | **未验证 / 待真机** | 本机无 Android 真机与音频回路 |
| iOS 编译 | **未验证 / 需 macOS** | 本机为 Windows，无法构建 iOS |
| iOS 后台音频行为 | **未验证 / 待实测** | 依赖 macOS + 真机 |
| 真机漏帧率 / 端侧缓冲时延 / 欠载率 | **口径已定，待真机取数** | 见 [metrics.md](./metrics.md) 第 3 节 |

> 说明：以上四项**不被声称为已通过**。实现与构建校验（APK 生成、合并清单、端到端自动化）已在 [metrics.md](./metrics.md) 与自动评级中单独记录。本机可复核的等价项：`flutter build apk --debug` 成功、合并后 `AndroidManifest.xml` 含前台服务与权限、网关端到端闭环通过。

## 5. 相关

- 验收口径：[../design/客户端APP/architecture.md](../design/客户端APP/architecture.md)
- 指标实测：[metrics.md](./metrics.md) · 容量：[scalability.md](./scalability.md)
- 自动评级：[grading.md](./grading.md)