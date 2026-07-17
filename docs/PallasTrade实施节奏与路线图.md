# PallasTrade 实施节奏与路线图

> 来源：`spree项目自有品牌化方案.md` V0.5
> 生成日期：2026-07-17
> 原则：**PVT 先行校准 → 1.0 聚焦核心 → 2.0/3.0 分层交付，不交叉推进**

---

## 总体时间线

```text
 ┌────────────┐    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
 │   PVT      │───▶│  1.0 MVP     │───▶│  2.0 扩展    │───▶│  3.0 商业化   │
 │ 2-4 周     │    │ 3-5 个月      │    │ 3-4 个月      │    │ 3-4 个月      │
 │ 校准工作量  │    │ 源码+品牌化   │    │ AI+完整支付   │    │ 交付+升级     │
 └────────────┘    └──────────────┘    └──────────────┘    └──────────────┘
                                   ▲                    ▲
                          Go/No-Go Gate           Go/No-Go Gate
```

---

# 第一阶段：PVT 原型验证测试（2-4 周）⚠️ 最高优先级

> **目标**：用最小工作量跑通核心链路，用真实数据校准后续所有时间估算。
> **输出**：PVT 报告 → Go/No-Go 决策 → 1.0 计划校准

## 任务清单

| 编号 | 任务 | 预计耗时 | 产出物 |
|------|------|---------|--------|
| PT-PVT-001 | 拉取 Spree Commerce 源码，本地 docker-compose 跑通 Rails + PostgreSQL + Redis | 2-3 天 | 可运行的基础环境 |
| PT-PVT-002 | 跑通 Storefront 完整购物链路（首页→商品→购物车→Checkout） | 2-3 天 | 端到端链路验证通过 |
| PT-PVT-003 | 接入 Stripe Sandbox，完成一笔测试支付 | 2-3 天 | 支付 Sandbox 可用 |
| PT-PVT-004 | 将 1 个 namespace（如 `Spree::Core → PallasTrade::Core`）完成重命名，运行全量测试 | 3-5 天 | 品牌化自动化可行性验证 |
| PT-PVT-005 | 汇总 PVT 报告，校准 1.0 计划 | 1-2 天 | PVT 报告 + 修订后的 1.0 计划 |

## PVT 验收标准

```text
[ ] docker-compose 一键启动全部服务，无额外手动配置
[ ] Storefront 完整购物链路无报错
[ ] Stripe Sandbox 支付成功，后台可见订单
[ ] namespace 重命名后全量测试通过率 ≥ 原版通过率
[ ] PVT 报告包含每个步骤的实际耗时和受阻问题
[ ] 1.0 时间估算已基于 PVT 数据修订
```

## Go/No-Go 决策点

| 条件 | 结论 |
|------|------|
| 全部通过，无阻塞问题 | **Go** → 进入 1.0 正式阶段 |
| 品牌化自动化受阻 | **No-Go** → 先解决自动化脚本问题 |
| 支付 Sandbox 不通 | **No-Go** → 先排查网络/账号/API 配置 |
| 核心链路跑不通 | **No-Go** → 排查 Spree 版本兼容性 |

---

# 第二阶段：1.0 MVP（3-5 个月）

> **目标**：源码冻结 + 完整部署 + 全面品牌化。这是 PallasTrade 的第一个可交付版本。
> **范围**：阶段 0 ～ 阶段 4

## 里程碑 M1：源码接管（阶段 0，~1 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-SOURCE-001 | 一次性拉取全部必要源码 | PT-PVT-005 |
| PT-SOURCE-002 | 记录许可证、Commit，建立 SOURCE_MANIFEST | PT-SOURCE-001 |
| PT-REPO-001 | 建立 PallasTrade 自有仓库，移除所有外部同步关系 | PT-SOURCE-001 |

**M1 验收**：
```text
[ ] SOURCE_MANIFEST.yml 含所有源码的来源、Commit SHA、许可证
[ ] THIRD_PARTY_LICENSES.md + NOTICE.md 完整
[ ] legal/source-records/ 目录归档完毕
[ ] git remote 仅指向 PallasTrade 自有仓库
[ ] pallastrade-source-baseline-0.0.0 Tag 已建立
```

