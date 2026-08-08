# REQ-20260808-ai-tools-optimization — AI Tools 模块优化

> 关联 PRD：`docs/prd/api/PRD-20260808-api-...-ai-tools-模块优化-...`
> 关联审计：`harness/requirements/REQ-20260808-ai-tools-audit.md`
> 用户已确认"实施 P0-P2"。

## 实施范围

### P0（阻断性）
1. **locale 修复**：`pallastrade_ai/config/locales/{en,zh-CN}.yml` 命名空间对齐 `PallasTrade.t`（`en.pallastrade.*`）+ 补 `ai_tools`/`save`/`manage`/`view`/`settings`/`updated` 等 key；zh-CN 用真实中文（当前是拼音乱写）
2. **添加 Provider 入口**：`ai_controller.rb` 加 `create_provider` action + 路由；providers 页面加"添加 Provider"表单（选 DeepSeek/OpenAI + API key）→ 创建 integration → `ProvisionProviders` + `ProvisionModels` 自动 provision 预设模型

### P1（体验）
3. **预设模型可见**：models 页面未配置 provider 时显示 catalog 预设（灰显 + 引导）
4. **空状态引导**：providers 空时显示引导文案
5. **视图 i18n**：providers/models 硬编码英文 → i18n

### P2（工程）
6. **API 文档**：`/api/v3/admin/ai/*` 入 `backend/public/api-docs/admin.yaml`
7. **AI 模块测试**：新建 `pallastrade_ai/spec/` 基础测试（service/controller）

## 关键文件

| 文件 | 变更 |
|---|---|
| `pallastrade_ai/config/locales/en.yml` | 命名空间 + 补 key |
| `pallastrade_ai/config/locales/zh-CN.yml` | 真实中文 |
| `backend/app/controllers/pallastrade/admin/ai_controller.rb` | create_provider |
| `backend/app/views/pallastrade/admin/ai/{index,providers,models}.html.erb` | 入口/引导/预设 |
| `backend/config/routes.rb` 或 admin gem routes | create_provider 路由 |
| `backend/public/api-docs/admin.yaml` | AI API 端点 |
| `pallastrade_ai/spec/` | 新建测试 |

## 验证
- 浏览器：AI Tools → 添加 DeepSeek/OpenAI → 预设模型出现（AC-001/002）
- 页面无 translation missing（AC-003）；zh-CN 真实中文（AC-004）
- models 未配置时灰显预设 + 引导（AC-005）
- admin.yaml 含 AI API（AC-006）
- AI spec 通过（AC-007）
- 反模式 0 error + harness 测试 + 后台 200
