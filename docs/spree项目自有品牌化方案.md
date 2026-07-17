已调整为：**源码一次性接管，部署完成后只保留 PallasTrade 自有仓库和版本体系，不建立任何 Spree 持续同步、补丁移植或远程更新关系。**

# PallasTrade 产品、源码本地化与 AI 工程总体需求框架

版本：V0.5
状态：总体需求基线（已校准 MVP 边界与架构约束）

## 1. 项目定位

PallasTrade 是一套以一次性取得的 Spree Commerce 开源源码为初始技术基础，经过完整本地部署、品牌自有化、支付能力接管和持续自研后形成的独立 Commerce 平台。

完成初始源码接管后，PallasTrade 将进入完全独立演进阶段：

* 不保留外部源码同步关系；
* 不自动获取 Spree 后续版本；
* 不合并 Spree 后续提交；
* 不依赖 Spree 的版本路线；
* 不以兼容 Spree 后续版本为目标；
* 不以 Spree Gem 或 Docker 镜像作为后续运行依赖；
* 所有缺陷修复、功能开发、架构升级和安全维护均由 PallasTrade 自行完成。

Spree 只作为 PallasTrade 初始源码的历史来源。相关来源、许可证和版权记录仅用于法律合规与内部审计，不参与后续工程运行。

---

# 2. 总体建设目标

PallasTrade 需要完成以下五条主线：

```text
源码一次性接管
    +
PallasTrade 全面品牌化
    +
支付能力完整本地部署
    +
Product AI Runtime
    +
Harness AI 工程化
```

最终形成五个主要平台：

```text
1. PallasTrade Commerce Runtime
2. PallasTrade Product AI Runtime
3. PallasTrade Engineering Harness
4. PallasTrade Release & Upgrade Platform
5. PallasTrade License & Customer Control Plane
```

---

# 3. 一次性源码接管范围

## 3.1 Commerce 主体源码

初始阶段一次性拉取：

```text
1. Spree Commerce 主项目源码
2. Rails Starter 应用源码
3. Next.js Storefront 源码
4. Agent Skills 与 AI 开发规范源码
```

对应接管内容包括：

| 源码范围         | 主要内容                                       |
| ------------ | ------------------------------------------ |
| Commerce 主项目 | Core、API、Admin、Emails、Dashboard、SDK、CLI、文档 |
| Starter      | Rails 主应用、Docker、数据库、Redis、Sidekiq、搜索与部署配置 |
| Storefront   | Next.js 商城前端                               |
| Agent Skills | Skills、Agents、Commands、Hooks、评估与开发指令       |

## 3.2 支付源码

初始阶段一并拉取和部署：

```text
5. Stripe 支付扩展源码
6. Adyen 支付扩展源码
7. PayPal Checkout 支付扩展源码
```

此外接管 Commerce Core 已提供的基础支付能力：

```text
Store Credit
Check
Cash on Delivery
Bank Transfer
其他线下支付方式
```

## 3.3 初始来源档案

每份初始源码都必须记录：

```text
来源项目名称
来源仓库地址
取得日期
Tag
Commit SHA
许可证
版权声明
对应的 PallasTrade 模块
是否包含后续自主修改
```

建议存放：

```text
legal/source-records/
docs/source-snapshot/
SOURCE_MANIFEST.yml
THIRD_PARTY_LICENSES.md
NOTICE.md
```

这些档案只用于：

* 许可证合规；
* 版权归属；
* 初始代码来源审计；
* 法律举证；
* 内部历史记录。

不用于后续代码同步。

---

# 4. 源码接管后的 Git 管理

完成一次性拉取后，应将代码导入 PallasTrade 自有代码仓库。

最终 Git 结构：

```text
origin
= PallasTrade 官方自有代码仓库
```

不保留其他可用于持续同步的远程仓库。

每个项目执行：

```bash
git remote remove origin
git remote add origin git@company.example:pallastrade/<repository>.git
git push -u origin main
```

或者在完成统一仓库整合后，只保留一个 PallasTrade monorepo。

建立不可变基线：

```text
pallastrade-source-baseline-0.0.0
```

该 Tag 表示：

* 初始源码已经完整取得；
* 初始许可证已经登记；
* 原始系统已经部署成功；
* 后续所有变化均属于 PallasTrade 自主迭代。

