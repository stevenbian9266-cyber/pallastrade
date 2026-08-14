# PRD-20260814-admin-管理后台新增安全配置管理模块-oss-key-secret-值托管

| 元数据 | 值 |
|---|---|
| 状态 | reviewing（待用户确认） |
| 创建日期 | 2026-08-14 |
| 来源 | 管理后台新增安全配置管理模块（OSS Key / Secret 值托管） |
| 分类 | admin（自动判定） |
| 关联 Skill | pallastrade-admin、pallastrade-api-v3、pallastrade-security |
| 关联 REQ | REQ-20260814-admin-secret-manager.md（实施时生成） |
| 关联 PRD | N/A（查重未命中） |
| 需求类型 | 新功能 |

---

## 1. 背景与目标

- **一句话需求原文**：管理后台增加一个管理模块，专门管理比如 oss 的 key、一些 secret 值
- **背景**：
  - 当前 OSS / Stripe / Turnstile / 第三方集成等密钥散落在服务器 `.env` 文件（`deploy/.env.dev`、`.env.production`）与 `backend/config/environments/production.rb` 的 `ENV[...]` 读取逻辑中，运维需 SSH 上服务器改文件才能变更，缺少后台可视化、审计与安全语义。
  - PallasTrade **已有成熟的密钥托管参考实现**：`pallastrade_ai` 的 `ProviderSecret`（Active Record Encryption 非确定性加密 + `key_hint` 掩码 + `rotated_at` + fail-closed），本需求将其**泛化**为通用 Secret 管理模块，供 OSS 等任意配置消费。
  - 已有 `PallasTrade::Preference`（key/value）与 `PallasTrade::Security::Preferences` 预留钩子，可承载非敏感配置；**敏感值必须走加密存储**，不落入 Preference 明文列。
- **目标**：
  - 管理后台 Settings 区域新增「Security / 安全配置」模块，管理员可在 UI 管理 OSS Key、各类 Secret 值；
  - 敏感值**加密存储、只写不读**（创建后不回显明文，仅显示掩码 hint 与轮换时间）；
  - 提供 Admin API v3 端点，供消费方（后端服务）读取/校验；
  - OSS 存储服务配置从「仅 ENV」升级为「Secret 优先 → ENV 回退 → local」。
- **成功指标**：
  - 新增密钥可在后台 UI 创建/编辑/轮换，全程不明文回显；
  - OSS 上传不依赖 `.env` 中的 AccessKey 也能正常工作（从 Secret 读取）；
  - 所有敏感值不进 API 响应、日志、Sentry。

## 2. 用户故事 / 场景

- 作为**管理员**，我希望在后台集中管理 OSS/Stripe/Turnstile 等密钥，以便无需 SSH 即可配置与轮换。
- 作为**运维**，我希望密钥加密存储且永不回显，以便降低泄密风险并满足审计。
- 作为**开发者**，我希望新增第三方集成时直接复用 Secret 模块，以便不再散落 `.env`。
- 场景：
  - 正常：创建 `oss_access_key_id` / `oss_secret_access_key` / `oss_endpoint` → 后台保存（加密）→ 服务器 OSS 上传生效。
  - 正常：编辑既有密钥（新值替换，`rotated_at` 更新；留空表示不改动）。
  - 边界：未配置 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` → 保存失败（fail-closed），提示配置加密。
  - 边界：读取 API 仅返回 `{ configured, hint, rotated_at }`，永不返回明文。
  - 异常：密钥被消费方使用中删除 → 消费方回退 ENV/local 并记录 warning。

## 3. 功能需求（FR）

- FR-001：新增通用 `PallasTrade::Secret` 模型（`name`、`value`、`description`、`store` 作用域），`value` 用 Active Record Encryption 非确定性加密。
- FR-002：`name` 唯一（scope store），存储前缀/后缀掩码 `key_hint` 与 `rotated_at`。
- FR-003：未配置加密主密钥时创建/更新 **fail-closed**（raise，不落明文）。
- FR-004：Admin UI（Settings 导航新增「Security」项）：列表（name/description/hint/rotated_at/操作）、新建、编辑（值留空=不改）、删除、轮换。
- FR-005：Admin API v3：`GET/POST/PATCH/DELETE /api/v3/admin/secrets`，序列化仅暴露 `summary`（configured/hint/rotated_at），写入走加密。
- FR-006：OSS 消费集成：`config/environments/production.rb` 的 active_storage 选择逻辑改为「Secret 优先 → ENV 回退 → local」；提供 `PallasTrade::Secret.fetch(name)` 读取明文（仅服务端内部调用）。
- FR-007：权限控制：Secret 仅 `manage` 权限的管理员可写；读取/校验仅服务端内部。
- FR-008：迁移预填：首次部署自动将现有 `ENV["OSS_*"]` 等同步为 Secret 记录（若存在）。

## 4. 非功能需求（NFR）

- **安全**：值加密存储（非确定性，DB 泄露不可逆读）；永不进 API 响应/日志/Sentry/Sidekiq 参数；掩码 hint 展示；fail-closed。
- **性能**：Secret 读取服务端走 Rails 缓存（进程内），不每次查库；密钥量极小（几十条）。
- **兼容**：ENV 仍优先或回退，存量部署不破坏；`ProviderSecret` 保持独立不重构（避免 AI 模块回归）。
- **可维护**：复用 `SettingsConcern` 布局与声明式导航注册；与 `Preference` 机制并存（Preference 管非敏感配置）。

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001/002：创建 Secret 后 DB 中 `value` 为密文；`key_hint` 正确（前缀5+后缀4掩码）。
- AC-002 ← FR-003：无 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY` 时创建/更新抛 `EncryptionNotConfigured`，不落库。
- AC-003 ← FR-004：后台 Settings > Security 可新建/编辑/删除；编辑留空不改动值；`rotated_at` 在新值保存后更新。
- AC-004 ← FR-005：`GET /api/v3/admin/secrets` 响应无 `value` 明文，仅 summary；`POST` 后可读回 hint。
- AC-005 ← FR-006：删除 `.env` OSS key（模拟）后，上传图片仍成功（从 Secret 读取）；未配置 Secret 时回退 ENV，再回退 local。
- AC-006 ← FR-007：无 `manage` 权限的 admin 对 secrets 请求返回 403。
- AC-007 ← FR-008：迁移后 `oss_*` 三条 Secret 已预填（若 ENV 存在）。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | OSS、secret、production.rb | `config/environments/production.rb`（ENV 读 OSS key） | 部分——需改为 Secret 消费 |
| Core | `pallastrade_core/app/` | Preference、Security、Config | `app/models/pallastrade/preference.rb`（key/value + Security::Preferences 钩子） | 部分——敏感值需加密，不复用 Preference 明文列 |
| API | `pallastrade_api/app/` | secret、credential、serializer | `app/serializers/.../webhook_endpoint_serializer.rb`（secret 不回显模式） | 参考——序列化不暴露明文模式 |
| Admin | `pallastrade_admin/app/` | SettingsConcern、navigation、storefront | `controllers/concerns/settings_concern.rb`、`config/initializers/pallastrade_admin_navigation.rb`（settings 菜单项） | 部分——需新增 Security 菜单 + controller/view |
| Storefront | `storefront/src/` | secret、settings | 无 | 不涉及 |
| Platform | `platform/packages/` | sdk、secret | `sdk`（Admin SDK 客户端） | 需确认/扩展 Admin SDK 类型（可选） |

