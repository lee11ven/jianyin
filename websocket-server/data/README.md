# 运行期数据目录

本目录存放网关的**运行期数据**（`users.json`、`membership.json`、`history.json`），
按 `.gitignore` 规则**不纳入版本库**，只保留在部署机上；首次运行会按需创建。

- 静态配置（词表 `src/data/gestures.json`、套餐 `data/plans.json`）在版本库内。
- 备份与迁移请直接复制本目录；**不要把含手机号 / 密码哈希的文件提交到仓库**。
- 如需清空账号与历史：停止服务后删除对应 JSON，再启动即可。