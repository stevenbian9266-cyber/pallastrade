# PRD-20260814-admin-管理后台统一配置中心-集中管理关键参数与-secret-env-从模块取数

| 元数据 | 值 |
|---|---|
| 状态 | done（已实施部署，dev 验证通过）；v0.4 唯一源语义强化进行中 |
| 创建日期 | 2026-08-14 |
| 来源 | 管理后台统一配置中心：集中管理关键参数与 Secret，env 从模块取数 |
| 分类 | admin（自动判定） |
| 关联 Skill | pallastrade-admin、pallastrade-api-v3、pallastrade-security、pallastrade-deployment |
| 关联 REQ | REQ-20260814-admin-config-center.md（实施时生成） |
| 关联 PRD | N/A（查重未命中） |
| 需求类型 | 新功能 |

---

## 1. 背景与目标

- **一句话需求原文（澄清后）**：核心需求是通过一个管理后台来管理项目中已有以及未来会用到的一些关键参数信息，这样就不用一直在 env 里配置，**env 也从这个模块取数**。
- **背景**：
  - 当前所有关键参数（OSS key、Stripe key、Turnstile secret、站点参数等）散落在服务器 `.env` 文件（`deploy/.env.dev`、`.env.production`），由各代码点 `ENV[...]` 直接读取（如 `config/environments/production.rb` 的 `ENV["OSS_ACCESS_KEY_ID"]`）。变更配置 = SSH 改文件 + 重启，无后台可视化、无审计、易泄密（明文）。
  - 目标是建立**统一配置中心（Config Center）**：管理**已有 + 未来**全部关键参数（含敏感 Secret 与非敏感普通参数），应用运行时从该模块取数，`.env` 退化为「引导 + 默认值」，逐步做到「配置不落 env」。
  - PallasTrade 已有基础可复用：`PallasTrade::Preference`（key/value 非敏感配置）、`PallasTrade::Api::Config`（preference 机制）、`pallastrade_ai` 的 `ProviderSecret`（**加密密钥托管成熟实现**：Active Record Encryption + key_hint + rotated_at + fail-closed）、`SettingsConcern`（后台设置页布局）、声明式导航注册。
- **目标**：
  - 管理后台 Settings 区域新增「**配置中心 / Config Center**」模块，统一管理已有与未来的关键参数；
  - 支持两类值：**敏感（secret，加密存储、只写不读）**与**非敏感（string/boolean/number，明文可读）**；
  - 提供**应用读取层**：`PallasTrade::ConfigCenter.get(key)`（带缓存与默认值），并支持 **boot 时将配置同步进 ENV**，使现有 `ENV[...]` 读取点无需大改即可从模块取数；
  - **配置中心是唯一配置源（single source of truth）**：参数在后台设置保存即生效，应用通过 `ConfigCenter.get(key)` 取「参数名 + 值」，**无需在 .env/配置文件中手填值**；ENV 仅作为启动兜底（配置中心未设置时才回退），不提供「ENV 优先」开关；
  - 提供**一次性初始化向导**（原「Import from ENV」改名）：仅用于首次把现有 `.env` 中的关键参数迁入配置中心，UI 明确标注「仅首次迁移用，迁移后配置中心为唯一源」；
  - `.env` 最终只保留「加密主密钥 / 数据库连接 / Rails 引导」等基础设施值。
- **成功指标**：
  - 90% 以上现有业务参数（OSS/Stripe/Turnstile/站点）可从后台配置并立即生效（无需改 .env）；
  - 敏感值全程不明文回显、不进日志/API/Sentry；
  - 新增第三方集成不再新增 .env 项，改在后台添加配置项。

## 2. 用户故事 / 场景

