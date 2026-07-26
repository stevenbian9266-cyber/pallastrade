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
```

四个目录共享根 Git Commit 和统一发布 Tag。仓库只维护长期分支 `main`，组件目录
不得包含独立 Git 元数据。

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
