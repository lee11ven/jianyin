# camera/

后置预览 + Idle/Active 抽帧状态机（运动能量 `E`、清晰度 `S`）。

- `frame_sampler.dart`：`Idle`↔`Active`，节流后回调 `onTick`
- Home：`CameraPreviewPanel` → `startImageStream` → `PerceptionRuntime.tick`
- MVP：`viewpoint_class = N0`；`forcePathGap` 恒 false；模糊帧 `omitHands`

算法：[docs/design/算法/客户端/视频流抽帧.md](../../../docs/design/算法/客户端/视频流抽帧.md)
落地切片：[docs/design/算法/客户端/plans/视频流抽帧.md](../../../docs/design/算法/客户端/plans/视频流抽帧.md)