---

## 里程碑 M2：原始系统完整部署（阶段 1，~2 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| — | Rails 后端 + Admin 完整部署 | M1 |
| — | Store API + Storefront 完整部署 | M1 |
| — | PostgreSQL + Redis + Sidekiq + 搜索 | M1 |
| — | Store Credit + 线下支付配置 | M1 |
| PT-PAYMENT-001 | 拉取 Stripe 支付源码，通过本地 Path Gem 部署 | M1 |
| PT-PAYMENT-002 | 配置 Store Credit 和线下支付 | M1 |

**M2 验收**：
```text
[ ] docker-compose up 一键启动全部服务
[ ] Admin 后台可正常操作商品、订单、用户
[ ] Storefront 完整购物链路可用
[ ] Stripe Path Gem 在本地加载成功，无外部 Gem 依赖
[ ] Store Credit + 线下支付方式可用
```

---

## 里程碑 M3：支付验证 + Harness 骨架（阶段 2，~3 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-PAYMENT-003 | Stripe Sandbox 全矩阵测试（Authorize/Capture/Void/Refund/Webhook/幂等） | M2 |
| PT-HARNESS-001 | 建立 Minimum Viable Harness | M2 |

**M3 验收**：
```text
[ ] Stripe Authorize → Capture → Refund 全流程通过
[ ] Stripe Webhook 验签 + 幂等验证通过
[ ] 支付安全 checklist 全部打勾（第 9.3 节）
[ ] AGENTS.md + ARCHITECTURE.md 就位
[ ] Change Manifest + Obligations Matrix + Impact Map 骨架就位
[ ] 命名审计：已扫描 `spree` 关键词并记录所有出现位置
```

---

## 里程碑 M4：外部品牌化（阶段 3，~2 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-LOCALIZE-001 | 完成外部品牌化 | M3 |

**覆盖范围**：
```text
产品名称/Logo        Admin 标题/图标
Storefront 品牌      API 响应中的产品名称
Docker 服务名        环境变量前缀
支付配置描述          回调地址域名
邮件模板签名/发件人   文档标题/链接
```

**M4 验收**：
```text
[ ] Admin 登录页/标题/页脚显示 PallasTrade
[ ] Storefront 页眉/页脚/标题显示 PallasTrade
[ ] API 响应中无 Spree 品牌标识
[ ] Docker Compose 服务名不含 spree
[ ] 环境变量前缀为 PALLASTRADE_
[ ] 邮件发件人和模板签名不含 Spree
```

---

## 里程碑 M5：内部深度品牌化（阶段 4，~3-4 周）⚠️ 最复杂阶段

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-LOCALIZE-002 | Namespace、Gem、数据库表品牌化（自动化脚本，禁止手工） | M4 |
| PT-LOCALIZE-003 | 品牌化后全量回归测试 | PT-LOCALIZE-002 |

**品牌化自动化步骤**：
```text
Step 1: 建立 PallasTrade Rename Map
        Spree → PallasTrade / spree_ → pallastrade_ /
        SPREE_ → PALLASTRADE_ / @spree/ → @pallastrade/

Step 2: RuboCop Custom Cops 批量处理 Ruby 文件

Step 3: 脚本批量处理 JS/TS/JSON/YAML/ERB 文件

Step 4: 数据库 migration（表名/索引/外键重命名）

Step 5: db:migrate:reset + db:schema:dump 验证

Step 6: 全量测试 → 修复遗漏 → 重新测试
```

**M5 验收**：
```text
[ ] grep -r "Spree" 返回零结果（排除 legal/ 和 .git/）
[ ] grep -r "spree_" 返回零结果
[ ] db:schema.rb 所有表名以 pallastrade_ 开头
[ ] Rails console 中 Spree 常量不存在，PallasTrade 常量正常
[ ] Gemfile 中无 spree gem 引用（本地 path 除外）
[ ] 全量测试套件通过率 100%
[ ] Storefront + Admin + API 功能正常
```

---

## 🏁 1.0 最终验收

