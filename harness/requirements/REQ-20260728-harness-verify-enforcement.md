# REQ-20260728-harness-verify-enforcement

## Step 0：跨层搜索

| 层 | 关键词 | 发现 |
|---|---|---|
| `harness/policies/` | task-rules.json, anti-patterns.json | TR-001~005 已定义，缺少验证证据规则 |
| `scripts/harness/cli.mjs` | verify-test, gate:clear | verify-test 描述模糊，无强制证据要求 |
| `AGENTS.md` §6 | Minimum Verification | 列出了检查类型但未要求浏览器验证 |
| `.github/copilot-instructions.md` | R6, verify | "run tests OR document no-test-needed" — 过于宽松 |

## Step 1：Skill 咨询

| Skill | 关键结论 |
|---|---|
| `pallastrade-customization` | 本次改动属于 Harness 配置层 |

---

## 需求标题
Harness：verify-test 强制浏览器验证 + user-confirmed 不可自清

## 任务类型
功能优化 (feature)

## 需求描述

复盘发现连续 3 次任务在 verify-test 阶段**未实际验证**就清检查。根因是机制本身缺少强制力：
- verify-test 的描述"run tests OR document no-test-needed"给了太多回旋余地
- user-confirmed 可以被 AI 自行清除（无二次确认）
- 没有"修复生效证据"的硬性要求

## 改动范围（4 文件）

| 文件 | 改动 | 目的 |
|---|---|---|
| `AGENTS.md` §6 | 新增 Verification Evidence 要求 | 每种变更类型对应必须提供的证据形式 |
| `.github/copilot-instructions.md` | R6 强化 + 新增 R7 | 明确 verify-test 不能仅靠"document no-test-needed"跳过 |
| `harness/policies/task-rules.json` | 新增 TR-006 | 验证证据规则 |
| `scripts/harness/cli.mjs` | verify-test 描述更新 | 引用 TR-006，提示必须提供证据 |

## 具体改动

### AGENTS.md §6（在表后追加）
```markdown
### Verification Evidence Required

| What you changed | Minimum evidence |
|---|---|
| UI (view/component/style) | Screenshot or DOM snapshot showing corrected state |
| Backend logic | Rails log line showing success (200/302) |
| Data fix | DB query result before/after |

**"no test needed" is NOT a valid resolution for UI or backend logic changes.**
```

### copilot-instructions.md（R6 末尾 + 新增 R7）
```markdown
### R6: Verify or Declare — NO SKIPPING (强化)

...existing content...

**Clearing `verify-test` without browser verification for UI changes, or without
log/DB verification for backend changes, is a process violation.**

### R7: user-confirmed Requires Explicit User Action

The `user-confirmed` gate check MUST NOT be cleared by the AI. It may only be
cleared after the user explicitly confirms (e.g., "确认", "实施", "go ahead").
```
```

### task-rules.json
```json
{
  "id": "TR-006",
  "name": "verification-evidence-required",
  "appliesTo": ["所有任务"],
  "description": "verify-test 清空前必须提供修复生效的客观证据。UI 变更须截图/DOM快照，后端变更须日志/DB查询结果，纯配置变更须重启后验证。不允许仅凭逻辑推理声明'no test needed'。"
}
```

## 风险点
- 某些纯文本/配置变更确实不需要浏览器验证 → 保留"document no-test-needed"但要求更具体的原因说明
