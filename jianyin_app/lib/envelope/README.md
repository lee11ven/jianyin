# envelope/

管线终态：汇合 body / trajectory / skeleton，填本地 frame，再投影为 `csl_channels_v1`。

- `catalog.dart` — 关节 / 骨节 / 轨迹点 / 身体点 / 部位身份（含 46 条骨节拓扑）
- `envelope_types.dart` — `catalog` / `frame` / `segment` 本地模型
- `envelope_assembler.dart` — **组装**完整 frame（joints / bones / present / valid / relation）
- `envelope_packer.dart` — **唯一**上行打包入口（不含骨节 / relation / present / valid / segment）
- `csl_channels.dart` — 上行通道数据结构
- `landmark_point.dart` — `{x,y,z,v}` 共用采样

分工锁定：`Assembler` 填 frame → `Packer` 上行。

算法：[docs/design/算法/客户端/手势骨架信封.md](../../../docs/design/算法/客户端/手势骨架信封.md)
