# 分支策略规范化 — 方案

> 需求来源：用户希望规范化分支策略——本地/远程 `dev` 开发，`dev` 合并到 `main`，`main` 为生产部署分支。
> 本文件为**方案设计**（用户确认后实施）。

---

## 一、目标分支模型

```
本地 dev ──push──▶ 远程 dev ──(CI 验证)──▶ merge ──▶ main ──▶ 生产部署
  ▲ 日常开发          ▲ 集成分支                    ▲ 生产分支（Tag/Release 唯一来源）
```

| 分支 | 角色 | 谁开发 | 谁合并 | CI | 部署 |
|---|---|---|---|---|---|
| `dev` | 开发/集成分支 | AI/开发者日常在此开发 | — | ✅ 推入即跑 | ❌ 不部署 |
| `main` | 生产分支 | ❌ 不直接开发 | 仅接受 `dev` 合并 | ✅ | ✅ 生产部署 / Tag / Release |

## 二、现状与差距

| 现状 | 差距 |
|---|---|
| 发布模型文档：`scripts/release/README.md` 写"唯一长期分支 main" | 需改为 dev 开发 + main 生产模型 |
| `backend-ci.yml` 已监听 `[main, dev]` | ✅ 达标 |
| `ai-ci.yml`、`harness-full.yml`、`monorepo-contract.yml`、`platform-ci.yml`、`storefront-ci.yml` 只监听 `main` | ⚠️ 需改为 `[main, dev]`（dev 推入也要 CI 验证） |
| `AGENTS.md`：无分支策略章节 | 需新增 |
| `copilot-instructions.md`：无分支规则 | 需新增 |
| `docs/standards/README.md`：规范索引 | 需登记分支策略 |

## 三、规范化内容

### 3.1 文档更新

| 文件 | 变更 |
|---|---|
| `scripts/release/README.md` | 发布模型改为"dev 集成分支 + main 生产分支"：main 唯一 Tag/Release/部署来源；dev 为开发集成分支；组件固定目录不变 |
| `AGENTS.md` §0.2 附近新增"分支策略"小节 | 日常开发在 `dev`；提交/推送 `dev`；发布时 `dev → main`；gate 绑定当前分支（在哪个分支开 gate 就在哪个分支完成提交） |
| `.github/copilot-instructions.md` | 新增 **R9 分支策略**：开发/提交/推送在 `dev`；`main` 仅由 `dev` 合并更新；禁止直接向 `main` 推送开发提交 |
| `docs/standards/README.md` | 规范登记表新增"分支策略"条目 |

### 3.2 CI 调整（dev 推入也跑全量验证）

5 个 workflow 的触发分支从 `[main]` 改为 `[main, dev]`：
- `ai-ci.yml`、`harness-full.yml`、`monorepo-contract.yml`、`platform-ci.yml`、`storefront-ci.yml`

> 目的：`dev` 上的每次推送都跑 CI，确保合并到 `main` 前验证通过（防止坏代码进生产）。

### 3.3 harness 配套（可选增强）

- `gate:required` 保持现状（绑定分支即可）；可增加提示：建议在 `dev` 开发
- `doc-impact --base origin/main` 已是 main 基准（dev 合并到 main 时检查知识同步）✅ 无需改

## 四、日常操作流程（规范化后）

```bash
# 1. 开发（日常）
git checkout dev                        # 本地 dev
# ... 开发 + harness gate + 提交 ...
git push origin dev                     # 推远程 dev（触发 CI）

# 2. 发布（dev 验证通过后）
git checkout main
git merge dev                           # dev → main
git push origin main                    # 推 main（触发部署/打 Tag）
```

## 五、当前状态迁移（实施时）

当前本地在 `main`（66f88a71，已推远程）。切换策略时：
1. `git checkout -b dev`（本地 dev = 当前 main 66f88a71）
2. `git push origin dev`（已是最新，无需 force）
3. 之后日常开发在 dev；main 不再直接推送开发提交

## 六、风险与对策

| 风险 | 等级 | 对策 |
|---|---|---|
| 开发者仍直接向 main 推送 | 中 | CI workflow 不监听 dev 提交的组件会漏检 → 全部改 [main, dev]；文档强调 |
| dev 长期落后 main | 低 | 发布流程固定 merge dev→main 后，main 与 dev 同步 |
| gate 绑定分支混乱 | 低 | 规范"在哪个分支开 gate 就在哪个分支完成提交" |
| 本地当前在 main 误提交 | 中 | 实施时切到 dev，AGENTS.md/copilot-instructions 明确约束 |

## 七、实施清单（用户确认后执行）

| # | 动作 |
|---|---|
| 1 | `scripts/release/README.md` 发布模型改分支策略 |
| 2 | `AGENTS.md` 新增分支策略小节（§0.4） |
| 3 | `.github/copilot-instructions.md` 新增 R9 分支策略 |
| 4 | `docs/standards/README.md` 登记分支策略 |
| 5 | 5 个 workflow 触发分支改 `[main, dev]` |
| 6 | 本地切换：`git checkout -b dev` |
| 7 | 验证：CI 配置语法 + doc-impact + harness 测试 |

---

## 决策节点

1. **确认分支模型**：`dev` 开发/集成 + `main` 生产部署（Tag/Release 只打 main）——对吗？
2. **确认 CI 调整**：5 个 workflow 改为监听 `[main, dev]`（dev 推送也跑 CI）——同意吗？
3. **确认本地迁移**：实施时把本地切到 `dev` 分支（基于当前 main 创建）——同意吗？