后续所有提交、分支、Tag 和 Release 均只存在于 PallasTrade 自有仓库。

---

# 5. 推荐仓库结构

```text
pallastrade/
├── apps/
│   ├── backend/
│   ├── admin/
│   └── storefront/
│
├── engines/
│   ├── pallastrade_core/
│   ├── pallastrade_api/
│   ├── pallastrade_admin/
│   ├── pallastrade_emails/
│   ├── pallastrade_stripe/
│   ├── pallastrade_adyen/
│   ├── pallastrade_paypal/
│   ├── pallastrade_ai_core/
│   ├── pallastrade_ai_admin/
│   └── pallastrade_ai_deepseek/
│
├── packages/
│   ├── store-sdk/
│   ├── admin-sdk/
│   ├── sdk-core/
│   ├── cli/
│   └── ui/
│
├── openapi/
│   ├── store/v1/
│   └── admin/v1/
│
├── harness/
│   ├── official/
│   ├── project/
│   ├── skills/
│   ├── agents/
│   ├── commands/
│   ├── hooks/
│   ├── evaluators/
│   └── evals/
│
├── governance/
├── docs/
├── legal/
└── releases/
```

---

# 6. PallasTrade 品牌化要求

除许可证、版权、来源审计文件和不可变 Git 历史外，正式项目中的 Spree 命名全部迁移。

```text
Spree                 → PallasTrade
Spree::               → PallasTrade::
spree_                → pallastrade_
SPREE_                → PALLASTRADE_
@spree/               → @pallastrade/
spree.*               → pallastrade.*
```

迁移范围包括：

* Ruby Namespace；
* Gem 名称；
* Rails Engine；
* npm 包；
* SDK；
* CLI；
  -数据库表；
  -索引和外键；
  -环境变量；
  -Docker 服务；
  -Queue；
  -Job；
  -Redis Key；
  -Cookie；
  -Event；
  -Webhook；
  -Admin；
  -Storefront；
  -邮件；
  -日志；
  -监控；
  -AI Skills；
  -Agent 名称；
  -开发文档。

最终运行时代码中不得出现 Spree 产品标识。

### 6.1 品牌化自动化策略

数据库层面（Spree Core 包含 100+ 张 `spree_*` 前缀表），重命名涉及：

- 所有 ActiveRecord model 的 `table_name` 声明
- 所有 migration 文件中的表名、索引名、外键约束名
- 所有 raw SQL 片段
- 第三方依赖中潜在的硬编码表名引用
- `db/schema.rb` 的完整重建

**禁止手工逐文件修改**。正确的做法：

```text
1. 建立 PallasTrade Rename Map（自动化配置）

{
  "namespace": { "Spree": "PallasTrade", "Spree::": "PallasTrade::" },
  "table_prefix": { "spree_": "pallastrade_" },
  "gem_prefix": { "spree_": "pallastrade_" },
  "env_prefix": { "SPREE_": "PALLASTRADE_" },
  "npm_scope": { "@spree/": "@pallastrade/" }
}

2. 编写 RuboCop Custom Cops 或脚本，基于 Rename Map 批量处理

3. 运行全量测试确认零回归

4. db:migrate:reset + db:schema:dump 验证 schema.rb 干净
```

此过程应作为独立任务分配 1-2 周专注时间，不与其他开发并行。

---

# 7. API 与 SDK

## 7.1 API

PallasTrade 直接接管并重构原有 API 实现。

建议入口：

```text
/api/store/v1
/api/admin/v1
```

PallasTrade 从 `v1` 开始独立维护 API 生命周期。

任何 API 变化必须同步更新：

```text
Controller
Serializer
参数校验
认证与权限
OpenAPI
SDK
Request Spec
Contract Test
API 示例
Changelog
```

## 7.2 SDK

形成 PallasTrade 自有 SDK：

```text
@pallastrade/store-sdk
@pallastrade/admin-sdk
```

SDK 负责：

* 封装 API；
  -认证；
  -TypeScript 类型；
  -错误处理；
  -购物车与 Checkout 调用；
  -订单调用；
  -Admin 管理调用；
  -支付 Session 调用。

业务规则仍然由 Rails 后端负责，不进入 SDK。

---

# 8. Gem 与 Rails Engine

核心后端模块迁移为：