- 作为**管理员/运维**，我希望在后台集中查看与管理所有关键参数（含 Secret），以便不再 SSH 改 `.env`、可审计、可轮换。
- 作为**开发者**，我希望新增集成时在配置中心添加参数、代码用统一读取 API，以便不再散落 `ENV[...]`。
- 作为**系统**，我希望 boot 时自动把配置中心的值注入 ENV，以便存量 `ENV[...]` 读取代码零改动生效。
- 场景：
  - 正常：后台「配置中心」→ 分组「OSS」→ 配置 `access_key_id / secret_access_key / endpoint` → 保存 → 新部署/重载后 OSS 上传生效（或进程内缓存失效即时生效）。
  - 正常：普通参数（如 `site.name`、`checkout.min_order_amount`）后台编辑，进程内缓存失效后新值生效。
  - 正常：导入向导把当前 `.env` 中已识别参数一次性写入配置中心。
  - 边界：secret 类型保存后只显示掩码 hint（`LTAI••••••••••••abcd`）与轮换时间，永不回显明文。
  - 边界：未配置 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` → secret 类型保存失败（fail-closed）。
  - 边界：配置中心未设置某参数 → 读取层回退 `.env`/默认值，行为与现状一致。
  - 异常：某参数被删除而代码仍读取 → 记录 warning 并回退默认值，不崩溃。

## 3. 功能需求（FR）

- FR-001：新增配置项模型 `PallasTrade::ConfigItem`（`key`、`group`、`value_type[secret|string|boolean|number]`、`value`、`description`、`default_value`、`store` 作用域、`updated_at`/`rotated_at`）。
- FR-002：`key` 唯一（scope store），命名规范 `group.name`（如 `oss.access_key_id`）；`secret` 类型 `value` 用 Active Record Encryption 非确定性加密，其他类型明文/JSON 存储。
- FR-003：`secret` 类型未配置加密主密钥时创建/更新 **fail-closed**（raise，不落明文）；`secret` 保存后仅存 `key_hint`（前缀5+后缀4掩码）与 `rotated_at`。
- FR-004：Admin UI（Settings 导航新增「配置中心 / Config Center」项）：按**分组**展示列表（key/类型/描述/值摘要/更新时间/操作）、新建、编辑（secret 留空=不改）、删除、**一次性初始化向导**（原「Import from ENV」：从 `.env` 识别参数批量导入，UI 标题与文案明确标注「仅首次迁移用，配置中心为唯一源」，迁移后请直接在后台设置并保存参数）。
- FR-005：Admin API v3：`GET/POST/PATCH/DELETE /api/v3/admin/config_items`（含 `group` 筛选与导入端点）；`secret` 类型序列化仅暴露 `{configured, hint, rotated_at}`，**永不返回明文**；非 secret 类型暴露值。
- FR-006：**应用读取层**：`PallasTrade::ConfigCenter.get(key, default: nil)`（进程内缓存 + 可强制刷新），统一语义：**配置中心（唯一源） → ENV（兜底） → 默认值**；`PallasTrade::ConfigCenter.fetch_secret(key)` 仅服务端内部读取明文。
- FR-007：**Boot ENV 同步**：初始化器在启动时把配置中心已配置项 merge 进 `ENV`（key 用规范化映射，如 `oss.access_key_id` → `OSS_ACCESS_KEY_ID`），使存量 `ENV[...]` 读取点（如 `production.rb` 的 OSS 逻辑）**零改动**从模块取数；**配置中心永远优先覆盖 ENV（无 env_precedence 开关）**，ENV 仅在配置中心未设置时兜底。
- FR-008：**一次性初始化向导**：首次部署时可将现有 `ENV["OSS_*"]`、`ENV["STRIPE_*"]`、`ENV["TURNSTILE_*"]` 等已识别参数同步为配置项（敏感类型自动归类）；该向导仅供**首次迁移**，UI 明确标注「仅首次迁移用，配置中心为唯一源」。
- FR-009：权限控制：配置项仅 `manage` 权限管理员可写；读取层仅服务端内部；Admin API 遵循现有 scope。
- FR-010：缓存与生效：配置读取进程内缓存（短 TTL 或事件失效）；后台更新后通过事件广播触发缓存失效，支持不重启生效。

## 4. 非功能需求（NFR）

- **安全**：`secret` 值加密存储（非确定性，DB 泄露不可逆读）；永不进 API 响应/日志/Sentry/Sidekiq 参数；掩码 hint 展示；fail-closed；`fetch_secret` 仅内部调用。
- **性能**：配置读取走进程内缓存（LRU/TTL），不每次查库；配置量小（数百条级）。
- **兼容**：`.env` 仍作为引导与默认来源，存量部署不破坏；`ProviderSecret` 保持独立不重构；`Preference` 继续承载框架内部偏好。
- **可维护**：分组管理；`config/settings.yml`（可选 schema 声明：key/类型/默认值/是否敏感）作为配置项目录，减少手工录入。
- **可维护**：复用 `SettingsConcern` 布局与声明式导航注册；与 `Preference` 机制并存（Preference 管非敏感配置）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/002：创建 `secret` 类型配置项后 DB 中 `value` 为密文、`key_hint` 正确（前缀5+后缀4掩码）；非 secret 类型明文存储且 API 可读。
- AC-002 ← FR-003：无 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` 时创建/更新 secret 抛 `EncryptionNotConfigured`，不落库。
- AC-003 ← FR-004：后台 Settings > 配置中心 按分组展示/新建/编辑/删除；secret 编辑留空不改动值；`rotated_at` 在 secret 新值保存后更新；**一次性初始化向导**可将 `.env` 参数批量导入，且 UI 明确标注「仅首次迁移用，配置中心为唯一源」。
- AC-004 ← FR-005：`GET /api/v3/admin/config_items` 中 secret 项无 `value` 明文，仅 summary；非 secret 项返回值；`POST` 后可读回 hint。
- AC-005 ← FR-006/007：`PallasTrade::ConfigCenter.get('oss.access_key_id')` 返回配置中心值；配置中心未设置时回退 `ENV['OSS_ACCESS_KEY_ID']`；boot 后 `ENV['OSS_ACCESS_KEY_ID']` 已由配置中心注入且**覆盖原 ENV 值（无 ENV 优先开关）**；删掉 `.env` OSS key（模拟）后上传图片仍成功。
- AC-006 ← FR-009：无 `manage` 权限的 admin 对 config_items 写请求返回 403。
- AC-007 ← FR-008：一次性初始化向导迁移后 `oss_*`、`stripe_*` 等已识别参数成为配置项（若 ENV 存在），且向导 UI 含唯一源标注。
- AC-008 ← FR-010：后台更新配置项后，进程内缓存失效（事件广播），无需重启即生效（验证 `ConfigCenter.get` 返回新值）。
- AC-009 ← FR-006/007（v0.4）：配置中心已设置的值在 ENV 存在且不同时，`ConfigCenter.get` 返回**配置中心值**（唯一源优先）；`sync_env!` 不再接受 `env_precedence` 参数（已移除）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | OSS、secret、ENV、production.rb | `config/environments/production.rb`（ENV 读 OSS key 决定 active_storage） | 部分——经 Boot ENV 同步可零改动消费 |
| Core | `pallastrade_core/app/` | Preference、Security、Config | `app/models/pallastrade/preference.rb`（key/value + Security::Preferences 钩子） | 部分——非敏感配置可扩展；敏感需新加密模型 |
| API | `pallastrade_api/app/` | Config、jwt_secret_key、credential | `lib/pallastrade/api/configuration.rb`（Config preference 机制）、webhook serializer（secret 不回显） | 参考——配置机制 + 不回显模式 |
| Admin | `pallastrade_admin/app/` | SettingsConcern、navigation、settings | `controllers/concerns/settings_concern.rb`、`config/initializers/pallastrade_admin_navigation.rb`（settings 菜单项注册） | 部分——需新增配置中心菜单 + controller/view |
| Storefront | `storefront/src/` | config、setting | 无（前台不管理配置） | 不涉及 |
| Platform | `platform/packages/` | sdk、admin | `sdk`（Admin SDK 客户端） | 可选扩展 Admin SDK 类型 |

