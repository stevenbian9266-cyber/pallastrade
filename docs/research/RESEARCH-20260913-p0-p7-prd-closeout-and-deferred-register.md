# RESEARCH-20260913 · P0–P7 PRD 状态收口报告与挂起项备案

| 元数据 | 值 |
|---|---|
| 日期 | 2026-09-13 |
| 类型 | 治理收口（docs） |
| 任务 | `TASK-20260913085722-ae3f1a01` · Gate `GATE-2026-09-13T08-57-36`（docs） |
| 输入 | `docs/research/RESEARCH-20260913-p0-p7-implementation-audit.md` §5 建议行动（第 1–4 项）+ §6 未覆盖项 |
| REQ | `harness/requirements/REQ-20260913-p0-p7-prd-closeout.md` |
| 复检结果 | 索引 **117** 行 ↔ 文件 **117** 份，**漂移 0**、未进索引 **0** |

---

## 1. 收口判据（本报告使用的唯一口径）

| 等级 | 判据 | 处置 |
|---|---|---|
| **L1 有闭环门禁** | `harness/gates/GATE-*.json` 中存在 `taskId` 匹配且 `phase == "finished"` 的门禁 | 状态置 `done`（索引 + 文件同时改） |
| **L2 追溯收口** | 无 finished 门禁，但**代码工件 + spec 齐备**且有下游依赖/后续门禁覆盖 | 状态置 `done`，并在本报告 §3 显式标注「历史门禁未闭环」 |
| **L3 未实施** | 既无门禁也无工件 | 保持 `approved`/`draft`，登记进 §5 挂起项 |
| **L4 名实不符** | 文件名与正文标题/主题不一致 | 修正文件名或正文；重复件标 `merged` |

> L1 可机器复核（`taskId` + `phase`），L2 属**人工判定**，已在 §3 逐项列出依据，接受审计挑战。

---

## 2. 收口判定表（L1，共 34 项）

| # | PRD | 收口前 索引/文件 | 收口后 | 闭环门禁（TASK / GATE 描述） |
|---|---|---|---|---|
| 1–11 | **TXN-P2-1 … P2-7 + 收口报告 + SDK + 轮3 + 组合交易 txn 化**（11 份） | approved / approved | done | `db01ee07` · `8ab4f216` · `1e95254d` · `32f3a2bd` · `28551e48` · `83e1abea` · `e6314687` · `8f662c06` · `eb2c2df2` · `889b7274` · `0f492f00` · `9eaa63f6` |
| 12 | PRD-20260905-shipping-库存事务集成与预留生命周期（P3） | draft / done | done | `942c63c2`「优化：库存事务集成与预留生命周期（P3）」 |
| 13 | PRD-20260906-admin-core-p5-8-operational-hardening | approved / approved | done | `0c5b8f03` |
| 14 | PRD-20260829-checkout-订单流程标准电商改造 | approved / approved | done | `a104cb71` |
| 15 | PRD-20260829-checkout-订单模块（单笔/多笔） | approved / approved | done | `2d7e8025` |
| 16 | PRD-20260830-checkout-下单链路规范化统一化 | approved / approved | done | `5f6397c0` |
| 17 | PRD-20260829-payments-Stripe→Checkout Sessions 迁移 | approved / approved | done | `15a7d705` |
| 18 | PRD-20260831-payments-stripe-自绘卡支付表单（PaymentIntent 模式） | implementing / done | done | `8c112760`（同任务含收尾 gate） |
| 19 | PRD-20260826-checkout-实施-p2-统一拆单引擎 | done / verifying | done | `073eb279` |
| 20 | PRD-20260828-checkout-p7-逆向链路售后父子单化 | done / draft | done | `72f726ec` |
| 21 | PRD-20260828-checkout-p8-前置校验/库存/风控 | done / draft | done | `00695a0d` |
| 22 | PRD-20260828-admin-p6-admin-手动拆单-父子树 | done / draft | done | `527009aa` |
| 23 | PRD-20260816-admin-管理后台导航一致性 | done / draft | done | `1e7c90f2` |
| 24 | PRD-20260816-admin-管理后台导航架构统一重构 | approved / approved | done | `d4fa3758` |
| 25 | PRD-20260817-admin-多店铺管理-店铺列表-新建-切换 | draft / approved | done | `114434b5`「优化：多店铺管理-店铺列表-新建-切换」 |
| 26 | PRD-20260817-admin-新建店铺表单-货币语言选择器与邮箱预设 | approved / done | done | `06c27720` · `7c836c69` |
| 27 | PRD-20260817-admin-菜单配置收敛 | draft / approved | done | `c47eb99a` |
| 28 | PRD-20260816-admin-后台可视化菜单配置模块 | reviewing / approved | done | REQ-20260816-admin-menu-config-role-permissions（finished） |
| 29 | PRD-20260813-admin-移除管理后台-integrations-菜单 | draft / draft | done | `02e5072d` |
| 30 | PRD-20260818-catalog-p0-4-产品评论 | draft / approved | done | `33d9e6b9`「需求：P0-4 产品评论」 |
| 31 | PRD-20260818-other-p0-3-邮件自动化-弃单恢复 | draft / draft | done | `a9c9242e` |
| 32 | PRD-20260809-storefront-brand-assets | reviewing / done | done | 品牌资产套件（`pallastrade-brand-assets/`）已交付 |
| 33 | PRD-20260909-payments-孤儿退款补记 backfill | done / draft | done | `ba160044`（REV-P6-8m） |
| 34 | PRD-20260810-storefront-重新规划 / tawk.to 接入 | done / draft · done / draft | done | 均存在 `phase=finished` 门禁（「对商城前台进行重新规划（全面重构+SEO/GEO）」「商城前台接入 tawk.to 作为客服工具」） |