```text
[ ] 所有必要源码已一次性接管并冻结
[ ] SOURCE_MANIFEST 已建立，许可证和 Commit 完整可追溯
[ ] PallasTrade 自有仓库已建立，不存在外部源码同步依赖
[ ] Commerce、Starter、Storefront 可本地 docker-compose 运行
[ ] PostgreSQL、Redis、Sidekiq、搜索均正常工作
[ ] Stripe 使用本地源码并通过 Sandbox 完整支付链路测试
[ ] Store Credit 和线下支付可用
[ ] 支付幂等、验签、退款和金额测试通过（Stripe）
[ ] 产品品牌、Admin、Storefront、邮件、文档完成 PallasTrade 品牌化
[ ] Ruby Namespace、Gem、Engine、数据库表完成 PallasTrade 品牌化
[ ] 环境变量、Docker 服务、Redis Key、事件、Webhook 完成品牌化
[ ] API 端点以 /api/store/v1、/api/admin/v1 正常服务
[ ] Storefront 与后端 API 联调通过
[ ] 全量测试套件通过（含品牌化后的回归测试）
[ ] 品牌化自动化脚本可复用（为 Adyen/PayPal 接入做准备）
```

---

# 第三阶段：2.0 扩展能力（3-4 个月）

> **目标**：完善支付矩阵 + AI Runtime + Extension Framework
> **范围**：阶段 5 ～ 阶段 7
> **前置**：1.0 全部验收通过

## 里程碑 M6：完整支付矩阵（阶段 5 部分，~3 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-PAYMENT-004 | 接入 Adyen 支付模块（复用 Stripe 测试范本） | 1.0 |
| PT-PAYMENT-005 | 接入 PayPal Checkout 支付模块 | PT-PAYMENT-004 |

**M6 验收**：
```text
[ ] Adyen Sandbox：Authorize/Capture/Void/Refund/Webhook/幂等全部通过
[ ] PayPal Sandbox：完整支付链路通过
[ ] 三套支付共用测试范本和接入规范，无重复代码
[ ] 每套支付独立 Sandbox 配置，不共享密钥
```

---

## 里程碑 M7：Extension Framework（阶段 5 剩余，~3 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-EXTENSION-001 | 建立 PallasTrade Extension Framework | 1.0 |

**M7 验收**：
```text
[ ] Provider Registry 可注册/发现扩展
[ ] Events 基础设施可用
[ ] Admin UI Slots 可用
[ ] Webhook Registry 可用
[ ] Payment Gateway Contract 已定义
[ ] Extension Compatibility 验证机制可用
```

---

## 里程碑 M8：Product AI Runtime（阶段 6，~4-6 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-AI-001 | 建立 AI Gateway + DeepSeek Adapter | 1.0 |
| PT-AI-002 | 完成 AI 多语言翻译闭环 | PT-AI-001 |

**PT-AI-002 架构约束**：
```text
⚠️  Storefront 任何时候只读数据库，不直接调用 AI
⚠️  AI 翻译仅在后台 Job（Sidekiq）中异步执行
⚠️  AI 超时/不可用时返回原始语言内容（降级），不阻塞请求
⚠️  翻译结果持久化到数据库表，非 Redis/内存缓存
```

**M8 验收**：
```text
[ ] AI Gateway 独立运行，Provider Adapter 模式可切换
[ ] DeepSeek V4 Pro 通过 Adapter 接入，Gateway 无直接依赖
[ ] 翻译流程：原始内容→术语表→模型翻译→格式校验→质量评价→审核→保存
[ ] 翻译结果持久化到数据库，版本可追溯
[ ] 模型不可用时：核心 Commerce 正常运行
[ ] 模型不可用时：Storefront 显示原始语言内容（降级验证）
[ ] 异步翻译任务不阻塞用户请求
[ ] 配额管理和审计日志可用
```

---

## 里程碑 M9：Harness 试点（阶段 7，~3 周）

| 任务 | 依赖 |
|------|------|
| 基于 Harness 完成一个 API 修改（API + OpenAPI + SDK + Contract Test 同步） | M8 |
| 基于 Harness 完成一个 Gem 修改（Gem Test + 版本决策 + Changelog） | M8 |
| 基于 Harness 完成一个支付修改（幂等 + 验签 + 金额校验 + 退款测试） | M8 |

