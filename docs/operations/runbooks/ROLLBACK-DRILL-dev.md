# dev 回滚手册（Rollback Runbook）与演练记录

> 适用环境：PallasTrade dev 单栈（`dev.pallastrade.cn`，服务器 `115.29.185.128`，代码 `/opt/pallastrade/repo`）
> 权威部署机制见 `deploy/README.md`；本手册只覆盖**回滚/回退**路径与演练证据。
> 建立日期：2026-09-13（首次真实演练，见 §4）

---

## 1. 回滚能力现状（实测结论）

| 组件 | 有无历史工件 | 回滚方式 | 回滚耗时量级 |
|---|---|---|---|
| **Backend（web/worker）** | ❌ 无（`pallastrade-dev-web/worker:latest` 为移动 tag，服务器本地构建） | **切源码版本 + 服务器重建** | 实测见 §4 |
| **Storefront** | ❌ 无（`ghcr.io/…/pallastrade-storefront:dev` 为**移动 tag**，CI 每次覆盖） | **无快速回滚路径**：需重新构建旧版本镜像并 `docker save/scp/load` | 30 分钟+（本地构建 + 传输） |
| **数据库** | ✅ 有（PostgreSQL 数据卷常驻） | **不参与回滚**：schema 只前进。回滚代码时若旧代码不认识新列/新表 → 需评估 | — |
| **nginx 配置** | ✅ 仓库版本化 | 随 `git reset` + `sync-and-smoke.sh` 自动同步 | 秒级 |
| **CI 镜像** | ❌ 未保留历史 tag | 见 §5 改进建议 | — |

> ⚠️ **关键缺口**：当前流水线**不保留任何历史版本工件**，因此「回滚」实质是「按旧 commit 重新构建并部署」，属于**分钟到小时级**操作，不具备秒级回退能力。

---

## 2. 回滚 SOP（标准步骤）

> 服务器上**必须**先禁用 cron，否则 `pull-deploy.sh`（每 5 分钟）会在窗口内自动前滚，回滚态无法保持。

```bash
# 0) 前置：磁盘 ≥ 8GB（重建需要空间）；不足先 `docker builder prune -f`
df -h /

# 1) 禁用 cron（备份后注释掉 pull-deploy 行）
crontab -l > /root/crontab-pre-rollback.bak
sed -i 's|^\([^#].*pull-deploy\)|#ROLLBACK# \1|' /root/crontab-pre-rollback.bak
crontab /root/crontab-pre-rollback.bak

# 2) 回退代码并重建
cd /opt/pallastrade/repo
git fetch origin dev
git checkout -f <ROLLBACK_SHA>          # 任意历史 commit
bash deploy/deploy.sh dev               # 重建 web/worker + up + 健康检查

# 3) 回退态验证（至少三项）
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3102/up     # 期望 200
curl -s -o /dev/null -w '%{http_code}\n' https://dev.pallastrade.cn/up # 期望 200/307
docker exec pallastrade-dev-web-1 bash -lc 'ls /rails/pallastrade_gems/pallastrade_core/app/services/pallastrade/disputes'

# 4) 前滚（恢复标准态）
crontab /root/crontab-pre-rollback.bak  # 恢复 cron
git checkout -f dev && git reset --hard origin/dev
bash deploy/pull-deploy.sh dev          # 拉镜像 + 重建 + nginx smoke + 记录 state

# 5) 前滚态验证
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3102/up
sed -n 1p /opt/pallastrade/.pull-deploy-state-dev   # 应等于 origin/dev HEAD
```

### 2.1 自动化脚本（推荐）

`deploy/drill-rollback-dev.sh` 把上述步骤做成**自恢复**脚本：

```bash
bash deploy/drill-rollback-dev.sh <ROLLBACK_SHA>            # 真实演练
bash deploy/drill-rollback-dev.sh <ROLLBACK_SHA> --dry-run  # 只做前置检查，不改动任何状态
```

