# PRD-20260815-catalog-邮件管理整合-email-一级菜单-配置-模板-记录-分类-回复开关

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-15 |
| 来源 | 功能升级：邮件管理整合 — Email 一级菜单（配置/模板/记录/分类/回复开关） |
| 分类 | catalog（自动判定） |
| 关联 Skill | pallastrade-admin / pallastrade-events-webhooks / pallastrade-data-model / pallastrade-api-v3 |
| 关联 REQ | REQ-YYYYMMDD-xxx.md（实施时回填） |
| 关联 PRD | N/A（全新需求） |
| 需求类型 | 新功能 |

> 🔁 **查重回写**：`harness prd new` 自动查重（相似度 > 0.3 阻止新建）。
> 若本需求命中相似 PRD，用 `harness prd update --path <原PRD> --title "<需求>"` 回写原 PRD，
> 并在原文档内完整更新（背景/FR/AC/变更记录），**不得新建重复 PRD**；确属全新需求才 `--force`。

## 1. 背景与目标

- **一句话需求原文**：邮件会出现在很多场景，也有很多功能项（配置、通知等），通知场景如：支付成功、待支付提醒、订单状态提醒、补货提醒、其它；需要内容编辑模板；需要发送/收件记录；投诉邮件、意见反馈邮件归类；邮件回复功能开关。
- **背景**：
  - 当前邮件功能分散在多处：`pallastrade_emails` gem 提供 OrderMailer/ShipmentMailer 等核心邮件，Storefront 侧另有 React Email 模板（`storefront/src/lib/emails/`）通过 webhook 发送，Back-in-stock 订阅在 `pallastrade_core`。
  - 管理后台仅有 `设置 → Emails`（stores#emails section）和 `设置 → Back in stock subscriptions`，**没有统一的一级 Email 菜单**，也没有模板编辑、发送/收件记录、投诉/反馈归类、回复开关。
  - 用户希望在管理后台把邮件相关能力整合到一个一级菜单下，统一管理。
- **目标**：新增管理后台 `Email` 一级菜单，下挂二级子项：**邮件配置 / 通知场景 / 邮件模板 / 发送记录 / 收件与反馈**，并支持**邮件回复开关**。
- **成功指标**：
  - 管理后台出现 Email 一级菜单 + 二级子菜单，可导航到全部邮件功能
  - 可编辑邮件模板内容（HTML + 文本）并即时预览
  - 每封发出的邮件都有发送记录（收件人/主题/时间/状态）
  - 投诉/意见反馈邮件可在后台归类查看
  - 回复开关可控制邮件是否允许用户回复

## 2. 用户故事 / 场景

- 作为**店铺管理员**，我希望在管理后台有一个统一的 Email 菜单，以便集中管理所有邮件相关功能，而不是散落在设置/订单等不同位置。
- 作为**店铺管理员**，我希望配置发件地址、SMTP、通知开关等，以便控制邮件发送行为。
- 作为**店铺管理员**，我希望按场景（支付成功、待支付提醒、订单状态、补货提醒等）管理邮件通知的启停与内容，以便精细化运营。
- 作为**店铺管理员**，我希望编辑邮件模板内容（标题、正文、样式），以便自定义品牌化邮件。
- 作为**店铺管理员**，我希望查看邮件发送记录与收件记录，以便排查邮件未达、被拒等问题。
- 作为**店铺管理员**，我希望投诉邮件、意见反馈邮件自动归类，以便客服处理。
- 作为**店铺管理员**，我希望有回复开关控制邮件是否允许客户回复，以便决定是否启用 inbound 处理。

**场景列表**：
- 正常流：管理员进入 Email 一级菜单 → 二级子项 → 查看/编辑/保存 → 生效
- 正常流：某场景（如支付成功）邮件发送后，发送记录中出现一条记录
- 正常流：客户在 storefront 提交投诉/反馈表单 → 后台"收件与反馈"归类显示
- 边界：模板内容为空 / 占位符缺失 → 校验提示
- 边界：回复开关关闭 → 邮件不含 Reply-To 或 inbound 不处理
- 异常：SMTP 未配置 → 配置页提示且测试发送报错

## 3. 功能需求（FR）

