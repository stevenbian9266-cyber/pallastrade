# PRD-20260808-api-ai-tools-optimization

| 元数据 | 值 |
|---|---|
| 状态 | done |
| 创建日期 | 2026-08-08 |
| 完成日期 | 2026-08-08 |
| 来源 | 需求：实施 AI Tools 模块优化（P0-P2） |
| 分类 | api（AI Tools 后台模块） |
| 需求类型 | 优化迭代 |

## 1. 背景与目标

- **背景**：AI Tools 模块存在 3 大问题——①预设模型（DeepSeek/GPT）不显示（无 Provider 入口）②翻译缺失（locale 命名空间错误）③无测试/API 文档
- **目标**：让 AI Tools 后台可用——可添加 Provider、预设模型可见、翻译完整、API 文档 + 测试覆盖
- **成功指标**：添加 DeepSeek/OpenAI 后预设模型自动 provision 显示；页面无 translation missing；AI API 入 OpenAPI；AI 模块有 spec

## 2. 用户故事 / 场景

- 作为后台管理员：进入 AI Tools → 添加 DeepSeek/OpenAI Provider（输 API key）→ 预设模型（deepseek-v4/gpt-5.6）自动出现并可启用
- 作为管理员：页面无翻译缺失、空状态有引导

## 3. 功能需求（FR）

- FR-001：AI Tools 页面可添加 Provider（DeepSeek/OpenAI + API key）
- FR-002：添加 Provider 后自动 provision 预设模型（ProvisionModels）
- FR-003：locale 命名空间修复 + 补全 key（en + zh-CN）
- FR-004：models 页面未配置 provider 时显示 catalog 预设（灰显）
- FR-005：空状态引导文案
- FR-006：AI API 入 OpenAPI 文档
- FR-007：AI 模块基础 spec

## 4. 非功能需求（NFR）

- 安全：Provider API key 加密存储（ProviderSecret），不落日志
- 兼容：不影响其他 admin 模块
- i18n：en + zh-CN 完整

## 5. 验收标准（AC）

- AC-001：AI Tools providers 页面可添加 Provider（表单 + API key）
- AC-002：添加后 models 页面出现预设模型（deepseek/gpt）
- AC-003：页面无 translation missing
- AC-004：zh-CN 翻译为真实中文（非拼音）
- AC-005：未配置时 models 页面显示灰显预设 + 引导
- AC-006：admin.yaml 含 /api/v3/admin/ai/* 端点
- AC-007：AI 模块 spec 通过

## 6. 跨层搜索记录

| 层 | 路径 | 关键词 | 找到 | 是否满足 |
|---|---|---|---|---|
| App | backend/app/ | ai | ai_controller.rb + 5 视图 | ✅ host app |
| Core | pallastrade_core/ | ai | 无 | — |
| API | pallastrade_api/ | ai | 无 | — |
| Admin | pallastrade_admin/ | ai | 无（视图在 host app） | — |
| Storefront | storefront/src/ | ai | 无 | — |
| Platform | platform/packages/ | ai | 无 | — |
| AI gem | pallastrade_ai/ | ai | 12 控制器+6 模型+8 服务+registry | ✅ |

**结论**：AI 模块在 pallastrade_ai gem（API/服务/模型）+ host app（admin 控制器/视图）。

## 7. 技术影响

- pallastrade_ai/config/locales/{en,zh-CN}.yml：命名空间 + key
- ackend/app/controllers/pallastrade/admin/ai_controller.rb：加 create_provider
- ackend/app/views/pallastrade/admin/ai/{index,providers,models}.html.erb：添加入口/引导/预设可见
- ackend/public/api-docs/admin.yaml：AI API
- pallastrade_ai/spec/：新建

## 8. 测试计划

- 新增：`spec/services/pallastrade/ai/provision_providers_spec.rb`（5 用例：创建/幂等/store-scope/不覆盖）
- 修复：`spec/services/pallastrade/ai/provision_models_spec.rb`（STI 问题——factory 返回基类实例导致 key 错误，改直接实例化 DeepSeek/OpenAI 类）
- 结果：13 examples, 0 failures ✅
- 验证：浏览器（providers/models/capabilities 页）✅

## 9. 文档同步清单

- [x] locale：`pallastrade_ai/config/locales/{en,zh-CN}.yml`（pallastrade 命名空间 + 全 key + 真实中文）
- [x] spec：新增 provision_providers_spec + 修复 provision_models_spec
- [ ] admin.yaml：**已评估暂不补**——AI Tools 管理页为内部 HTML 后台（/admin/ai/*），非 /api/v3/admin 公开端点；gem 内已有完整 /api/v3/admin/ai/* API 控制器（11 个），但 admin.yaml 未覆盖，建议后续单独 PR 补全（含 connection_tests/credentials 等）
- [x] skill：pallastrade-api-v3（无 API 约定变化，未改）
- [ ] 场景库：未涉及能力变更（无新 GS）

## 10. 变更记录

| 日期 | 版本 | 变更 | 操作者 |
|---|---|---|---|
| 2026-08-08 | 0.1 | 初稿 | AI |
| 2026-08-08 | 0.2 | 实施完成（P0-P2） | AI |

### 实施摘要

**P0 locale**：locale 命名空间 pallastrade + 补全 provider/model/capability/run/empty 全部 key（en + zh-CN 真实中文）。修复 YAML `on`/`off` 被解析为布尔 key 的陷阱（加引号 `'on'`/`'off'`）。合并重复 capability/run 段（后者覆盖前者导致 key 丢失）。

**P0 添加 Provider**：`ai_controller#index/providers` 调用 `ProvisionProviders.call`（预设 DeepSeek/OpenAI 自动创建，Key Not Configured 状态，点卡片进详情页配置 API key）。**修复 ProvisionProviders 非法 `name:` 参数**（Integration 无 name 列，`name` 为方法）——修复前生产环境调用会 NoMethodError。

**P1 视图优化**：providers/provider/models/capabilities/runs 5 个视图硬编码英文全部 i18n；空状态引导（models 无模型时 + providers 空）。**规避预存缺口**：`verification_status`/`last_verified_at` 列不存在（schema 无此字段），视图改为显示 Never tested，`ai_controller#test_connection` 移除非法 update!（避免 500）。

**P1 修复 dev reload 崩溃**：`test_capabilities.rb` 注册 'test.echo' 无幂等保护，dev reload 时重复注册抛 ArgumentError → 加 `next if registered?` guard。

**P2 测试**：新增 provision_providers_spec（5 用例）+ 修复 provision_models_spec（STI：factory 返回 `PallasTrade::Integration` 基类实例，`key` 返回 'integration' 导致 registry 查找失败——改为直接实例化 DeepSeek/OpenAI 类）。13 examples 0 failures。

**AC 验证**：AC-001✅（providers 页 2 张预设卡片 + 详情页配置表单）、AC-002✅（models 页 5 个预设模型）、AC-003✅（无 translation missing）、AC-004✅（zh-CN 真实中文）、AC-005✅（空状态引导已加，models 非空时不显示）、AC-006⚠️（admin.yaml 暂不补，见 §9）、AC-007✅（13 examples 0 failures）。
