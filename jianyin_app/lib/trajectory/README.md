# trajectory/

活动段轨迹支路：固定节拍腕 / 掌心 / 五指尖；断点写 `gap`。

- `path_types.dart` — `PathTickResult` / `PathTraceKind`
- `trajectory_tracker.dart` — 跟踪接口（P1-0 stub）

算法：[docs/design/算法/客户端/运动轨迹.md](../../../docs/design/算法/客户端/运动轨迹.md)

部位命中：当段 `trace` 为指尖时，默认用该指尖求部位 / 接触（见多器官文档）。
