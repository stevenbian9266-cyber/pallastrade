# Harness 升级机制决策 (2026-08-07)

## 已删除（审计/检查层）
- harness `upgrade:*` 套件（upgrade-audit/rollback/verify/evidence.mjs、harness/versions/、harness/baselines/、harness-upgrade.yml、config.json upgrade profile、scenarios GS-010、artifacts/upgrade-evidence/）
- `ai/commands/audit-upgrade.md` 及全部引用（README/AGENTS/plugin json/plugin-structure-check.mjs→只留 doctor.md/3 个 skill）
- 需求文档：`harness/requirements/REQ-20260807-remove-upgrade-audit.md`

## 保留（执行层，用户决定"先留着"）
- `pallastrade:upgrade` rake task（pallastrade_core/lib/tasks/upgrade.rake）——自有框架升级执行引擎，非上游 Spree
- `pallastrade upgrade` CLI（platform/packages/cli/src/commands/upgrade.ts）
- 注意：`lib/pallastrade/upgrades/` manifest 目录当前不存在 → 跑 rake task 是安全 no-op（Runner 对空 manifest 直接 return）
- 生产部署 release-phase 依赖它（Heroku/Render/K8s 均调用），删了会破坏部署

## 关键事实
- 私有化彻底：backend/storefront/platform/harness/ai 全仓零 Spree 残留，Gemfile 全 pallastrade_* 本地 gem
- Spree 官方 docs MCP 已从 VS Code 用户级 MCP 设置移除（用户级配置，非仓库文件）
