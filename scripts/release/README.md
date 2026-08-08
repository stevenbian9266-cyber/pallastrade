# PallasTrade 单仓库与发布模型

## 仓库结构

唯一正式仓库为 `github.com/stevenbian9266-cyber/pallastrade`。分支策略：`dev`
为开发/集成分支（日常开发 + CI 验证），`main` 为生产部署分支（唯一
Tag/Release/部署来源，仅接受 `dev` 合并）。四个组件固定在以下目录：

```text
pallastrade/
├── backend/
├── platform/
├── storefront/
└── ai/
```

仓库根目录是唯一 Git 工作树。组件目录不得包含独立的 `.git` 文件或目录，也不得
作为独立发布分支维护。脚手架只克隆一次 `main`，然后从上述固定目录复制所需组件。

根目录 `.github/workflows/` 中的工作流使用路径过滤触发对应组件任务。涉及多个组件
的变更可以并行触发多个任务。

## 分支策略

| 分支 | 角色 | 说明 |
|---|---|---|
| `dev` | 开发/集成 | 日常开发在此分支；推入即触发 CI（所有组件 workflow 监听 `[main, dev]`）；不部署 |
| `main` | 生产部署 | 仅接受 `dev` 合并；Tag/Release/部署的唯一来源 |

日常流程：

```bash
git checkout dev        # 开发（本地 + 远程）
git push origin dev     # 推 dev（触发 CI 验证）
git checkout main       # 发布
git merge dev           # dev → main
git push origin main    # 推 main（部署/打 Tag）
```

禁止：直接向 `main` 推送开发提交（`main` 只由 `dev` 合并更新）。

## Tag 规则

统一 Tag 格式：

```text
pallastrade-v1.0.0-rc.1
pallastrade-v1.0.0
pallastrade-v1.0.1
```

Tag 必须满足 `pallastrade-vMAJOR.MINOR.PATCH` 或
`pallastrade-vMAJOR.MINOR.PATCH-rc.NUMBER`，并创建在 `main` 的根仓库提交上。
一个 Tag 同时绑定四个组件。禁止移动、覆盖或重复创建已有 Tag。

本地创建命令：

```bash
node scripts/release/create-tag.mjs --tag pallastrade-v1.0.0-rc.1
git push origin pallastrade-v1.0.0-rc.1
```

`create-tag.mjs` 会检查当前分支、工作树、固定目录、嵌套 Git 元数据和已有 Tag，
并只创建带说明的 Tag。远端还必须在 GitHub 仓库设置中启用匹配
`pallastrade-v*` 的 Tag 规则，禁止更新和删除，并限制创建权限。

## Release manifest

Tag 推送后，发布工作流对四个组件执行验证，并生成不可覆盖的 release manifest。
manifest 是发布资产，不提交回被它描述的 Commit，从而避免 Commit 自引用问题。

manifest 记录：

- Tag 和根 Commit；
- 四个固定目录的 Git tree ID 与确定性 SHA-256；
- 从该 Commit 读取的 Gem/npm 包名、版本和路径；
- 四个组件的测试命令、结果和 CI 证据地址。

手工生成与验证：

```bash
node scripts/release/manifest.mjs create \
  --tag pallastrade-v1.0.0-rc.1 \
  --evidence path/to/evidence.json \
  --output path/to/pallastrade-v1.0.0-rc.1.manifest.json

node scripts/release/manifest.mjs verify \
  --manifest path/to/pallastrade-v1.0.0-rc.1.manifest.json
```

实际 manifest 由根目录 `.github/workflows/release-manifest.yml` 生成并附加到对应
GitHub Release。若同名发布资产已经存在，工作流会失败，不会覆盖。

## 首次远端切换

本地目录和 Git 元数据完成合并后，首次正式提交按以下顺序执行：

1. 审查并提交根工作树中的四个组件和根级治理文件；
2. `git push -u origin main`；
3. 在 GitHub 将默认分支设为 `main`；
4. 确认没有依赖后删除其他长期远端分支；
5. 为 `main` 配置禁止强推的分支规则；
6. 为 `pallastrade-v*` 配置禁止更新和删除的 Tag 规则。

完成首次单仓库提交前不要创建正式 Tag，因为旧根 Commit 尚未包含四个固定组件目录。
