# services/inference —— 云端识别（规划目录）

本目录为**规划中的独立服务目录**（对应 `docs/design/系统架构/modules.md` 的仓库映射表）。

- **当前承载位置**：`websocket-server/src/pipeline/`（`features.js` 特征积分、`lexicon.js` 规则词表打分、`recognition.js` 滑动窗口与节流）。
- **契约来源**：`docs/design/算法/云端/滑动窗口识别.md`（多通道消费契约、降级矩阵、一期最小可用实现与验收点）。
- **可替换点**：`lexicon.js` 的 `rankCandidates(features)` 视为接口；替换为模型推理时，缓冲、对齐、段切分、特征契约与输出字段保持不变。
- **迁移触发条件**：需要独立扩缩容、独立部署或独立评测（WER）时，把该管线整体迁入本目录并保持对外契约不变。