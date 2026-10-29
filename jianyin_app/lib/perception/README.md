# perception/

同拍调度：多器官 → 轨迹 → 帧手势 → 信封打包。

`PerceptionPipeline`：同拍 `body → path → hands → pack`。
`PerceptionRuntime`：注入 MediaPipe Pose/Hands 实现；Home 经 `FrameSampler` 驱动。
