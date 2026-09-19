# PRD-20260919-checkout-remove-shipping-change-placeholder-banner

| 元数据 | 值 |
|---|---|
| 状态 | approved |
| 创建日期 | 2026-09-19 |
| 来源 | 优化：checkout 页面 shipping method 区块常显「The shipping options have changed for your order. Review your selection.」——按现有交易链路，只有后端改了物流信息才该出现该提示 |
| 分类 | checkout |
| 关联 Skill | `pallastrade-storefront` / `pallastrade-checkout` |
| 关联 REQ | REQ-20260919-checkout-remove-shipping-change-placeholder-banner.md |
| 关联 PRD | 五条结账优化清单第 2 项（用户选定**方案 A：删除占位提示**） |
| 需求类型 | 优化迭代（纯前台结构 + 文案） |

> **用户决策（2026-09-19）**：第 2 项选**方案 A** —— 删除该常显占位提示，物流/运费变化统一由**顶部报价差异横幅**表达。用户原话：「实施：第2项：方案A」。

## 1. 背景与目标

- **背景**：`UnifiedCheckout` 第 3 节（Shipping method）内有一个**无条件渲染**的琥珀色提示框（`data-testid="shipping-options-changed"`），源码注释自述为「PRD 3.4：配送选项变化黄色警告框（**占位**，后端推送变更信号后驱动）」。全仓检索**不存在**任何 `shipping_options_changed` 类后端信号 —— 该提示从未被真实事件驱动，对每位顾客恒显，属噪音且误导（提示"已变化"但事实未变化）。
- **真实信号已存在**：服务端在报价漂移时返回 `quote_changed` / `checkout_version_conflict`，前端渲染顶部 `checkout-quote-diff` 横幅（含 `quote-diff-shipping` 行：运费 before → after）。这才是"后端改了物流信息"的正确表达面。
- **目标**：删除占位提示框；物流/运费变化只由顶部报价差异横幅表达。
- **成功指标**：结账页不再出现恒显的「shipping options changed」提示；`quote_changed` 场景下的差异横幅行为零回归。

## 2. 用户故事 / 场景

1. 作为**买家**，我不应在没有发生任何变化时被告知"配送选项已变化"。
2. 作为**买家（真实发生运费变化）**，我应在提交前从顶部横幅看到运费前后对比并重新确认（既有能力）。
3. **边界**：物流方式列表为空（`shippingMethods.length === 0`）→ 第 3 节整体不渲染（既有行为不变）。
4. **异常**：服务端未返回报价漂移 → 无任何"已变化"提示（这正是修复点）。

## 3. 功能需求（FR）

| # | 需求 |
|---|---|
| FR-001 | 删除第 3 节内无条件渲染的琥珀色提示框（`data-testid="shipping-options-changed"`） |
| FR-002 | 物流/运费变化的**唯一**呈现面 = 顶部 `checkout-quote-diff` 横幅（`quote_changed` / `checkout_version_conflict` 时出现，含 `quote-diff-shipping` 行；行为不变） |
| FR-003 | 清理不再使用的文案键 `checkout.shippingOptionsChanged`（五语言），避免死键 |
| FR-004 | 第 3 节的其余内容（步骤标题、物流方式单选列表、限制说明）保持不变 |

## 4. 验收标准（AC）

| # | 验收标准 | 覆盖 FR |
|---|---|---|
| AC-001 | 结账页渲染后**不存在** `shipping-options-changed` 元素，也不出现其文案 | FR-001 |
| AC-002 | 第 3 节标题与物流方式单选行仍正常渲染（回归） | FR-004 |
| AC-003 | 报价漂移场景仍渲染顶部 `checkout-quote-diff`（含 `quote-diff-shipping`），物流变化提示仅此一处 | FR-002 |
| AC-004 | 五语言不再包含 `shippingOptionsChanged` 键（键集一致性守护通过） | FR-003 |

## 5. 技术影响

| 区域 | 变更 |
|---|---|
| `storefront/src/components/checkout/UnifiedCheckout.tsx` | 删除占位提示块（约 10 行） |
| `storefront/messages/{en,de,es,fr,pl}.json` | 删除 `checkout.shippingOptionsChanged` |
| `storefront/src/components/checkout/__tests__/UnifiedCheckout.test.tsx` | 原「断言提示存在」改为「断言提示不存在 + 报价漂移横幅仍存在」 |
| 后端 / 契约 / SDK | **无变更** |

## 6. 测试计划（AC ↔ 测试映射）

| AC | 测试 |
|---|---|
| AC-001 / AC-002 | `UnifiedCheckout.test.tsx`（既有渲染用例 + 新增断言） |
| AC-003 | `UnifiedCheckout.test.tsx` 既有 `checkout-quote-diff` 用例（保持通过） |
| AC-004 | `storefront/src/lib/__tests__/checkout-i18n-keys.test.ts`（五语言键集一致性） |

**验证命令**：`npx harness verify storefront-test --task <TASK-ID>` + `pnpm -C storefront check` + `pnpm -C storefront typecheck` + `pnpm -C storefront check:locales`。

## 7. 非目标（Non-goals）

- 不新增后端「物流变更」信号（方案 C 已评估弃用：现有 `quote_changed` 已覆盖运费漂移）。
- 不做客户端对账（方案 B）：当前页面未保存上一次费率快照，收益有限且易与权威口径冲突。
- 不改右栏费用口径（属第 5 项）。

## 8. 风险

| 风险 | 处置 |
|---|---|
| 真实运费变化时缺少提示 | 顶部 `checkout-quote-diff` 横幅已覆盖（AC-003 回归守护） |
| 文案键被其它地方引用 | 全仓检索确认仅本处引用（PRD §5 记录） |

## 9. 知识同步清单

| 资产 | 动作 | 结论（2026-09-19） |
|---|---|---|
| `pallastrade-storefront Skill` | **更新** | Checkout 章节补充：第 3 节不再有常显变更提示；物流变化唯一呈现面 = 顶部 quote diff |
| `组件测试` | **更新** | `UnifiedCheckout.test.tsx` 断言反转 + 回归断言 |
| `场景库` / `scenarios.json` | **更新** | 新增 GS-190 |
| `pallastrade-prd Skill` / `AGENTS.md` / `copilot-instructions.md` | 已评估，无需更新 | 流程与规则未变 |

## 10. 变更日志

| 日期 | 变更 |
|---|---|
| 2026-09-19 | 初稿（approved）：用户选定方案 A；实现 + 验证中 |
