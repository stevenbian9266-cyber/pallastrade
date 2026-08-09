# REQ-20260809-prod-stack-script

## 需求
新增 `deploy/prod.sh` 快捷启停脚本（对称 `deploy/dev.sh`），支持 `up|down|status`，方便快速开关 prod 栈。

## 背景
- prod 栈常驻，但有时需要维护/重启
- 现有 `deploy/dev.sh` 已提供 dev 栈启停
- 增加对称的 prod 脚本，统一管理体验

## 方案
`deploy/prod.sh`：与 dev.sh 同构，操作 `docker-compose.prod.yml` + `.env.prod`
- `up`：启动 prod 栈 + 健康检查（3100/3101）
- `down`：停止 prod 栈（保留数据卷）
- `status`：查看 prod 栈状态

## 验证
- bash -n 语法检查
- `bash deploy/prod.sh status` 正常输出
- 提交推送 dev

## Skill 参考
- pallastrade-deployment/SKILL.md（部署约定）
- 跨层搜索：deploy/ 目录（dev.sh 为模板，无重复实现）