```text
pallastrade_core
pallastrade_api
pallastrade_admin
pallastrade_emails
```

支付模块迁移为：

```text
pallastrade_stripe
pallastrade_adyen
pallastrade_paypal
```

开发阶段统一通过本地 Path Gem 加载：

```ruby
gem "pallastrade_core",
    path: "../engines/pallastrade_core"

gem "pallastrade_stripe",
    path: "../engines/pallastrade_stripe"
```

不得依赖外部发布的 Spree Gem。

PallasTrade 可以在后续建设自己的私有 Gem Registry，但不是初始阶段的必要条件。

---

# 9. 支付能力

## 9.1 Core 支付能力

由 `pallastrade_core` 提供：

```text
Payment
Payment Method
Payment Session
Payment Source
Payment State
Capture
Void
Refund
Store Credit
Offline Payment
支付幂等
支付状态机
支付审计
```

## 9.2 在线支付模块

独立模块：

```text
pallastrade_stripe
pallastrade_adyen
pallastrade_paypal
```

每套支付模块必须包括：

* Gateway；
  -支付配置；
  -Payment Session；
  -前端支付组件；
  -Webhook；
  -验签；
  -幂等；
  -Authorize；
  -Capture；
  -Void；
  -Partial Refund；
  -Full Refund；
  -错误映射；
  -审计；
  -Sandbox 测试。

## 9.3 支付安全要求

```text
[ ] 不保存原始银行卡号
[ ] Secret 不进入 Git
[ ] Webhook 必须验签
[ ] Webhook 必须幂等
[ ] 金额和币种由后端校验
[ ] Capture 和 Refund 必须鉴权
[ ] 支付状态转换必须审计
[ ] 支付失败不得错误完成订单
[ ] 日志不得输出敏感支付凭证
[ ] 重试不得造成重复扣款或退款
```

支付功能后续由 PallasTrade 自主维护，包括：

-支付平台 API 变化；
-SDK 版本变化；
-Webhook 协议变化；
-安全缺陷；
-支付方式新增；
-支付合规升级。

## 9.4 支付接入分批策略

三套在线支付（Stripe、Adyen、PayPal）不建议同时接入，原因：

- 每套支付需要独立的 Sandbox 账号、测试卡和 Webhook 本地接收环境
- 各平台 SDK 版本、网关行为、幂等和重试策略互不相同
- 同时调试多套支付会放大排查难度

**推荐分批顺序**：

```text
Phase 1：Stripe（最流行、文档最好、开发者体验最佳）
  ├── 跑通 Stripe Sandbox 完整支付链路
  ├── 验证 Webhook、验签、幂等、Capture/Void/Refund
  ├── 沉淀支付模块模板和测试范本
  └── 形成「PallasTrade 支付接入规范」

Phase 2：Adyen（基于 Stripe 经验并行接入）
  └── 复用 Phase 1 的测试范本和接入规范

Phase 3：PayPal Checkout（最后接入）
  └── 复用成熟流程
```

每套支付通过 Sandbox 全矩阵测试后再进入下一套，避免三套同时处于"半通不通"状态。

---

# 10. Core 与 Extension Framework

## 10.1 Core

进入 Core 的内容包括：

* 商品、订单、购物车、库存和支付基础语义；
  -核心缺陷修复；
  -平台统一幂等；
  -统一审计；
  -公开 ID；
  -事件基础设施；
  -权限基础设施；
  -所有部署均需要的能力。

## 10.2 Extension

独立模块适用于：

-具体支付网关；
-第三方服务；
-可选 Commerce 功能；
-地区能力；
-实验性能力；
-客户特定集成。

PallasTrade 保留并重新设计：

```text
Events
Provider Registry
Rails Engine
Admin UI Slots
API Resource Registry
Webhook Registry
Extension Contract
```

第一方新代码禁止：

```text
无约束 class_eval
任意 monkey patch
大量 Decorator
无边界 prepend
任意覆盖核心状态机
```

---

# 11. Product AI Runtime

PallasTrade 品牌化后，在系统中建设独立大模型底座。

当前默认模型接入：

```text
DeepSeek V4 Pro
```

业务代码不得直接调用模型供应商 Client。

正确结构：