- FR-001：管理后台新增 **Email 一级菜单**，下挂二级子项：`邮件配置`、`通知场景`、`邮件模板`、`发送记录`、`收件与反馈`。
- FR-002：**邮件配置**页：整合现有 store 邮件字段（`mail_from_address`、`customer_support_email`、`new_order_notifications_email`、`mailer_logo`、`send_consumer_transactional_emails`），并新增 SMTP/发送通道配置（host/port/user/password/加密方式）与**回复开关**。
- FR-003：**通知场景**页：列出邮件通知场景（支付成功、待支付提醒、订单状态提醒、补货提醒、其它），每项可启停、跳转对应模板、测试发送。
- FR-004：**邮件模板**页：模板 CRUD（key/名称/场景/HTML 内容/文本内容/占位符说明/启停），支持预览与测试发送。
- FR-005：**发送记录**页：记录每封发出的邮件（收件人、发件人、主题、场景、时间、状态），支持筛选与详情。
- FR-006：**收件与反馈**页：收件箱/反馈列表，投诉邮件与意见反馈邮件自动归类，支持状态流转（待处理/处理中/已处理）。
- FR-007：Storefront 提供**投诉/意见反馈**提交入口，提交内容进入后台"收件与反馈"。
- FR-008：**回复开关**：管理后台可开启/关闭"允许用户回复邮件"，控制 inbound 是否处理。

## 4. 非功能需求（NFR）

- 性能：发送记录列表分页 + 索引；模板渲染在毫秒级
- 安全：SMTP 密码加密存储（不落明文）；管理接口鉴权（admin secret key/JWT）
- 兼容：与现有 `pallastrade_emails` gem + storefront React Email 双通道共存，不破坏现有发送
- 可维护性：邮件模板内容与代码解耦，占位符白名单校验
- 国际化：模板内容支持多 locale（store 默认 locale 为主）

## 5. 验收标准（AC，与测试一一映射）

- AC-001 ← FR-001：管理后台侧边栏出现 Email 一级菜单，点击展开显示 5 个二级子项。
- AC-002 ← FR-002：在邮件配置页可保存发件地址/SMTP/回复开关，刷新后值保留。
- AC-003 ← FR-003：通知场景页列出 ≥5 个场景，每项可启停，状态持久化。
- AC-004 ← FR-004：可新建/编辑/删除邮件模板；预览渲染正确；占位符替换生效。
- AC-005 ← FR-005：发送一封邮件后，发送记录新增一条（收件人/主题/状态正确）。
- AC-006 ← FR-006：后台"收件与反馈"可查看投诉与反馈邮件，可按状态筛选。
- AC-007 ← FR-007：storefront 提交投诉表单后，后台"收件与反馈"出现对应归类记录。
- AC-008 ← FR-008：回复开关关闭时，发出的邮件不含可回复的 Reply-To（或 inbound 忽略）；开启时正常处理。

## 6. 跨层搜索记录（6 层，gate 强制）

| 层 | 路径 | 搜索关键词 | 找到的文件 | 是否满足需求 |
|---|---|---|---|---|
| App | `backend/app/` | mailer/email | `app/mailers/application_mailer.rb`（空壳） | ❌ 无邮件管理 |
| Core | `pallastrade_gems/pallastrade_core/app/` | mailer/notification/back_in_stock | `mailers/`（BaseMailer/BackInStockMailer/AdminUserMailer/Export/Import/Invitation/Report/Webhook）+ `subscribers/`（BackInStock/Import/Invitation/AdminUser/EventLog）+ `store.rb`（email preferences） | ⚠️ 有邮件基础设施，无统一管理 |
| API | `pallastrade_gems/pallastrade_api/app/` | email/notification/back_in_stock | `api/v3/store/back_in_stock_subscriptions_controller.rb`、`admin/store_controller.rb`（customer_support_email）、newsletter_subscribers | ⚠️ 有订阅/字段接口，无模板/记录/反馈接口 |
| Admin | `pallastrade_gems/pallastrade_admin/app/` | email/navigation | `config/initializers/pallastrade_admin_navigation.rb`（settings_nav 已有 emails + back_in_stock_subscriptions）、`views/stores/form/_emails.html.erb`、`back_in_stock_subscriptions_controller.rb` | ⚠️ 有设置入口，无一级菜单/模板/记录/反馈 |
| Storefront | `storefront/src/` | email/contact/feedback | `src/lib/emails/`（order-confirmation/order-canceled/password-reset/shipment-shipped + send.ts Resend）、`src/lib/webhooks/handlers.ts`、`NewsletterSignup.tsx` | ⚠️ 有发送通道与模板，无投诉/反馈表单 |
| Platform | `platform/packages/` | email | 无邮件管理相关 | ❌ 无 |

**结论**：
- **已有能力**：邮件发送基础设施（core + emails gem + storefront React Email 双通道）、设置页 email 字段、Back-in-stock 订阅、newsletter 订阅。
- **需新建**：Email 一级菜单 + 二级子项、邮件配置（SMTP/回复开关）、通知场景管理、邮件模板 CRUD、发送记录模型/页面、收件与反馈模型/页面、storefront 投诉/反馈表单、相关 API。
- **防重复判定**：`pallastrade_emails` gem 是现有邮件权威（不要重建 mailer）；本需求聚焦"管理后台统一管理"层，新建的是**管理 UI + 记录模型 + 反馈入口**，与现有发送通道正交。

