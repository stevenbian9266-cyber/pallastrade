# 管理后台 AI Tools 模块检查报告

> 审计任务：GATE-2026-08-08T11-31-04（audit，dev 分支）
> 检查内容：AI Tools 信息缺失诊断 + 模块整体实现评估 + 优化方向

---

## 一、用户报告"AI Tools 信息缺失"的根因（3 个）

### 1️⃣ 预设模型（DeepSeek/GPT）不显示 —— 根因：无 Provider + 无创建入口
- ✅ 代码**有**预设模型：`provider_registry.rb` 注册 DeepSeek（deepseek-v4-flash/pro）+ OpenAI（gpt-5.6-sol/terra/luna），catalogs 有完整元数据（pricing/parameters/capabilities）
- ❌ **数据库 0 模型**：`ProvisionModels` 只在"存在 provider integration"时触发（`ai_controller#models` / `update_provider` / API `models_controller`）
- ❌ 当前 Store "shop" **0 integrations** → provision 永不触发 → 0 模型
- ❌ **AI Tools 页面无"添加 Provider"入口**（ai_controller 只有 index/providers/update/test/clear，无 create）→ 用户无法配置 → 预设模型永远不出现

### 2️⃣ 翻译缺失 —— 根因：locale 命名空间错误
- AI gem `en.yml` 用 `en: ai: menu: title: "AI Tools"`（`en.ai.*` 命名空间）
- 视图/控制器用 `PallasTrade.t(:ai_tools)` → 查 `en.pallastrade.ai_tools`（**不存在**）
- 页面显示 `translation missing: en.pallastrade.ai_tools` / `en.pallastrade.save`
- 缺失 key：`ai_tools`、`save`（视图中 `manage`、`view`、`settings`、`updated` 也可能缺）
- **根因**：AI gem locale 命名空间与 `PallasTrade.t`（`en.pallastrade.*`）约定不匹配

### 3️⃣ Capabilities 0 —— 根因：仅 dev/test 注册 + 未创建 store 记录
- 仅 `test.echo` capability（`test_capabilities.rb`，**production 不注册**）
- `CapabilitySetting`（store-scoped, active）记录未创建

---

## 二、模块整体实现评估

### ✅ 优点
| 方面 | 说明 |
|---|---|
| 架构分层 | API v3 控制器（12）+ 服务层（gateway/provision/catalog/provider adapter）+ 模型（6）+ jobs（3） |
| 安全 | ProviderSecret 加密存储、`key_hint_display`、连接测试、SSRF 防护中间件 |
| 可扩展 | provider registry + catalog + capability 注册机制、`non_secret_settings` |
| 预设完整 | recommended_models 含 pricing（input/output/cached/currency）、default_parameters、capabilities |

### ⚠️ 问题清单
| # | 问题 | 级别 |
|---|---|---|
| 1 | locale 命名空间错误 → 翻译缺失（ai_tools/save 等） | **P0** |
| 2 | 无"添加 Provider"入口 → 预设模型永不 provision | **P0** |
| 3 | providers/models/capabilities 空状态无引导 | P1 |
| 4 | production 无 capabilities（仅 test.echo） | P1 |
| 5 | 视图大量硬编码英文（'Test Connection'、'Key'、'Active'、'On/Off'） | P1 |
| 6 | AI API 未进 OpenAPI 文档（admin.yaml 无 /api/v3/admin/ai/*） | P2 |
| 7 | pallastrade_ai **无 spec**（测试缺失） | P2 |
| 8 | breadcrumb `PallasTrade.t(:ai_tools)` 同缺 | P0 |

---

## 三、优化方向（按优先级）

### P0（阻断性修复）
1. **修复 locale**：AI gem en.yml/zh-CN.yml 命名空间对齐 `PallasTrade.t`（`en.pallastrade.*` 或视图改用 `PallasTrade.t('ai.menu.title')`）；补 `ai_tools`、`save`、`manage`、`view`、`settings`、`updated` 等 key
2. **添加 Provider 入口**：AI Tools 页面新增"添加 Provider"（选 DeepSeek/OpenAI + 输入 API key → 创建 integration → ProvisionProviders + ProvisionModels 自动 provision 预设模型）

### P1（体验）
3. **预设模型可见性**：models 页面未配置 provider 时显示 catalog 预设（灰显 + "配置后自动启用"）
4. **空状态引导**：providers 空 → "配置 DeepSeek/OpenAI 开始使用 AI Tools"
5. **production capabilities**：注册非 test 的基础 capabilities 或页面说明
6. **i18n 完整**：视图硬编码英文 → i18n

### P2（工程）
7. **API 文档**：`/api/v3/admin/ai/*` 入 admin.yaml + `generated:check`
8. **模块测试**：补 pallastrade_ai 服务/控制器 spec
9. **skill 同步**：更新 `pallastrade-ai` 相关 skill（如有）
10. **验证证据**：修复后浏览器验证 AI Tools 页面（模型/翻译/引导）

---

## 四、验证证据（本次审计）
- Store "shop" integrations = 0；Models = 0、Providers = 0、Capabilities = 0
- registry：DeepSeek + OpenAI 预设存在（recommended_models 完整）
- locale：`en.ai.*`（非 `en.pallastrade.*`）；缺 ai_tools/save
- 浏览器：/admin/ai 显示 "translation missing" + 全 0 卡片
- AI 表 6 张已建（migrations 已跑）
- AI 模块无 spec；admin.yaml 无 AI API