```text
PallasTrade AI Feature
       ↓
PallasTrade AI Gateway
       ↓
Provider Adapter
       ↓
DeepSeek V4 Pro
```

建议模块：

```text
pallastrade_ai_core
pallastrade_ai_admin
pallastrade_ai_deepseek
```

## 11.1 首批 AI 功能

```text
多语言 AI 翻译
商品名称和描述翻译
分类内容翻译
SEO 内容翻译
邮件模板翻译
内容生成
内容摘要
后台 AI 操作辅助
```

## 11.2 AI 翻译流程

```text
原始内容
→ 术语表和品牌规则
→ 模型翻译
→ 格式和变量校验
→ 质量评价
→ 人工审核或自动发布
→ 保存翻译版本
```

必须记录：

```text
源语言
目标语言
源文本版本
翻译文本
模型
Prompt 版本
术语表版本
质量结果
审核状态
人工修改记录
```

## 11.3 AI 可用性边界

AI 服务不可成为以下流程的强依赖：

```text
订单
支付
退款
库存
Checkout
管理员登录
```

模型不可用时，核心 Commerce 必须继续运行。

### 11.3.1 AI 内容呈现的架构约束（关键决策）

由于 AI 翻译被列为"首批 AI 功能"，且商品名称、描述、分类、SEO 等内容会出现在购物车、Checkout 和订单等核心交易路径上，**AI 内容生成必须遵循异步+缓存+降级模式**：

```text
┌─ 管理后台编辑内容 ──────────────────────────────┐
│                                                   │
│  原始内容保存                                      │
│      ↓                                            │
│  [异步] 触发 AI 翻译/生成                          │
│      ↓                                            │
│  AI 结果写入 palliative_translations /              │
│  palliative_ai_content 表（持久化缓存）              │
│      ↓                                            │
│  管理员审核或自动发布                                │
│                                                   │
└───────────────────────────────────────────────────┘

┌─ Storefront / API 读取 ──────────────────────────┐
│                                                   │
│  查询翻译缓存表                                     │
│      ├── 缓存命中 → 直接返回                        │
│      ├── 缓存未命中 → 返回原始内容（降级）            │
│      └── 异步触发翻译任务（不阻塞当前请求）            │
│                                                   │
│  ❌ 禁止：API 请求中同步等待 AI 模型返回              │
│  ❌ 禁止：AI 超时导致页面白屏或 500                  │
│  ❌ 禁止：AI 不可用导致商品无法展示                   │
│                                                   │
└───────────────────────────────────────────────────┘
```

**翻译存储策略**：

```text
- AI 翻译结果持久化到数据库表，非 Redis/内存缓存
- 数据库被视为此类内容的权威来源（非 AI 模型）
- 数据库迁移/备份时翻译内容与原始内容一起迁移
- 翻译版本号与源内容版本关联，源内容变更时标记翻译过期
```

**关键不变量**：

```text
[ ] Storefront 任何时候只读数据库，不直接调用 AI
[ ] AI 服务超时/不可用/返回错误均不中断用户请求
[ ] 商品、分类页面的渲染路径不包含 AI API 调用
[ ] 降级时显示原始语言内容，非空白或错误信息
[ ] AI 调用仅发生在后台 Job（Sidekiq）中
```

---

# 12. Engineering AI Harness

PallasTrade 交付的源码需要支持客户通过 AI 进行：

-功能优化；
-新功能开发；
-API 修改；
-SDK 同步；
-Gem 修改；
-支付开发；
-数据库迁移；
-Admin 和 Storefront 修改；
-文档回写；
-测试补充；
-架构重构。

Harness 的目标不是控制拥有源码的客户，而是提供官方推荐的安全开发路径。

## 12.1 Harness 核心资产

```text
AGENTS.md
ARCHITECTURE.md
Change Manifest
Exec Plan
Obligations Matrix
Impact Map
Skills
Agents
Commands
Hooks
Evaluators
Evals
Handoff
```

## 12.2 标准变更流程

```text
任务分类
→ Change Manifest
→ 影响分析
→ Exec Plan
→ 契约优先设计
→ 代码实现
→ 测试
→ 文档回写
→ 独立 Agent Review
→ CI Gate
→ Release Impact
```

## 12.3 强制同步关系