**关键参考（AI 层）**：`pallastrade_ai/app/models/pallastrade/ai/provider_secret.rb` —— **完整加密密钥托管实现**（encrypts + key_hint + rotated_at + fail-closed + credential_summary + key_hint_display），本需求泛化复用其模式；`pallastrade_ai` 的 `Setting` 模型（`content_logging_mode` 等）可作为非敏感配置参考。

**结论**：Core 新建 `ConfigItem` 模型 + `ConfigCenter` 读取层 + Boot ENV 同步初始化器；API/Admin 新增配置中心端点与 UI；**不新增**第三方依赖（Active Record Encryption 已内置）；`ProviderSecret` 保持独立。Platform SDK 视范围可选扩展。

## 7. 技术影响

- **涉及组件**：
  - Core：新模型 `PallasTrade::ConfigItem` + 迁移；`lib/pallastrade/config_center.rb`（读取层：get / fetch_secret / 缓存 / ENV 映射）；boot 初始化器（ENV 注入 + 缓存失效订阅）；可选 `config/settings.yml` schema 目录。
  - API：`PallasTrade::Api::V3::Admin::ConfigItemsController` + serializer + routes（`/api/v3/admin/config_items` + 导入端点）。
  - Admin：`ConfigItemsController`（SettingsConcern）+ view（分组列表/表单/导入向导）+ 导航项注册（`settings_nav.add :config_center`）。
  - App：`config/environments/production.rb` 等存量 `ENV[...]` 读取点**零改动**（由 Boot ENV 同步覆盖）；新增 `config/initializers/config_center.rb`。
  - Platform：`platform/packages/sdk` 补充 `configItems` 类型（可选，P2）。
