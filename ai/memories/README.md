# AI Repository Memory (Synced)

> 仓库级 AI 记忆快照——随仓库跨设备同步。

## 这是什么

这是 VS Code Copilot memory-tool 的 **repo 作用域记忆**（`/memories/repo/`）的仓库同步副本。
记忆系统本身存储在设备本地（`workspaceStorage/.../memory-tool/memories/repo/`），**不会自动跨设备同步**。
本目录把它们纳入 Git 版本管理，换设备时可以从这里恢复。

## 文件说明

| 文件 | 内容 |
|---|---|
| `harness-l3-results.md` | Harness L3 工程建设结果（CI 修复、lefthook 门禁、gate 加固、eval/freshness） |
| `harness-upgrade-decision.md` | 升级机制决策（删除审计层 / 保留执行层） |
| `m3-stripe-results.md` | Stripe 支付矩阵测试结果 |
| `m4-branding-results.md` | 外部品牌化结果 |

## 换设备时如何恢复

在新设备克隆仓库后，把本目录内容复制回记忆系统的 repo 作用域：

```powershell
# 新设备上的记忆路径（workspaceStorage 哈希随工作区而定，先创建目录）
$dest = "$env:APPDATA\Code\User\workspaceStorage\<your-workspace-hash>\GitHub.copilot-chat\memory-tool\memories\repo"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "ai\memories\*.md" -Destination $dest -Force
```

> 注意：`<your-workspace-hash>` 是 VS Code 为当前工作区生成的目录名（可在
> `%APPDATA%\Code\User\workspaceStorage\` 下按项目路径识别）。
> 恢复后新设备上的 Copilot 会话即可直接引用这些记忆。

## 维护规则

- 每次有新的 repo 记忆写入后，**同步更新本目录并提交**，保持与 `/memories/repo/` 一致。
- 记忆系统里删除的条目，也应在本目录删除。
