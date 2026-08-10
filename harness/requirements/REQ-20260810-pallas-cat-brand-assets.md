# 需求文档：兔狲品牌图片资源套件

## Step 0：跨层搜索（所有任务强制执行）

| 层 | 搜索路径 | 搜索关键词（含同义词） | 找到的文件 | 是否满足需求？ |
|---|---|---|---|---|
| App — models/controllers | `backend/app/` | logo、favicon、og:image、open graph、email logo、brand mark、mascot | 无 | 否 |
| App — views/decorators | `backend/app/` | 同上 | 无 | 否 |
| Core Gem — models | `backend/pallastrade_gems/pallastrade_core/app/models/` | 同上 | 无品牌图片实现 | 否 |
| Core Gem — services/views/assets | `backend/pallastrade_gems/pallastrade_core/app/` | 同上 | `assets/images/logo.png`、`views/pallastrade/shared/_mailer_logo.html.erb` | 部分；有旧 logo 与邮件入口，无兔狲套件 |
| API Gem — controllers | `backend/pallastrade_gems/pallastrade_api/app/controllers/` | 同上 | 无 | 不涉及 |
| Admin Gem — controllers | `backend/pallastrade_gems/pallastrade_admin/app/controllers/` | 同上 | 无 90×32 logo 逻辑 | 否 |
| Admin Gem — views/assets | `backend/pallastrade_gems/pallastrade_admin/app/` | 同上 | `assets/images/favicon_256x256.png`、`shared/_head.html.erb` | 部分；只有旧 favicon |
| Storefront | `storefront/src/` | 同上 | `components/layout/Header.tsx`、checkout `layout.tsx`、metadata builders、`app/favicon.ico` | 部分；入口存在，但缺少统一兔狲资源与 1200×630 OG 图 |
| Platform | `platform/packages/` | 同上 | 无相关实现 | 不涉及 |

### 搜索结论

现有系统已具备商城、结算、邮件、SEO 与 Admin 的品牌图片使用入口，但资产本身分散且没有统一兔狲视觉。根目录也没有同类交付文件夹。此次仅新增 `pallastrade-brand-assets/` 及图片，不改动现有入口，可避免重复业务实现和影响现有工作区改动。

## Step 1：Skill 文件咨询

**必读 Skill：**

| Skill 文件 | 状态 | 关键结论引用（至少一条） |
|---|---|---|
| `ai/skills/pallastrade-customization/SKILL.md` | ✅ 已读 | 决策树从 Settings/Config/Events/DI 到直接修改；本任务只交付独立静态资产，不需要引入运行时定制模式。 |
| `ai/skills/pallastrade-admin/SKILL.md` | ✅ 已读 | Admin 为独立 Rails engine；本阶段不改视图或控制器，只提供可按 90×32 使用的共享 logo。 |
| `ai/skills/pallastrade-catalog/SKILL.md` | ✅ 已读 | 图片资产通常经 ActiveStorage/媒体处理；本次是平台品牌资产而非商品媒体，因此不进入 Catalog 数据模型。 |

**按需 Skill：**

| Skill 文件 | 本次涉及？ | 状态 | 关键结论引用 |
|---|---|---|---|
| `pallastrade-api-v3` | 否 | N/A | 无 API、serializer 或路由变化。 |
| `pallastrade-decorators` | 否 | N/A | 不改变既有类结构。 |
| `pallastrade-dependencies` | 否 | N/A | 不替换核心服务。 |
| `pallastrade-events-webhooks` | 否 | N/A | 不产生事件或副作用。 |
| `pallastrade-storefront` | 是 | ✅ 已读 | Storefront 已有共享 SEO metadata 与 `/pallastrade-logo.svg` 引用；本任务只交付资源，不修改消费代码。 |
| `pallastrade-testing` | 否 | N/A | 无业务代码测试；采用尺寸、格式、透明度、文件大小和视觉联系表验证。 |
| `pallastrade-i18n` | 否 | N/A | 图片只包含固定品牌字标 `PallasTrade`。 |
| 系统 `imagegen` | 是 | ✅ 已读 | 默认使用内置 ImageGen；项目资源必须复制到工作区；透明需求先用纯色 chroma-key 再本地去背，并验证 alpha。 |
| `pallastrade-prd` | 是 | ✅ 已读 | 新功能先生成 draft PRD 与 REQ，用户明确确认后才生成资源并完成验证。 |

## 需求标题