安全设计：
- `EXIT trap` 无论成功/失败都执行「恢复 crontab → 前滚到 `origin/dev` → 跑 pull-deploy」；
- 日志 `/var/log/pallastrade-drill-rollback.log`，证据 `/tmp/drill-<secs>/evidence.txt`；
- 磁盘 < 8GB 直接拒绝执行（防 2026-08-31 式磁盘满级联故障）；
- 退出码：`0` 完成且已前滚 / `2` 前置不满足未开始 / `1` 中途异常（trap 已前滚）。

---

## 3. 风险与注意事项

| 风险 | 说明 | 缓解 |
|---|---|---|
| **cron 抢跑** | 不禁用 cron 时，回滚态最多保持 5 分钟 | 必须先备份/禁用 crontab |
| **DB schema 只前进** | 回滚到旧代码时，DB 仍含新列/新表 | 演练选择「无迁移破坏」的相邻版本；破坏性回滚需先评估 |
| **磁盘水位** | 重建会新增镜像层；82% 水位下曾引发 pull 挂起 + flock 泄漏 | 脚本内置 8GB 门禁 + `builder prune` |
| **并发部署** | 手工回滚与 cron 部署同时进行会互相覆盖 | flock（`/tmp/pull-deploy-dev.lock`）已有；仍应禁用 cron |
| **storefront 无法回滚** | 移动 tag 覆盖历史镜像 | 见 §5 改进建议 |

---

## 4. 首次演练记录（2026-09-13）

| 项 | 值 |
|---|---|
| 任务 / 门禁 | `TASK-20260913092622-cdcb70d5` / `GATE-2026-09-13T09-26-31`（测试） |
| 演练脚本 | `deploy/drill-rollback-dev.sh`（本次随演练建立） |
| 回滚目标 | `d3c1db36`（P7-8 收口，pre-P7-9） |
| 起始版本 | `fc4d3324` |
| 前置 | 磁盘 prune 后 14164MB；`backend/up=200`、`public/up=307` |
| 结果 | 见下表（由脚本自动写入 `/tmp/drill-<secs>/evidence.txt`） |

<!-- DRILL-RESULTS -->

### 4.1 结果（实测数据）

| 阶段 | 结果 | 证据 |
|---|---|---|
| 基线 | `backend/up=200`、`public/up=307`、`web_image=sha256:0dcf51d9cb40` | 日志 17:28:10 |
| **回退**（切 `d3c1db36` + `deploy.sh`） | ✅ 成功，**耗时 297s（≈5 分钟）** | `回退部署耗时: 297s` |
| 回退态验证 | ✅ `backend/up=200`、`public/up=307`、`web_image=sha256:bfe3363a9b62`（新镜像） | 日志 17:33:27 |
| **回退生效判据** | ✅ `disputes/` 目录**不含** `capture_fee.rb`（P7-9 工件随版本消失），共 13 个文件均为 pre-P7-9 版本 | 容器内 `ls /rails/…/services/pallastrade/disputes` |
| **前滚**（`pull-deploy.sh dev`） | ❌ **未生效**：输出「✅ 无变化（head=fc4d3324 img=sha256:1b681），跳过部署」，耗时 9s | 日志 17:33:31 |
| 前滚态验证（失败态） | ⚠️ `web_image=sha256:bfe3363a9b62`（**仍是回退镜像**）、`disputes/` 仍无 `capture_fee.rb` | 日志 17:33:36 |
| **前滚（现场处置：删 state 强制重部署）** | ✅ **成功**，耗时与回退同量级（≈5 分钟） | 人工执行；容器 `pallastrade-dev-web-1` 于 ~17:42 重建完成 |
| **最终态验证** | ✅ `state=fc4d3324`、repo HEAD=`fc4d3324`、`web_image=sha256:f0f0949abc78`、`disputes/` 含 `capture_fee.rb`（P7-9 回归）、`backend/up=200`、容器 healthy | 17:43:24 实测 |

### 4.2 🔴 演练结论 1：**手工回退后无法自动前滚（流水线缺陷）**

**根因**：`pull-deploy.sh` 的变化检测**只比较 state 文件记录的 (head, storefront 镜像 digest)**：