**关键参考（AI 层）**：`pallastrade_ai/app/models/pallastrade/ai/provider_secret.rb` —— **完整加密密钥托管实现**（encrypts + key_hint + rotated_at + fail-closed + credential_summary），本需求泛化复用其模式。

**结论**：Core/API/Admin 均需新建 Secret 相关代码；**不新增**第三方依赖（Active Record Encryption 已随 Rails 内置）；ProviderSecret 保持独立。Platform SDK 视范围可选扩展。

## 7. 技术影响

- **涉及组件**：
  - Core：新模型 `PallasTrade::Secret` + 迁移 `create_pallastrade_secrets`；`lib/pallastrade/core/engine.rb` 可注册读取 helper。
  - API：`PallasTrade::Api::V3::Admin::SecretsController` + serializer + routes（`/api/v3/admin/secrets`）。
  - Admin：`SecretsController`（SettingsConcern）+ view（列表/表单，值输入框 type=password 且不回显）+ 导航项注册（`settings_nav.add :security`）。
  - App：`backend/config/environments/production.rb` OSS 选择逻辑改造；可选 `config/initializers/pallastrade.rb`。
  - Platform：`platform/packages/sdk` 视范围补充 `secrets` 类型（可选，P2）。
- **数据库**：新增 `pallastrade_secrets` 表（name/value/description/key_hint/rotated_at/store_id/timestamps）。
- **加密**：依赖 `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`（与 AI ProviderSecret 同一套，服务器 .env 已具备）。
- **接口**：新增 Admin API 端点，同步 `backend/public/api-docs/admin.yaml`。
- **影响面**：`harness affected --base origin/main`（预计 backend gem 变更 → Backend CI + doc-impact + admin 相关）。

## 8. 测试计划

- **新增测试**：
  - `backend/spec/models/pallastrade/secret_spec.rb`（AC-001/002：加密、hint、fail-closed、unique）
  - `backend/spec/requests/api/v3/admin/secrets_spec.rb`（AC-004/006：summary 序列化、权限 403、CRUD）
  - `backend/spec/requests/pallastrade/admin/secrets_spec.rb`（AC-003：后台 UI CRUD + 留空不改）
  - `backend/spec/models/pallastrade/secret_consumption_spec.rb` 或集成（AC-005：OSS 消费回退链）
- **更新测试**：`backend/spec/requests/api/v3/admin/...` 权限相关若有 `secrets` scope 断言需同步。
- **AC 映射**：AC-001~007 → 上述文件；AC-005 需真实/桩 OSS。

## 9. 文档同步清单（知识同步门）

- [ ] API 文档：`backend/public/api-docs/admin.yaml` + `platform/docs/api-reference/`（新增 secrets 端点）
- [ ] Skill：`pallastrade-admin/SKILL.md`（Settings 导航新增项）、`pallastrade-api-v3/SKILL.md`（secrets 端点）、`pallastrade-security/SKILL.md`（密钥管理语义）
- [ ] 反模式/场景库：新增 GS 场景（Secret 只写不读 / fail-closed）
- [ ] `docs/prd/README.md` 索引更新
- [ ] 本 PRD 状态流转（reviewing → approved → implementing → done）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-14 | 0.1 | 初稿（骨架 + 完整扩充，待用户确认） | AI |

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