---

## 3. 追溯收口项（L2，**历史门禁未闭环** —— 请审阅）

以下 6 项**没有** finished 门禁，凭代码工件 + 测试工件 + 下游依赖判定为已实现。**这是本报告中最需人工复核的部分**：

| PRD | 原状态 | 依据（可复核） | 门禁缺口 |
|---|---|---|---|
| PRD-20260902-payments-payment-p0-foundation-hardening | approved | `pallastrade_core/app/models/pallastrade/payment_webhook_event.rb`、`.../services/pallastrade/payments/webhook_event_store.rb` 齐备 | REQ 未登记 taskId |
| PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting | approved | `.../services/pallastrade/financial_ledger/post_refund.rb` + 账本 spec 套件齐备；由 FIN-P4-3（`ba840006` finished）覆盖 | REQ 无 taskId |
| PRD-20260826-payments-实施-p1-数据模型与语义方法（父子单） | verifying | `.../models/pallastrade/payment_combination.rb`（parent_id / PaymentSplit）齐备；下游 P2–P8 全部 finished | REQ 无 taskId |
| PRD-20260903-checkout-chk-p1-1（Application Layer） | draft | `.../services/pallastrade/order_checkout/` **10 个服务** + `spec/services/pallastrade/order_checkout/` 5 份 | `TASK-20260903110446-5a7993ae` 门禁停在 `implementation`（`cleared=False`） |
| PRD-20260903-checkout-chk-p1-1a（Read-only CheckoutView） | implementing | 同上（`view.rb` 只读投影） | 同上；且 CHK-P1-1B/2/3/4/4B/4C/4C4 共 **9 个任务**门禁全部未闭环 |
| PRD-20260904-r1-contract-generation-infra | done（索引）/ 无状态行 | `harness.config.mjs → generatedCheck.checks` 已指向 `scripts/ci/contracts.sh`（存在），不再是 `echo SKIP` 空转 | `TASK-20260904023203-21329797` 停在 `implementation` |

**建议**：这 6 项已在本次以回归证据（当日全量 `backend-rspec` 1661 examples / 0 failures）背书；若要求每个 PRD 独立门禁，请安排一次「补门禁」批次（见 §5 第 6 条）。

---

## 4. 数据质量修复（本次附带完成）

| 类别 | 发现 | 处置 |
|---|---|---|
| **名实互换** | `…chk-p1-1-order-checkout-application-layer-checkoutview.md` 与 `…chk-p1-1a-read-only-checkoutview.md` **两文件内容互换** | `git mv` 对调（内容各归其名） |
| **名实不符** | `…admin-管理后台新增安全配置管理模块-oss-key-secret-值托管.md` 正文实为「统一配置中心（⛔废弃）」 | `git mv` 恢复为 `…管理后台统一配置中心-集中管理关键参数与-secret-env-从模块取数.md`（与索引行一致） |
| **重复 PRD** | `other/PRD-20260828-other-p7-逆向链路售后父子单化` 与 `checkout/PRD-20260828-checkout-p7-…` 同需求双份 | `other/` 侧置 `merged`（历史副本）；`checkout/` 侧标题修正为自身名 |
| **骨架残留** | 11 份 PRD 存在**重复 H1 + 重复元数据块**（`prd new` 骨架未替换，直接追加正文） | 本次未改；见 §5 第 7 条（建议机器归一化） |
| **缺失索引** | 5 份 PRD 未进 `docs/prd/README.md` | 补齐 3 行（sdk-consumption / infra 部署脚本固化 / other-p7），另 2 行由改名与去后缀消除 |
| **索引名后缀** | 索引行 `…checkoutview（1B/2/3/4/4B/4C/4C4/5 实施收口）` 与文件名不符 | 索引行去掉后缀，与文件对齐 |

---

## 5. 挂起项备案（正式登记，解除条件明确）

