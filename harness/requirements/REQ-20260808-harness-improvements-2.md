# REQ-20260808-harness-improvements-2 — 实施评级改进建议

> 关联评级：`harness/requirements/REQ-20260808-harness-rating.md`（8.6/10）
> 用户已确认"实施"评级建议。

## 实施范围（6 项）

### 1. 反模式规则精化（AP-006 误报消除）
- **问题**：AP-006 无 excludeGlob，邮件模板（`lib/emails/`，邮件客户端不支持 CSS 变量 → 必须内联 hex）+ `globals.css`（token 定义源）+ `dev/emails/`（邮件预览页）被误报（约 80 个）
- **改**：`harness/policies/anti-patterns.json` AP-006 添加 `excludeGlob: "**/{emails,dev/emails}/**|**/globals.css"`

### 2. AP-009b 修复（防循环）
- `storefront/src/app/[country]/[locale]/layout.tsx:51` `.catch(() => [])` → `.catch(() => null)` + 显式处理 null

### 3. AP-001 组件修复（9 处静态 inline styles → Tailwind）
- sonner.tsx:27、VariantPicker.tsx:177、MobileFilterDrawer.tsx:202、OptionDropdownContent.tsx:31、Header.tsx:67、MobileMenu.tsx:142、PayPalPaymentForm.tsx:119、GiftCardList.tsx:146、CategoryBanner.tsx:25
- 逐个确认静态样式 → className；动态样式保留（规则允许）

### 4. GS-010 补齐（场景编号连续性）
- 新增 GS-010（如：Storefront 搜索/过滤组件知识同步场景）

### 5. prd verify 删除类任务豁免
- `prd verify` 增加 `--allow-missing-tests`：删除/重构类任务无新测试 AC 时允许通过（exit 0 提示）

### 6. nav:check 扩展（各层 CLAUDE 双检）
- nav:check 额外校验 backend/platform/storefront 的 AGENTS.md 中引用的 CLAUDE.md 存在

## 验证
- 反模式 warning：94 → 期望 <10（仅剩需人工决策的动态样式）
- harness 测试 10/10（新增 prd verify 豁免 + nav:check 扩展测试）
- eval-scenarios 15 场景 readiness 通过
- nav:check 通过
- storefront 构建/测试不破坏（改动组件样式需跑 pnpm build/test）
