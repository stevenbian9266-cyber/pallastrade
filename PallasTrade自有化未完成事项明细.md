# PallasTrade 自有化未完成事项明细

更新时间：2026-07-24
维护人：Steven Bian

## 本轮已完成

- [x] 删除独立许可、告知、版权归属、作者与外部签署记录类文件。
- [x] 删除外部贡献者签署数据和外部行为准则文件。
- [x] 删除平台目录中的外部通用技能包及其工具引用。
- [x] 删除代码、文档和样式中的外部来源、改编及风格归属措辞。
- [x] 将 npm、Gem 及项目发布主体统一为 PallasTrade / Steven Bian。
- [x] 建立 PallasTrade 项目归属说明和强制归属审查。
- [x] CI 在组件或归属审查规则变化时执行强制检查。
- [x] 文件名、正文、临时文件、嵌套 Git 元数据及派生措辞物理扫描均为零残留。
- [x] API 文档仅维护 V3，并通过 V3 文档策略检查。
- [x] 单仓库目录、`main` 分支、统一 Tag 与 release manifest 工具已实施。
- [x] MONO-01：已创建单仓库模型首个正式根提交 `e9d248d`，四个组件已绑定到同一根 Commit。
- [x] MONO-02：已推送 `main`，GitHub canonical 仓库默认分支为 `main`。

## 仍未完成

- [ ] RELEASE-01：在全部发布门禁通过后创建首个不可移动的正式 PallasTrade Tag。
- [ ] RELEASE-02：为正式 Tag 生成包含根 Commit、目录校验值、包版本和测试证据的 release manifest。
- [ ] TEST-01：修复 Platform `create-pallastrade-app` 的 Biome 格式检查问题，再执行全量 lint、typecheck、test 和 build。
- [ ] TEST-02：调整 Backend Compose CI 环境契约，使检查阶段使用安全的测试环境文件而不依赖未提交的 `backend/.env`。
- [ ] TEST-03：同步 Storefront 的 `package.json` 与 `package-lock.json`，补齐 `@pallastrade/sdk-core@0.1.0` 锁定记录后重跑 `npm ci`。

以上未完成项均不影响本轮 PallasTrade 项目身份零残留审查结论；正式 Tag、release manifest 和全量测试将在对应发布步骤中执行。