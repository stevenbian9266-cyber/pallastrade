# PallasTrade

PallasTrade 是由 Steven Bian 维护的自有电商平台，正式域名为
[pallastrade.cn](https://pallastrade.cn)。本仓库是 Backend、Platform、Storefront
和 AI 能力的唯一正式源码仓库。

## 目录

```text
backend/      Rails 后端与部署模板
platform/     管理平台、SDK、CLI、文档与开发工具
storefront/   Next.js 商店前端
ai/           PallasTrade AI 开发能力
harness/      项目规范、场景、需求和治理策略
```

各目录共享根 Git Commit 和统一发布 Tag。日常开发与发布均在 `dev`（远程仅 dev，无
main/prod）；组件目录不得包含独立 Git 元数据。

## AI 开发生命周期

仓库使用 `pallastrade-harness@1.0.3` 约束 AI 开发：持久 Task、Project Brain、风险分级、
task-bound Gate、实际 Diff/领域监督、typed evidence、恢复计划与知识回写。新修改任务从
`npx harness task start` 开始，只有当前代码状态对应的证据通过 `evidence verify` 后才可完成。
详细规则以 [AGENTS.md](AGENTS.md) 和 [Harness 升级方案](harness升级方案.md) 为准。

## 获取源码

```bash
git clone --branch main --single-branch https://github.com/stevenbian9266-cyber/pallastrade.git
cd pallastrade
```

按组件进入固定目录开展开发。根目录 CI 会依据变更路径运行对应组件任务。

## 发布

统一 Tag 示例：`pallastrade-v1.0.0-rc.1`、`pallastrade-v1.0.0`、
`pallastrade-v1.0.1`。Tag 同时绑定四个组件；Gem/npm 包可保留独立版本，但发布时
必须由同一个 release manifest 绑定到根 Commit。

完整规则和操作方式见 [单仓库与发布模型](scripts/release/README.md)。

## 维护

本项目由 Steven Bian 独立维护，不接受外部代码贡献。问题、支持、安全、销售和
其他联系统一使用 `stevenbian9266@gmail.com` 或仓库 Issue。