**M9 验收**：
```text
[ ] API 修改自动触发 OpenAPI + SDK + Contract Test 同步检查
[ ] Gem 修改自动触发版本决策提醒和 Changelog 更新
[ ] 支付修改自动触发 Payment Contract Reviewer + Security Reviewer
[ ] Harness 的 Obligations Matrix 对上述修改产生约束效果
```

---

## 🏁 2.0 最终验收

```text
[ ] Extension Framework 可运行（Provider Registry、Events、Admin Slots）
[ ] Adyen 和 PayPal 支付模块接入并通过 Sandbox 测试
[ ] AI Gateway + DeepSeek Adapter 独立运行
[ ] AI 翻译闭环完成（异步+缓存+降级）
[ ] AI 不影响核心交易可用性（模型不可用时验证通过）
[ ] Harness 试点：API+SDK+Gem 修改流程验证通过
[ ] Minimum Viable Harness 可约束代码同步关系
```

---

# 第四阶段：3.0 商业化交付（3-4 个月）

> **目标**：客户交付体系 + 自有升级 + License 平台
> **范围**：阶段 8 ～ 阶段 9
> **前置**：2.0 全部验收通过

## 里程碑 M10：客户源码交付（阶段 8，~4 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| — | Standard Distribution 打包与文档 | 2.0 |
| — | Certified Fork 指南与工具链 | 2.0 |
| — | Unmanaged Fork 公告与迁移文档 | 2.0 |
| PT-UPGRADE-002 | 建立 AI 辅助升级分析 Agent | 2.0 |

**升级 Agent 安全约束**：
```text
⚠️  支付相关 diff 绝不由 Agent 自动合并
⚠️  Migration 绝不由 Agent 自动执行
⚠️  Agent 生成的 PR 必须通过 CI Gate + 人工 Code Review
⚠️  涉及金额/币种/价格计算的变更标记为最高风险
⚠️  升级分析结果为决策参考材料，非决策依据
```

**M10 验收**：
```text
[ ] Standard Distribution 客户可基于官方镜像部署
[ ] Certified Fork 客户可记录 Change Manifest 和 Git 历史
[ ] Unmanaged Fork 客户可获取新版本说明和安全公告
[ ] AI 升级分析 Agent 可用于三方 diff 分析（A→B vs A→C）
[ ] 升级 Agent 对支付/migration 相关 diff 强制标记为需人工决策
```

---

## 里程碑 M11：自有发布体系（阶段 9 部分，~3 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-UPGRADE-001 | 建立 PallasTrade 自有 Release 体系与升级差异包 | M10 |

**M11 验收**：
```text
[ ] 每个版本输出 Release Manifest
[ ] 每个版本输出 Source Diff / Gem API Diff / OpenAPI Diff / SDK Diff / Schema Diff
[ ] 每个版本输出 Migration + Payment Contract Diff
[ ] 每个版本输出配置变化 + 环境变量变化
[ ] 每个版本输出 Security Advisory + Harness Eval Pack
```

---

## 里程碑 M12：License & Control Plane（阶段 9 剩余，~4 周）

| 编号 | 任务 | 依赖 |
|------|------|------|
| PT-CONTROL-001 | License 文件签名验证机制 | M11 |
| PT-CONTROL-002 | 客户版本下载与基础支持资格管理 | PT-CONTROL-001 |

**渐进策略**：
```text
1.0 阶段（已在 M4 后完成）：
  └── License Key 文件 → 离线验证签名 → 基础权益检查

2.0 阶段（本次实现）：
  └── 客户注册 + License 分发 + 版本下载权限 + 基础审计日志

3.0 阶段（后续）：
  └── 完整 Control Plane（合同/安装追踪/异常检测）
```

**M12 验收**：
```text
[ ] License 文件签名可验证，防止篡改
[ ] License 过期或权益不足时明确提示，不破坏已有数据
[ ] 不做任何形式的远程禁用或数据清除
[ ] 客户可自助下载授权版本
[ ] 基础审计日志记录下载和激活事件
```