| # | 挂起项 | 现状 | 解除条件 | 归属 |
|---|---|---|---|---|
| 1 | **Adyen / PayPal 适配** | 未开始 | 用户提供 sandbox 凭据 | payments |
| 2 | **规格 §68「高级争议能力」剩余边界** | 仅落地边界 C（partial / 多争议 / 能力矩阵 / 手续费） | 用户定义剩余范围（自动抗辩 / AI 生成证据 / 自动退款 / 自动补货，源计划 §71） | payments |
| 3 | **P5-8 Legacy 路径使用计数「量化报告」** | 埋点已实现（`0c5b8f03` finished），未跑出数据 | dev 运行一段时间后导出计数 | admin |
| 4 | **安全配置管理模块（OSS key/secret 值托管）PRD 正文缺失** | 仅有「草案」门禁记录，`docs/prd/` 无正文 | 补写 PRD 正文，或正式标废弃 | security |
| 5 | **R1 契约生成在 Windows 本地不可跑** | `contracts.sh` 需 docker+linux；本地 `generated:check` 走 SKIP | 在 CI / linux 环境执行；或在宿主补 Windows 分支 | api/infra |
| 6 | **CHK-P1-1 系列 9 个任务门禁未闭环** | 门禁停在 `implementation`（历史债务） | 安排补门禁批次，或接受 §3 的追溯收口口径 | checkout |
| 7 | **11 份 PRD 重复骨架头部** | 结构冗余，首行状态与正文块状态可能各说各话 | 在「PRD 状态一致性检查器」中加归一化动作 | harness |
| 8 | **多店铺切换 UI 已隐藏**（`b1b24d4c`：隐藏多店铺切换下拉与 Stores 导航项，渲染层保留代码与路由） | 与「多店铺管理」PRD 的验收口径存在解释空间 | 明确该功能的产品定位（保留/移除） | admin |
| 9 | **dev-only 单环境：无生产 SLA / 无回滚演练** | 仅证明 dev 可运行 + CI 绿 | 见 Task C（dev 真实回滚演练） | infra |
| 10 | **逐条 AC 复算未做** | 审计 §8 已声明；本报告沿用 | 需要时按 PRD 逐条复算 | 全体 |

---

## 6. 防复发机制（用户已确认，独立任务）

| 项 | 内容 |
|---|---|
| 现状缺口 | `.github/workflows/` 中 **0 处** prd 相关检查；`harness` 引擎虽有 13 个模块读取 `docs/prd`，但**没有状态一致性校验** |
| 拟新增 | `harness prd status:check`（或 `scripts/ci/prd-status-sync.mjs`）：比对 `README.md` 索引 ↔ PRD 文件头状态；`--fix` 自动同步；CI / lefthook 漂移即失败 |
| 关联收益 | 同时可检测 §4「骨架残留」「名实不符」，并输出机器可读的收口清单 |
| 任务 | 独立任务（用户选择「机制另开一条优化任务」） |

---

## 7. 复检证据（本次收口后实测）

```
索引=117 文件=117
漂移计数=0
未进索引=0
文件状态分布: done=114 merged=2 obsolete=1
```

| 复检脚本口径 | 说明 |
|---|---|
| 索引解析 | `docs/prd/README.md` 中 7 列行（状态 / PRD / 分类 / 日期 / REQ），`⛔废弃` 归一为 `obsolete` |
| 文件解析 | PRD 文件首个 `^\| 状态 \|` 行的 ASCII 状态词 |
| 漂移定义 | 两侧归一后不相等 |

---

## 8. 未覆盖（**不要过度解读**）

1. **未**逐条复算每个 PRD 的 AC 与测试映射（`harness prd verify` 对多数 PRD 无 AC 标注，输出「未找到 AC 标注」）。
2. **未**验证 §2 中每项功能在 dev 上的**运行时**行为（L1 项由门禁的 typed evidence 背书，属历史证据，本次未重跑）。
3. **未**清理 11 份重复骨架头部（仅登记）。
4. **未**处理 §5 中除「回滚演练」外的挂起项内容本身。
5. **未**变更任何代码、迁移、API 契约。

---

## 9. 证据索引

| 证据 | 位置 / 值 |
|---|---|
| 门禁记录 | `harness/gates/`（389 份；341 份带 `taskId`，297 个唯一任务） |
| REQ 记录 | `harness/requirements/`（159 份） |
| 本次任务/门禁 | `TASK-20260913085722-ae3f1a01` · `GATE-2026-09-13T08-57-36` |
| 当日后端全量回归 | `EVD-20260913071415-e7c36f0977`（1661 examples / 0 failures / 6 pending；Line 75.7% / Branch 42.53%） |
| 本报告变更面 | `docs/prd/README.md` + 42 份 PRD 文件（其中 2 组改名、1 份重复件标 merged）+ 本文件 |

---

## 10. 结论

- P0–P7 的 **PRD 状态首次实现机器可复核的自洽**：117 行索引 ↔ 117 份文件，漂移 0。
- 审计 §5 建议行动第 1–4 项（P2 全线收口、P3 归位、状态漂移、旁线收口）**已完成**；第 5 项（单环境/回滚）转 Task C；第 6 项（机制）转 Task B。
- **仍有 6 项属追溯收口**（§3）与 **10 项挂起**（§5），已全部显式登记，不再以「漂移」形式隐性存在。