```text
API 修改
→ OpenAPI + SDK + Contract Test

Gem 公共接口修改
→ Gem Test + 版本决策 + Changelog

数据库修改
→ Migration + Backfill + 回滚评估

支付修改
→ 幂等 + 验签 + 金额校验 + 退款测试

行为修改
→ Product Spec + 不变量测试 + 文档
```

## 12.4 支付高风险门禁

任何支付目录变化必须触发：

```text
Payment Contract Reviewer
Security Reviewer
Idempotency Tests
Webhook Replay Tests
Amount/Currency Integrity Tests
Refund Invariant Tests
Sensitive Data Scan
Storefront Payment Regression
```

---

# 13. 客户源码自主修改模式

客户获得源码后，可以修改甚至删除 Harness、激活或升级代码。

因此正式定义三种模式。

## 13.1 Standard Distribution

客户不修改 Core，主要通过配置和 Extension 开发。

支持：

* 官方标准版本升级；
  -标准数据库 Migration；
  -支付模块升级；
  -标准兼容验证；
  -标准技术支持。

## 13.2 Certified Fork

客户修改 Core，但保留：

* PallasTrade 基线 Tag；
  -Git 历史；
  -Change Manifest；
  -Migration；
  -OpenAPI；
  -SDK；
  -测试；
  -Harness 记录。

支持：

* AI 升级分析；
  -三方差异；
  -冲突定位；
  -升级 PR；
  -兼容认证；
  -专业支持。

## 13.3 Unmanaged Fork

客户任意修改项目。

官方提供：

* 新版本说明；
  -安全公告；
  -PallasTrade 版本差异；
  -通用升级文档；
  -按项目提供迁移服务。

不承诺：

-镜像直接替换；
-Gem 直接升级；
-数据库自动兼容；
-客户定制功能回归；
-自动升级成功。

---

# 14. PallasTrade 自有升级体系

PallasTrade 后续发布只基于自己的版本历史：

```text
PallasTrade 1.0
→ PallasTrade 1.1
→ PallasTrade 1.2
```

所有新功能、缺陷修复、安全修复和架构调整均来自 PallasTrade 自主研发。

## 14.1 官方制品的作用

官方 Docker 镜像、Gem、SDK 和 Release 仍用于：

* 新客户交付；
  -Standard Distribution 客户升级；
  -版本事实基线；
  -安全扫描；
  -SBOM；
  -问题复现；
  -Certified Fork 差异比较；
  -客户升级分析。

## 14.2 每个版本必须提供

```text
Release Manifest
Source Diff
Gem API Diff
OpenAPI Diff
SDK Diff
Schema Diff
Migration
Payment Contract Diff
配置变化
环境变量变化
Extension Compatibility
Security Advisory
Harness Eval Pack
AI Upgrade Plan
```

## 14.3 客户 Fork 升级（AI 辅助分析，非自动升级）

**定位约束**：升级分析 Agent 是**辅助决策工具**，不是自动升级引擎。以下场景必须由人工审查和决策：

- 数据库 migration 冲突
- 支付 Gateway 逻辑变更
- 状态机（订单/支付/库存）修改
- 认证与权限逻辑变更
- 涉及金额计算的代码变化
- 同一文件的同一方法被双方修改

三方比较：

```text
A：客户最初使用的 PallasTrade 官方版本
B：客户当前修改后的版本
C：新的 PallasTrade 官方版本
```

升级 Agent 提供分析输出：

```text
客户从 A 到 B 修改了什么
PallasTrade 从 A 到 C 修改了什么
双方是否修改了相同文件、领域、API、数据库或支付逻辑
```

Agent 输出（辅助人工决策）：

```text
可自动合并项（纯文本级无冲突 diff）
AI 建议合并项（语义分析建议，需人工确认）
⚠️ 需要人工决策项（涉及数据库/支付/状态机/认证/金额）
  └── 每项附带：冲突位置、双方修改摘要、推荐决策方向、风险等级
数据库风险（migration 冲突、schema 变更、backfill 需求）
API 冲突（路由、序列化、参数校验）
支付风险（绝对禁止自动合并）
测试缺口（客户修改缺少的测试覆盖）
升级 PR（AI 生成，人工 Review + CI 验证后合并）
```

**关键安全约束**：