创建可用于商城、邮件、SEO、favicon 与管理后台的统一兔狲品牌图片资源套件。

## 任务类型

新功能。

## 需求描述

在项目根目录新增 `pallastrade-brand-assets/`，交付以下图片：

- `pallastrade-logo.svg`：兔狲图形 + `PallasTrade` 字标，透明背景，约 2.8:1，供商城页头、结算和管理后台按 90×32 共用。
- `pallastrade-logo-email.png`：225×80 透明 PNG，≤200KB。
- `pallastrade-og.png`：1200×630 PNG，统一兔狲视觉和字标。
- `favicon-16x16.png`、`favicon-32x32.png`、`favicon-48x48.png`。
- `favicon.ico`：包含 16/32/48 三种尺寸。

兔狲形象采用扁平矢量卡通：宽脸、低位圆耳、蓬松脸颊、困倦琥珀眼和轻微呆笑；暖灰/沙棕毛色、琥珀强调、深炭轮廓。先用内置 ImageGen 生成形象锚点，再以简化矢量结构制作最终小尺寸可读版本。当前阶段不替换任何现有项目图片或代码引用。

## 影响范围（harness affected 输出）

`harness affected --base origin/main`：145 个已变更文件，影响 harness、ai、backend、platform、storefront，预计测试数 435。该输出反映现有工作区状态；本任务只新增根目录资源文件夹与流程文档，不修改这些既有文件。

## 技术方案（初步）

1. 使用 ImageGen 内置模式生成无文字、纯色背景的扁平兔狲形象锚点，并检查轮廓与表情。
2. 以锚点为视觉参考，创建不依赖外部图片的主 SVG，确保 90×32 下仍可读。
3. 从统一矢量构图导出邮件 PNG、OG PNG 与 favicon 多尺寸；ICO 用 16/32/48 PNG 封装。
4. 用 Sharp/Pillow 做尺寸、格式、alpha、体积和 ICO 帧验证；制作联系表进行视觉检查。
5. 所有最终图片只写入 `pallastrade-brand-assets/`，不集成到现有消费路径。

## 风险点

- 16×16 下复杂毛发会糊成一团：favicon 只保留低耳、宽脸和眼睛三个特征。
- 生成式图片的字标可能拼写不稳定：ImageGen 锚点不生成文字，最终 `PallasTrade` 由确定性 SVG 排版完成。
- 透明去背可能产生色边：锚点使用纯色 chroma-key，并按 imagegen 技能要求验证 alpha；最终生产 SVG/PNG 不依赖锚点边缘。
- 当前工作区已有大量未提交改动：严格限定新增文件路径，不替换或覆盖现有资产。

## 决策节点

请确认以上理解是否正确。确认后 AI 将输出详细设计/Go-No-Go 结论，然后生成并验证图片资源。

---

## 阶段③：实施后验证（不可跳过）

| 改动类型 | 改动文件 | 最低验证 | 执行结果 | 状态 |
|---|---|---|---|---|
| 品牌 SVG | `pallastrade-brand-assets/pallastrade-logo.svg` | XML/viewBox/90×32 渲染检查 | 90×32；viewBox 2.8125:1；无位图嵌入；视觉检查通过 | ✅ |
| 邮件 PNG | `pallastrade-brand-assets/pallastrade-logo-email.png` | 225×80、alpha、≤200KB | 225×80 RGBA；透明边角；11,930 bytes | ✅ |
| OG PNG | `pallastrade-brand-assets/pallastrade-og.png` | 1200×630 + 视觉检查 | 1200×630；91,092 bytes；无裁切/边界线 | ✅ |
| favicon | `pallastrade-brand-assets/favicon*` | 16/32/48 PNG 与 ICO 帧检查 | PNG 尺寸正确；ICO 含 16/32/48 三帧；16px 对比保留 | ✅ |
| 自动测试 | `tests/pallas-cat-brand-assets.test.mjs` | Node test + PRD AC 追溯 | 7 passed / 0 failed；全部 AC 有覆盖 | ✅ |
| 变更范围 | 整体 | `harness check --profile quick`、`harness doc-impact --base origin/main` | quick 0 error；doc-impact 8 synced / 0 missing | ✅ |

### 验证结论

全部 7 个图片资源满足尺寸、格式、透明度和体积要求；邮件、OG 与 favicon 已进行最终视觉检查。现有 Storefront、邮件与 Admin 资源未被替换。
