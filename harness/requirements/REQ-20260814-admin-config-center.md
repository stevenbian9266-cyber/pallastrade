# REQ-20260814-admin-config-center — 管理后台统一配置中心

> 关联 PRD：`docs/prd/admin/PRD-20260814-admin-管理后台新增安全配置管理模块-oss-key-secret-值托管.md`（v0.2 统一配置中心）
> 用户确认：2026-08-14「实施」（R7 明确肯定）

---

## Step 0：跨层搜索（6 层强制）

| 层 | 搜索路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | OSS、ENV、production.rb | `config/environments/production.rb`（`ENV["OSS_*"]` 决定 active_storage） | 部分——Boot ENV 同步后可零改动消费 |
| Core | `pallastrade_core/app/models/` | Preference、Config、Security | `pallastrade/preference.rb`（key/value + Security::Preferences 钩子） | 部分——非敏感基础存在，需新建加密模型 |
| Core | `pallastrade_core/app/services/` | config、settings | 无专门配置服务 | 需新建 ConfigCenter 读取层 |
| API | `pallastrade_api/app/controllers/` | config、secret | `v3/admin/`（API Key 等资源控制器模式） | 需新建 config_items 端点 |
| Admin | `pallastrade_admin/app/controllers/` | SettingsConcern、settings | `concerns/settings_concern.rb`、`api_keys_controller.rb` 等 Settings 控制器 | 需新建 ConfigItemsController |
| Admin | `pallastrade_admin/app/views/` | settings | `pallastrade/admin/<resource>/` ERB 模式 | 需新建 views |
| Storefront | `storefront/src/` | config、setting | 无 | 不涉及 |
| Platform | `platform/packages/` | sdk | `sdk`（Admin SDK 客户端） | 可选扩展类型 |

**关键参考**：
- `pallastrade_ai/app/models/pallastrade/ai/provider_secret.rb` —— 加密密钥托管成熟实现（encrypts + key_hint + rotated_at + fail-closed + credential_summary）
- `pallastrade_ai/app/models/pallastrade/ai/setting.rb` —— 非敏感配置参考
- `pallastrade_admin/config/initializers/pallastrade_admin_navigation.rb` —— settings 导航项注册（`settings_nav.add`）
- `pallastrade_admin/config/initializers/pallastrade_admin_tables.rb` —— table registry 注册

**结论**：Core/API/Admin 三层需新建代码；不新增第三方依赖（Active Record Encryption 已内置）；ProviderSecret 保持独立。

---

## Step 1：Skill 文件咨询（强制）

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用 |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已评估 | 决策树：优先 Settings/Config → 事件 → DI；本需求属「新增模块」，走 Admin/Generator 层 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | admin scaffold 生成器路径 + `PallasTrade.admin.tables.register` + 声明式导航（`settings_nav.add :key, label:, url:, position:`）|
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已评估 | 本需求不涉及 catalog，无影响 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ✅ | ✅ 已读 | API v3 约定：prefixed ID、`{data, meta}` 信封、Admin API secret key/JWT、序列化不暴露敏感字段（webhook secret 模式） |
| `pallastrade-security` | ✅ | ✅ 已读 | Secret 只写不读/fail-closed 语义（沿用 ProviderSecret 模式） |
| `pallastrade-events-webhooks` | ✅ | ✅ 已评估 | 复用事件机制做缓存失效广播 |
| `pallastrade-deployment` | ✅ | ✅ 已评估 | .env 瘦身与 ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY 引导 |
| `pallastrade-testing` | ✅ | ✅ 已评估 | RSpec 模式：model/request/admin spec 划分 |

---

## 需求标题

管理后台统一配置中心：集中管理已有及未来关键参数（含 Secret），应用从模块取数、Boot 同步 ENV，不再依赖 .env 逐项配置。

## 任务类型

新功能

## 需求描述

- 后台 Settings 新增「配置中心」，按分组管理配置项（secret/string/boolean/number 四种类型）。
- secret 类型加密存储、只写不读（掩码 hint + rotated_at + fail-closed）。
- 应用读取层 `PallasTrade::ConfigCenter.get(key)`：配置中心 → ENV → 默认值，进程内缓存。
- Boot 初始化器把配置中心已配置项注入 ENV（`oss.access_key_id` → `OSS_ACCESS_KEY_ID`），存量 `ENV[...]` 代码零改动生效。
- 导入向导从 `.env` 识别参数批量导入。
- Admin API v3 `/api/v3/admin/config_items`（secret 序列化仅 summary）。

## 影响范围

- `backend/pallastrade_gems/pallastrade_core/`：新模型 ConfigItem + 迁移 + ConfigCenter 读取层 + Boot 初始化器
- `backend/pallastrade_gems/pallastrade_api/`：Admin ConfigItemsController + serializer + routes
- `backend/pallastrade_gems/pallastrade_admin/`：ConfigItemsController + views + 导航项
- `backend/app/`：`config/initializers/config_center.rb`（宿主装配）
- `backend/public/api-docs/admin.yaml`：新增端点
- 测试：model/lib/request/admin spec

## 技术方案（初步）

1. Core：`PallasTrade::ConfigItem`（key/group/value_type/value/default_value/description/key_hint/rotated_at，store scope，secret 加密列）。
2. Core：`PallasTrade::ConfigCenter` 读取层（get/fetch_secret，进程内缓存，ENV 映射）。
3. Core：Boot 初始化器（`config_center.boot_sync_env`），把配置项注入 ENV（配置中心优先）。
4. API：`/api/v3/admin/config_items` CRUD + `import` 端点；secret 序列化仅 summary。
5. Admin：Settings 导航「配置中心」+ 分组列表/表单/导入向导（沿用 SettingsConcern + table registry）。
6. App：装配初始化器；事件缓存失效。

## 风险点

- 加密主密钥缺失 → secret 写入 fail-closed（已在 ProviderSecret 验证）。
- Boot ENV 注入与显式 ENV 优先级冲突 → 设计为「配置中心优先，ENV 显式可覆盖」开关。
- 导入向导误导入 → 仅导入已知 key 白名单 + 预览确认。
- 缓存失效时效 → 事件广播 + 短 TTL 兜底。