```text
[ ] 支付相关 diff 绝不由 Agent 自动合并
[ ] Migration 绝不由 Agent 自动执行
[ ] Agent 生成的 PR 必须通过 CI Gate + 人工 Code Review
[ ] 涉及金额/币种/价格计算的变更标记为最高风险
[ ] 升级分析结果本身不作为决策依据，仅作为决策参考材料
```

---

# 15. 独立安全维护体系

不依赖外部 Commerce 项目更新后，PallasTrade 必须自行承担安全维护责任。

需要建立：

```text
Ruby 与 Rails 版本管理
第三方 Gem 漏洞监控
npm 依赖漏洞监控
Docker 基础镜像更新
操作系统漏洞监控
支付 Provider API 变化监控
支付 SDK 升级
Webhook 安全评审
SBOM
依赖许可证审计
渗透测试
安全发布流程
```

安全来源不依赖某个 Commerce 项目，而是直接监控：

```text
Ruby / Rails 安全公告
Gem 和 npm 依赖公告
操作系统与容器漏洞
支付平台官方公告
数据库与 Redis 安全公告
CVE 数据源
```

---

# 16. License 与 Customer Control Plane

独立建设：

```text
PallasTrade Control Plane
├── Customers
├── Contracts
├── Licenses
├── Editions
├── Entitlements
├── Installations
├── Activations
├── Release Access
├── Support Eligibility
└── Audit Logs
```

Control Plane 负责：

* 客户主体；
  -合同；
  -License；
  -功能权益；
  -安装实例；
  -激活；
  -版本下载权限；
  -支持资格；
  -安装和版本可见性；
  -异常使用线索。

由于源码客户可以删除激活代码，激活不能绝对阻止复制和二次销售。

保护体系必须是：

```text
商业许可证
+ 商标保护
+ 客户专属源码包
+ Build ID
+ 下载审计
+ 激活记录
+ 官方版本和升级权益
+ 技术支持
+ 法律责任
```

不得通过远程 Kill Switch 破坏客户订单、支付或数据。

### 16.1 Control Plane 建设策略

Control Plane 本质是一个**独立的 SaaS 运营平台**，涉及客户管理、激活、版本分发、审计日志等完整功能。不建议从零自建。

**推荐渐进路线**：

```text
1.0 阶段：License Key 文件机制
  ├── 使用成熟的第三方 License 方案（如 Keygen、许可链）
  ├── License 文件包含：客户 ID、版本、权益范围、过期时间、签名
  ├── 应用启动时本地验证 License 签名
  └── 不依赖外部服务即可完成验证（离线友好）

2.0 阶段：精简 Control Plane
  ├── 客户注册与管理
  ├── License 生成与分发
  ├── 版本下载权限控制
  └── 基础审计日志

3.0 阶段：完整 Control Plane
  └── 全部功能（合同管理、安装追踪、异常检测等）
```

**1.0 阶段最小要求**：

```text
[ ] 每个分发的源码包包含唯一 Build ID
[ ] License 文件可验证签名，防止篡改
[ ] 不依赖远程服务即可完成 License 验证
[ ] License 过期 / 权益不足时明确提示，不破坏已有数据
[ ] 不做任何形式的远程禁用或数据清除
```

---

# 17. 实施阶段

## MVP 边界原则

本方案涉及 5 个平台级别产品（Commerce Runtime、Product AI Runtime、Engineering Harness、Release & Upgrade Platform、Customer Control Plane），同时推进存在极高风险。

**采用分层 MVP 策略**：PallasTrade 1.0 = 阶段 0-4（源码冻结 + 部署 + 品牌化），其余进入 2.0/3.0 路线图，不阻塞 1.0 发布。

---

## 阶段 PVT：原型验证测试 —— 1.0 的前置阶段 ⚠️ 最高优先级

先于正式开发，用最小工作量跑通核心链路以校准真实工作量：

```text
拉取 Spree Commerce 源码
本地 docker-compose 跑通 Rails + PostgreSQL + Redis
跑通 Storefront 首页 → 商品 → 购物车 → Checkout
接入 Stripe Sandbox 并完成一笔测试支付
将 1 个 namespace（如 Spree::Core → PallasTrade::Core）完成重命名
运行全量测试，记录遇到的每一个问题
```

**PVT 输出**：