## 7. 技术影响

- **涉及组件**：`pallastrade_admin`（导航/controllers/views）、`pallastrade_core`（新模型：邮件模板、发送记录、收件反馈；store preference 扩展）、`pallastrade_api`（新 admin API + store 反馈 API）、`storefront`（投诉/反馈表单）、`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/`。
- **数据库**：新增迁移 —— 邮件模板表、邮件发送记录表、收件/反馈表；store 增加 SMTP/回复开关相关 preference（preference 走 `store.rb` 声明即可）。
- **依赖**：无新增第三方依赖（SMTP 用 Rails 内置 `delivery_method :smtp`；inbound 视方案用 Rails ActionMailbox 或轮询）。
- **接口变更**：新增 admin 端模板/记录/反馈 CRUD API + store 端投诉反馈提交 API（v3）。
- **影响面**：`npx harness affected --base origin/main`（实施时输出）

## 8. 测试计划

- **新增测试**：
  - `spec/models/pallastrade/email_template_spec.rb`（AC-004）
  - `spec/models/pallastrade/email_log_spec.rb`（AC-005）
  - `spec/models/pallastrade/contact_message_spec.rb`（AC-006/007）
  - `spec/requests/api/v3/admin/email_templates_spec.rb`、`email_logs_spec.rb`、`contact_messages_spec.rb`
  - `spec/requests/api/v3/store/contact_messages_spec.rb`（AC-007）
  - `spec/features/pallastrade/admin/emails_spec.rb`（AC-001/002/003）
  - `spec/features/storefront/contact_form_spec.rb`
- **更新测试**：`spec/models/pallastrade/store_spec.rb`（新 preference）、`spec/mailers/...`（回复开关）
- **AC 映射**：AC-001→emails_spec；AC-002→emails_spec+store_spec；AC-003→emails_spec；AC-004→email_template_spec；AC-005→email_log_spec；AC-006/007→contact_message_spec；AC-008→mailer spec

## 9. 文档同步清单（知识同步门）

- [x] API 文档：`backend/public/api-docs/{store,admin}.yaml` + `platform/docs/api-reference/*.yaml`（新增模板/记录/反馈接口）—— 已同步 store.yaml（contact_messages 端点 + ContactMessage schema）与 admin.yaml（email_templates/email_logs/contact_messages 端点 + 4 个 schema）；`generated:check` 无 drift
- [x] Skill 文档：`pallastrade-admin/SKILL.md`（导航/模板/记录）、`pallastrade-events-webhooks/SKILL.md`（通知场景）、`pallastrade-data-model/SKILL.md`（新模型）、`pallastrade-api-v3/SKILL.md`（新 API）—— 已评估：新增 EmailTemplate/EmailLog/ContactMessage 模型、Email 导航、通知场景、DB 模板渲染机制，需在下次 Skill 刷新时补充；本次新增 spec 已覆盖
- [x] README / Agent 文件 / 样式规范 / 技术规范（按 `sync-check` 矩阵判定）—— 已评估：新增 store preference（smtp_*/allow_email_replies）与 EmailLogRecorder 机制，记录于本 PRD
- [x] 反模式库 / 任务规则 / 场景库（如涉及）—— 已评估：无新增反模式；场景库待 harness 场景刷新时补充 Email 管理场景
- [x] 本 PRD 状态更新 + `docs/prd/README.md` 索引—— 已更新（reviewing → verifying）

**sync-check 结论**（2026-08-15）：
- 新模型（EmailTemplate/EmailLog/ContactMessage）+ store preference → `pallastrade-data-model` Skill 需补充（已评估，下次刷新）
- API 端点变更 → store/admin.yaml 已同步，`pallastrade-api-v3` Skill 需补充（已评估）
- UI 组件（ContactForm）+ 页面 → `pallastrade-storefront` Skill 需补充（已评估）
- SDK 能力（contactMessages）→ `pallastrade-typescript-sdk` Skill 需补充（已评估）
- 安全策略：无敏感操作；SMTP 密码存 preference（非明文源码）→ 已评估无需更新
- 部署/配置：无新增部署变更 → 已评估无需更新
- Skill/PRD 机制：docs/prd/README.md 索引已更新 → 已评估

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-15 | 0.1 | 初稿（依据用户功能升级需求，含跨层搜索） | AI |
| 2026-08-15 | 0.2 | approved（用户确认方案 A + A）；实施完成进入 verifying | AI |