- **数据库**：新增 `pallastrade_config_items` 表（key/group/value_type/value/key_hint/description/default_value/rotated_at/store_id/timestamps）。
- **加密**：依赖 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`（与 AI ProviderSecret 同一套，服务器 .env 已具备）。
- **接口**：新增 Admin API 端点，同步 `backend/public/api-docs/admin.yaml`。
- **影响面**：`harness affected --base origin/main`（预计 backend gem 变更 → Backend CI + doc-impact + admin 相关）。

## 8. 测试计划

- **新增测试**：
  - `backend/spec/models/pallastrade/config_item_spec.rb`（AC-001/002：secret 加密+hint+fail-closed+unique、value_type 校验）
  - `backend/spec/lib/pallastrade/config_center_spec.rb`（AC-005/008：读取回退链、ENV 映射、缓存失效）
  - `backend/spec/requests/api/v3/admin/config_items_spec.rb`（AC-004/006：summary 序列化、权限 403、CRUD、导入）
  - `backend/spec/requests/pallastrade/admin/config_items_spec.rb`（AC-003：后台 UI CRUD + 留空不改 + 分组展示）
  - `backend/spec/initializers/config_center_boot_spec.rb`（AC-005：boot ENV 注入）
- **更新测试**：`production.rb` OSS 相关若有 spec 需同步验证 ENV 注入后行为。
- **AC 映射**：AC-001~008 → 上述文件；OSS 端到端（AC-005 上传）用桩/真实 OSS 验证。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/`（新增 config_items 端点）
- [ ] Skill：`pallastrade-admin/SKILL.md`（Settings 导航新增配置中心）、`pallastrade-api-v3/SKILL.md`（config_items 端点）、`pallastrade-security/SKILL.md`（secret 只写不读/fail-closed）、`pallastrade-deployment/SKILL.md`（.env 瘦身与配置中心引导）
- [ ] 反模式/场景库：新增 GS 场景（配置中心 secret 只写不读 / Boot ENV 同步）
- [ ] `docs/prd/README.md` 索引更新（标题同步）
- [ ] 本 PRD 状态流转（reviewing → approved → implementing → done）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-14 | 0.1 | 初稿（骨架 + Secret 管理模块完整扩充） | AI |
| 2026-08-14 | 0.2 | 按用户澄清**升级为统一配置中心**：支持 secret/普通参数、ConfigCenter 读取层、Boot ENV 同步、导入向导、缓存失效 | AI |
| 2026-08-14 | 0.3 | 实施完成：ConfigItem/ConfigCenter/Boot ENV/API+Admin 全量实现，35 spec 全绿，dev 部署验证（含 secret 加密），i18n 补充 | AI |
| 2026-08-14 | 0.4 | **唯一源语义强化**（用户澄清）：Import from ENV 改为「一次性初始化向导」并标注唯一源；移除 `sync_env!` 的 `env_precedence` 开关（配置中心永远优先，ENV 仅兜底）；PRD/FR/AC 同步 | AI |

## 5. 验收标准（AC，与测试一一映射）

> ⚠️ 以下为示例，正式内容请删除注释标记并替换为真实 AC：
- <!-- AC-001 ← FR-001：<可验证的判定条件> -->
- <!-- AC-002 ← ... -->

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | | | |
| Core | `pallastrade_gems/pallastrade_core/app/` | | | |
| API | `pallastrade_gems/pallastrade_api/app/` | | | |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

**结论**：哪些层已有能力 / 哪些需新建 / 防重复判定

## 7. 技术影响

- 涉及组件 / 文件 / 依赖 / 数据库 / 接口
- 影响面（`harness affected --base origin/main` 输出）

## 8. 测试计划

- 新增测试文件（路径清单）
- 更新测试文件（路径 + 变更点）
- 覆盖的 AC 映射（AC-xxx → 测试文件）

## 9. 文档同步清单（知识同步门）

- [ ] API 文档（若涉及接口）：`backend/public/api-docs/*.yaml` + `platform/docs/api-reference/*.yaml`
- [ ] Skill 文档（doc-impact 规则）
- [ ] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）
- [ ] 反模式库 / 任务规则 / 场景库（如涉及）
- [ ] 本 PRD 状态更新 + `docs/prd/README.md` 索引

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| YYYY-MM-DD | 0.1 | 初稿 | AI |

## 回写记录（harness prd update）

| 日期 | 来源 | 操作者 |
|---|---|---|
| 2026-08-14 | 管理后台统一配置中心：集中管理关键参数与 Secret，env 从模块取数 | AI |

| 2026-08-14 | 优化：配置中心唯一源语义强化——Import from ENV 改为一次性初始化向导，移除 ENV 优先开关 | AI |