```text
PVT 报告：记录每个步骤的实际耗时
风险登记册：记录所有偏离预期的技术问题
1.0 计划校准：基于 PVT 数据修订阶段 1-4 的时间估算
Go/No-Go 决策：品牌化自动化脚本是否可行、支付接入是否畅通
```

**PVT 成功后进入正式阶段**，PVT 失败则先解决阻塞问题再进入阶段 1。

---

## 阶段 0：一次性源码冻结

```text
拉取全部必要源码
拉取三套在线支付源码
记录 Commit 和许可证
建立 SOURCE_MANIFEST
建立不可变基线 Tag
移除外部同步关系
```

## 阶段 1：原始系统部署

```text
Rails
Admin
Store API
Storefront
PostgreSQL
Redis
Sidekiq
搜索
Store Credit
线下支付
Stripe
Adyen
PayPal
```

## 阶段 2：Minimum Viable Harness

```text
AGENTS
Change Manifest
Obligations
Impact Map
Naming Audit
API/SDK Check
Gem Check
Payment Security Gates
Document Check
```

## 阶段 3：外部品牌化

```text
产品品牌
Admin
Storefront
API
SDK
环境变量
Docker
支付配置
回调地址
邮件和文档
```

## 阶段 4：内部深度品牌化

```text
Ruby Namespace
Gem
Engine
数据库
Events
Jobs
Queues
Redis Keys
Payment Gateway Classes
```

## 阶段 5：Extension Framework

```text
Provider Registry
Events
Admin Slots
Webhook Registry
Payment Gateway Contract
Extension Compatibility
```

## 阶段 6：Product AI Runtime

```text
AI Gateway
DeepSeek Adapter
Prompt Registry
AI 翻译
审计
配额
安全
质量 Eval
```

## 阶段 7：Harness 试点

```text
原功能优化试点
新功能试点
API + SDK 试点
Gem 修改试点
支付修改试点
```

## 阶段 8：客户源码交付

```text
Standard Distribution
Certified Fork
Unmanaged Fork
Customer Harness
AI Upgrade Agent
```

## 阶段 9：自有发布与 Control Plane

```text
PallasTrade Release Manifest
升级差异包
License
Installation
Release Access
Support Eligibility
```

---

# 18. PallasTrade 1.0 验收标准

## 18.1 1.0 MVP 验收（阶段 0-4：源码冻结 + 部署 + 品牌化）

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

## 18.2 2.0 验收（阶段 5-7：Extension Framework + AI Runtime + Harness 试点）

```text
[ ] Extension Framework 可运行（Provider Registry、Events、Admin Slots）
[ ] Adyen 和 PayPal 支付模块接入并通过 Sandbox 测试
[ ] AI Gateway + DeepSeek Adapter 独立运行
[ ] AI 翻译闭环完成（异步+缓存+降级）
[ ] AI 不影响核心交易可用性（模型不可用时验证通过）
[ ] Harness 试点：API+SDK+Gem 修改流程验证通过
[ ] Minimum Viable Harness 可约束代码同步关系
```

## 18.3 3.0 验收（阶段 8-9：客户交付 + 自有发布 + Control Plane）

```text
[ ] 客户源码自主修改模式（Standard/Certified/Unmanaged）明确且可运行
[ ] PallasTrade 自有升级体系可运行（Release Manifest、Diff、Migration）
[ ] AI 升级分析 Agent 可辅助分析客户 Fork（非自动执行）
[ ] License 文件机制可用（签名验证、离线友好）
[ ] 客户版本下载权限和基础支持资格管理可用
```

---

# 19. 第一批正式任务

## 19.1 PVT 阶段（最高优先级，先行执行）

```text
PT-PVT-001
拉取 Spree Commerce 源码并本地 docker-compose 跑通

PT-PVT-002
跑通 Storefront 完整购物链路（首页→商品→购物车→Checkout）

PT-PVT-003
接入 Stripe Sandbox 并完成一笔测试支付

PT-PVT-004
将 1 个 namespace 完成重命名并运行全量测试

PT-PVT-005
输出 PVT 报告，校准 1.0 计划
```

## 19.2 1.0 核心任务（阶段 0-4）

