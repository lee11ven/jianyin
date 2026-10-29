# native/

双端共享 MediaPipe Tasks Vision MethodChannel。

| 项 | 值 |
|----|----|
| Channel | `jianyin/mediapipe_vision` |
| 帧格式 | 连续 **RGBA8888**（`format=rgba`） |
| 方法 | `ensureReady` / `detectPose` / `detectHands` / `dispose` |
| 模型 | `assets/ml/pose_landmarker_lite.task`、`hand_landmarker.task` |
| Android | `MediaPipeVisionPlugin.kt` + `tasks-vision` |
| iOS | `AppDelegate.swift` 内插件 + CocoaPods `MediaPipeTasksVision` |

算法侧不再做左右镜像；旋转在 Dart 转 RGBA 时按 `sensorOrientation` 校正。

**Android 注意**：`tasks-vision` 只带 **ARM** 原生库。`sdk gphone64 x86 64` 等 x86 模拟器会在 `ensureReady` 软失败（不崩进程），仅保留相机预览；请用 **arm64 真机** 或 ARM system image 验证 Pose/Hands。