```bash
if [ "$NEW_HEAD" = "$OLD_HEAD" ] && [ "$NEW_IMG_ID" = "$OLD_IMG_ID" ]; then
  echo "✅ 无变化…，跳过部署"; exit 0
fi
```

手工回退只改动**工作区源码**，不会改写 state 文件 → `NEW_HEAD == OLD_HEAD` → 判定"无变化" → **跳过部署**。
**后果：一旦手工回退，cron 每 5 分钟都会跳过，dev 会无限期停留在旧版本，且 state 文件仍显示最新版本（监控假绿）。**

**现场处置（本次已实测验证）**：删除 state 文件强制重新检测：

```bash
cd /opt/pallastrade/repo
git checkout -f dev && git reset --hard origin/dev
rm -f /opt/pallastrade/.pull-deploy-state-dev   # ← 关键：否则 pull-deploy 仍会跳过
bash deploy/pull-deploy.sh dev                  # 触发重建 + 重新记录 state
```

实测结果：执行后 web 镜像由 `sha256:bfe3363a9b62`（回退版）重建为 `sha256:f0f0949abc78`，`capture_fee.rb` 回归，`backend/up=200`、容器 healthy。

**演练脚本已内置该修复**：`deploy/drill-rollback-dev.sh` 在前滚前会自动 `rm -f $STATE`（v2026-09-13 起）。

**根治建议**（见 §5 第 1 条）：`pull-deploy.sh` 的变化检测应增加**实际运行镜像 vs 期望镜像**的比对，而非只信 state 文件。

### 4.3 🟡 演练结论 2：回退耗时基线 = **297s（≈5 分钟）**

后端重建 5 分钟即完成（构建缓存命中）。这是**当前架构下最快的回滚时间**；storefront 若也需回退，需额外「本地构建镜像 + save/scp/load」，量级为 30 分钟+（本次未实测，因回退目标与当前 storefront 代码一致）。

### 4.4 演练中暴露的操作注意事项

| 现象 | 说明 |
|---|---|
| cron 并发抢跑 | 首次 dry-run 恰逢 cron 部署窗口，出现 `backend/up=000`、`public/up=502`（容器重建中）。**演练必须禁用 cron**（脚本已内置） |
| `deploy.sh` 输出被 `tail` 缓冲 | 日志中 `deploy.sh` 输出直到结束才落盘，无法实时观察进度 → 建议加 `stdbuf -oL` 或用 `tee` 直通 |
| `couldn't find env file: /opt/pallastrade/repo/.env.dev` | 演练脚本在 `$REPO` 之外的 cwd 调用了 compose ps；**无害**（仅状态展示），但应修正 cwd |

---

## 5. 改进建议（演练暴露的缺口）

| # | 建议 | 收益 | 优先级 |
|---|---|---|---|
| 1 | `pull-deploy.sh` 变化检测增加**「实际运行镜像 vs 期望镜像」**校验（对比 `docker inspect` 当前 web/storefront 容器镜像 ID 与 state 记录值），不一致即重部署 | 修复 §4.2 的**假绿/无限期停留旧版本**缺陷；让手工回退可被 cron 自动发现并前滚 | 🔴 P0 |
| 2 | CI 推送 storefront 镜像时**同时打不可变 tag**（`dev-<sha>`），并保留最近 N 个 | storefront 具备可回滚的确定目标 | 🔴 P0 |
| 3 | backend 镜像增加不可变 tag（`pallastrade-dev-web:<sha>`）并保留最近 N 个 | backend 回滚从 297s 降到 `docker tag` + `up -d`（秒级） | 🟡 P1 |
| 4 | `pull-deploy.sh` 记录 state 时**同时写入上一个可回滚的 (head, digest)** 并保留镜像 | 支持「回滚到上一个成功部署」一条命令 | 🟡 P1 |
| 5 | `drill-rollback-dev.sh` 纳入定期演练（每季度），并把耗时写入本手册 §4.1 | 保持回滚路径可用、耗时数据可跟踪 | 🟢 P2 |