```text
PT-SOURCE-001
一次性拉取和冻结全部源码

PT-SOURCE-002
记录许可证、Commit 和初始来源，建立 SOURCE_MANIFEST

PT-REPO-001
建立 PallasTrade 自有仓库并移除外部同步关系

PT-PAYMENT-001
拉取 Stripe 支付源码并通过本地 Path Gem 部署

PT-PAYMENT-002
配置 Store Credit 和线下支付

PT-PAYMENT-003
完成 Stripe Sandbox 全矩阵测试（Authorize/Capture/Void/Refund/Webhook/幂等）

PT-LOCALIZE-001
完成外部品牌化（产品品牌、Admin、Storefront、API、Docker、邮件、文档）

PT-LOCALIZE-002
完成 Namespace、Gem 和数据库品牌化（基于自动化脚本，禁止手工逐文件修改）

PT-LOCALIZE-003
品牌化后全量回归测试通过

PT-HARNESS-001
建立 Minimum Viable Harness（AGENTS、Change Manifest、Obligations、命名审计）
```

## 19.3 2.0 任务（阶段 5-7）

```text
PT-PAYMENT-004
接入 Adyen 支付模块（复用 Stripe 测试范本）

PT-PAYMENT-005
接入 PayPal Checkout 支付模块

PT-EXTENSION-001
建立 PallasTrade Extension Framework

PT-AI-001
建立 AI Gateway 和 DeepSeek Adapter

PT-AI-002
完成 AI 多语言翻译闭环（异步+缓存+降级，Storefront 不直接调用 AI）
```

## 19.4 3.0 任务（阶段 8-9）

```text
PT-UPGRADE-001
建立 PallasTrade 自有 Release 体系与升级差异包

PT-UPGRADE-002
建立 AI 辅助升级分析 Agent（非自动升级引擎）

PT-CONTROL-001
建立 License 文件签名验证机制（1.0 阶段最小方案）

PT-CONTROL-002
建立客户版本下载与基础支持资格管理（2.0 阶段）
```

这个版本的核心边界已经变成：**Spree 只存在于初始来源档案中；从基线 Tag 之后，PallasTrade 是一条完全独立的产品和代码演进渠道线。**

---

# 20. 关键架构决策与风险登记册

## 20.1 关键架构决策（ADR，不可轻易推翻）

| 决策 | 理由 | 推翻条件 |
|------|------|---------|
| 一次性接管，不建立持续同步 | 避免长期维护外部依赖的工程成本 | 成本收益发生根本性变化 |
| 品牌化通过自动化脚本完成 | 100+ 表/上万处引用，手工不可行 | 自动化脚本本身成本超过手工成本 |
| AI 内容仅通过后台 Job 异步生成 | 防止 AI 延迟/不可用阻塞交易链路 | AI 推理延迟稳定 < 50ms |
| 支付分批接入（Stripe→Adyen→PayPal） | 降低并行调试复杂度 | Stripe 接入完成后评估 |
| 1.0 License 使用文件签名，非 Control Plane | 1.0 阶段无需完整的 SaaS 运营后台 | 客户量达到需要自动化管理的规模 |
| AI Upgrade Agent 定位为辅助分析工具 | 支付/migration/状态机冲突无法安全自动合并 | AI 能力发生质变 |
| PVT 先行，校准后再进入正式阶段 | 用实际工作量替代估算 | 团队对 Spree 源码有充分经验 |

## 20.2 已识别主要风险

| 风险 | 等级 | 缓解措施 |
|------|------|---------|
| 数据库品牌化中遗漏硬编码表名引用 | 高 | 自动化脚本 + 全量测试 + schema.rb 验证 |
| 支付 Webhook 本地调试环境复杂 | 中 | Stripe CLI 本地监听；Adyen/PayPal 使用 ngrok |
| AI 翻译被误用在同步请求路径 | 高 | 架构评审 + Code Review gate + 不变量测试 |
| 三套支付的 API/SDK 版本兼容 | 中 | 每套独立 Sandbox 环境，不共享配置 |
| Control Plane 自建导致 1.0 延迟 | 中 | 1.0 仅用 License 文件签名，Control Plane 进入 2.0 |
| 范围膨胀（同时推进 5 个平台） | 高 | 明确 1.0/2.0/3.0 边界，各版本不交叉 |

---

**下一步最重要的是执行 PVT（PT-PVT-001 至 PT-PVT-005），用真实跑通的数据校准本方案中的所有时间估算和优先级排序。**