---

## 🏁 3.0 最终验收

```text
[ ] 客户源码自主修改模式（Standard/Certified/Unmanaged）明确且可运行
[ ] PallasTrade 自有升级体系可运行（Release Manifest、Diff、Migration）
[ ] AI 升级分析 Agent 可辅助分析客户 Fork（非自动执行）
[ ] License 文件机制可用（签名验证、离线友好）
[ ] 客户版本下载权限和基础支持资格管理可用
```

---

# 总览：里程碑与任务依赖图

```text
PVT ─────────────────────────────────────────────────────────────
 │
 ├─ PT-PVT-001 ─▶ PT-PVT-002 ─▶ PT-PVT-003 ─▶ PT-PVT-004 ─▶ PT-PVT-005
 │                                                               │
 └─────────────────────── Go/No-Go Gate ─────────────────────────┘
                                  │ Go
                                  ▼
1.0 MVP ─────────────────────────────────────────────────────────
 │
 ├─ M1 源码接管 ──▶ M2 系统部署 ──▶ M3 支付+Harness ──▶ M4 外部品牌化 ──▶ M5 深度品牌化
 │    (~1周)         (~2周)         (~3周)              (~2周)           (~3-4周)
 │                                                                        │
 └──────────────────────────────── 1.0 验收 ──────────────────────────────┘
                                                                          │
                                                                          ▼
2.0 ─────────────────────────────────────────────────────────────────────
 │
 ├─ M6 完整支付 ──▶ M7 Extension ──▶ M8 AI Runtime ──▶ M9 Harness试点
 │    (~3周)         (~3周)           (~4-6周)            (~3周)
 │                                                          │
 └────────────────────────── 2.0 验收 ──────────────────────┘
                                                              │
                                                              ▼
3.0 ─────────────────────────────────────────────────────────────────
 │
 ├─ M10 客户交付 ──▶ M11 发布体系 ──▶ M12 License/Control Plane
 │     (~4周)          (~3周)            (~4周)
 │                                          │
 └────────────────── 3.0 验收 ──────────────┘
```

---

# 关键架构决策（ADR，不可在实施中轻易推翻）

| 决策 | 理由 |
|------|------|
| 一次性接管，不建立持续同步 | 避免长期维护外部依赖的工程成本 |
| 品牌化通过自动化脚本完成 | 100+ 表/上万处引用，手工不可行 |
| AI 内容仅通过后台 Job 异步生成 | 防止 AI 延迟/不可用阻塞交易链路 |
| 支付分批接入（Stripe→Adyen→PayPal） | 降低并行调试复杂度 |
| 1.0 License 使用文件签名，非完整 Control Plane | 1.0 阶段无需完整 SaaS 运营后台 |
| AI Upgrade Agent 定位为辅助分析工具 | 支付/migration/状态机冲突无法安全自动合并 |
| PVT 先行，校准后再进入正式阶段 | 用实际工作量替代估算 |

---

# 主要风险与缓解

| 风险 | 等级 | 缓解措施 | 关注阶段 |
|------|------|---------|---------|
| 数据库品牌化遗漏硬编码引用 | 🔴 高 | 自动化脚本 + 全量测试 + schema.rb 验证 | M5 |
| 支付 Webhook 本地调试环境复杂 | 🟡 中 | Stripe CLI；Adyen/PayPal 用 ngrok | M3/M6 |
| AI 翻译被用在同步请求路径 | 🔴 高 | 架构评审 + Code Review gate + 不变量测试 | M8 |
| 三套支付 API/SDK 版本兼容 | 🟡 中 | 每套独立 Sandbox，不共享配置 | M6 |
| Control Plane 自建拖慢 1.0 | 🟡 中 | 1.0 仅 License 文件签名 | M12 |
| 范围膨胀（5 个平台同步推进） | 🔴 高 | 1.0/2.0/3.0 边界刚性，不交叉 | 全程 |

---

## ⏭️ 下一步

**立即执行 PT-PVT-001 至 PT-PVT-005**，用真实跑通的数据校准本文档中的所有时间估算和优先级排序。
