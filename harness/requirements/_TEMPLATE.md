# 需求文档模板

> 所有任务先做 Step 0（跨层搜索），再按任务类型填写并等待用户确认。

---

## Step 0：跨层搜索（所有任务强制执行 — 无例外）

| 层 | 搜索路径 | 搜索关键词(含同义词) | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | | | |
| App — views/decorators | `backend/app/` | | | |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | | | |
| Core Gem — services | `backend/pallastrade_gems/pallastrade_core/app/services/` | | | |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | | | |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | | | |
| Admin Gem — views | `backend/pallastrade_gems/pallastrade_admin/app/views/` | | | |
| Storefront | `storefront/src/` | | | |
| Platform | `platform/packages/` | | | |

### 搜索结论

<!-- 总结：哪些层已有能力？哪些层需要新建？若全部已有 → 任务完成，0 行新代码。 -->

---

## Step 1：Skill 文件咨询（新功能/功能优化 — 强制执行）

> 每格必须填真实"关键结论引用"；有未读项则需求文档无效，禁止进入编码。

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ⬜ 未读 | |
| `ai/skills/pallastrade-admin/SKILL.md` | ⬜ 未读 | |
| `ai/skills/pallastrade-catalog/SKILL.md` | ⬜ 未读 | |

**按需 Skill（勾选本次涉及并填写）：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | ⬜ | ⬜ | |
| `pallastrade-decorators` | ⬜ | ⬜ | |
| `pallastrade-dependencies` | ⬜ | ⬜ | |
| `pallastrade-events-webhooks` | ⬜ | ⬜ | |
| `pallastrade-storefront` | ⬜ | ⬜ | |
| `pallastrade-testing` | ⬜ | ⬜ | |
| `pallastrade-i18n` | ⬜ | ⬜ | |

---

## 需求标题

<!-- 一句话描述：做什么、给谁用 -->

## 任务类型

<!-- 新功能 / 功能优化 / Bug修复 / 样式调整 / 版本升级 -->

## 需求描述

<!-- 用自然语言描述需求，避免技术术语 -->

## 影响范围（harness affected 输出）

<!-- 贴入 harness affected --base origin/main 的输出 -->

## 技术方案（初步）

<!-- 根据决策树选择层级 + 理由 -->

## 风险点

<!-- 最高风险 + 回滚难度 -->

## 决策节点

> ⏸️ **请确认以上理解是否正确。确认后 AI 将进入阶段②输出详细方案文档。**

---

## 阶段③：实施后验证（不可跳过）

> ⚠️ **每项改动都必须有对应的最低验证。** "no test needed" 是极少数例外。

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| | | `pnpm build` / `pnpm lint` | | ⬜ |
| | | `harness check --profile quick` | | ⬜ |
| | | `harness generated:check` | | ⬜ |
| | | 其他：_____ | | ⬜ |
| | | 声明无需验证 → 原因：_____ | | ⬜ |

### 新增 admin 页面三要素检查（固定检查项，凡新增/改动 admin 页面必填）

> ⚠️ 2026-08-17 教训（stores 列表/新建页面包屑缺失、Switch 链接 data-method 空白页）：
> **功能正确 ≠ 页面完整**。每次新增/改动 admin 页面，除功能验证外，必须逐项核对以下三要素
> 并填写结果；同时检查目标控制器是否声明 `skip_breadcrumb_derivation = true`
> （若声明，新增 action 必须手写 `add_breadcrumb` + `add_breadcrumb_icon`）。

| 检查项 | 页面（路径） | 是否符合 | 备注 |
|---|---|---|---|
| ① 页面标题（page_title / 页面头 h3） | | ⬜ | |
| ② 面包屑（含图标；`skip_breadcrumb_derivation` 控制器需手写） | | ⬜ | |
| ③ 页面操作按钮（page_actions）与返回路径正常 | | ⬜ | |
| ④ POST/PATCH/DELETE 链接/按钮用 `data: { turbo_method: ... }`（Turbo 约定），**勿用 `method:`** | | ⬜ | |

### 验证结论

<!-- 例：pnpm lint 通过 ✅ / pnpm build 失败 ❌，原因：缺少闭合反引号，已修复 → 通过 ✅ -->


