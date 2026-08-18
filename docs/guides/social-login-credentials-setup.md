# 社交登录凭证申请教程（Google + Facebook）

> **用途**：为 PallasTrade 社交登录（PRD-20260818-other-p1-1）申请第三方 OAuth 凭证。
> **所需凭证**：
> | 凭证 | 敏感级别 | 存放位置 |
> |---|---|---|
> | Google OAuth Client ID | 公开（类似 publishable key） | storefront `NEXT_PUBLIC_GOOGLE_CLIENT_ID` + backend `GOOGLE_CLIENT_ID` |
> | Facebook App ID | 公开 | storefront `NEXT_PUBLIC_FACEBOOK_APP_ID` + backend `FACEBOOK_APP_ID` |
> | Facebook App Secret | **机密（绝不进前端）** | 仅 backend `FACEBOOK_APP_SECRET` |
>
> **预计耗时**：Google 约 15 分钟（需 Google 账号）；Facebook 约 20 分钟（需 Facebook 账号 + 开发者验证）。
> **注意**：凭证申请与代码实施可并行——未配置凭证时前端按钮自动隐藏、后端优雅返回错误，不影响开发与测试。

---

## 1. Google OAuth Client ID 申请

**流程**：Google Cloud Console → 创建项目 → 配置同意屏幕 → 创建 OAuth Client ID → 获取 Client ID。

### 1.1 创建 / 选择项目
1. 打开 [Google Cloud Console](https://console.cloud.google.com/)
2. 右上角项目下拉 → **新建项目**（或选择现有项目）
   - 项目名称建议：`pallastrade-social-login`
3. 确保顶部已切换到该项目

### 1.2 配置 OAuth 同意屏幕（OAuth consent screen）
1. 左侧菜单 → **APIs & Services（API 和服务）** → **OAuth consent screen（OAuth 同意屏幕）**
2. User Type 选择 **External**（外部，独立站标准选择）→ Create
3. 填写：
   - **App name**：PallasTrade
   - **User support email**：你的邮箱
   - **Developer contact email**：你的邮箱
4. **Scopes** 步骤：添加范围（Add or remove scopes）→ 勾选：
   - `.../auth/userinfo.email`（邮箱）
   - `.../auth/userinfo.profile`（姓名/头像）
   - `openid`
   - （这是默认最小集，不必全选）
5. **Test users（测试用户）**：开发阶段 Google 只允许列出的测试账号登录。把**你自己的 Gmail** 加进去（发布前才对所有用户开放）。
6. 保存（Publish status 保持 **Testing** 即可，后期正式上线再 Publish）

### 1.3 创建 OAuth Client ID
1. 左侧菜单 → **Credentials（凭据）** → **+ Create Credentials** → **OAuth client ID**
2. Application type 选择 **Web application**
3. 填写 **Authorized JavaScript origins（已授权的 JavaScript 来源）**：
   ```
   http://localhost:3001
   https://dev.pallastrade.cn
   https://pallastrade.cn
   ```
   > 这是 GIS（Google Identity Services）前端 JS 允许调用你的 Client ID 的来源，必须包含本地与线上域名。
4. **Authorized redirect URIs** 可留空（本方案用前端 JS 直接取 ID token，不走重定向回调）；如需兜底可加：
   ```
   http://localhost:3001
   ```
5. 点击 **Create** → 弹窗显示 **Client ID**（形如 `123456789012-xxxxxxxx.apps.googleusercontent.com`）

### 1.4 记录
- **Client ID**：`xxx.apps.googleusercontent.com`（**公开值**，可放前端）
- 本方案**不需要 Client Secret**（前端 JS 获取 ID token 仅需 Client ID；后端用 Google tokeninfo 端点验证，无需密钥）

---

## 2. Facebook App ID + App Secret 申请

**流程**：Facebook for Developers → 创建应用 → 添加 Facebook Login → 配置域名 → 获取 App ID + App Secret。

### 2.1 创建应用
1. 打开 [Facebook for Developers](https://developers.facebook.com/)（需 Facebook 账号登录）
2. 右上角 **My Apps** → **Create App（创建应用）**
3. 选择使用场景：**Authenticate and request data from users with Facebook Login** → Next
4. 填写 **App name**（如 `PallasTrade Social Login`）+ 联系邮箱 → Create App
5. 可能要求 **开发者验证**（手机号/邮箱验证），按提示完成

### 2.2 添加 Facebook Login 产品
1. 左侧菜单 → **Add Product（添加产品）** → 找到 **Facebook Login** → **Set up（设置）**
2. 进入 Facebook Login → **Quickstart** 可跳过，直接到 **Settings（设置）**
3. 在 **Valid OAuth Redirect URIs（有效的 OAuth 重定向 URI）** 添加：
   ```
   http://localhost:3001
   https://dev.pallastrade.cn
   https://pallastrade.cn
   ```
   > 本方案用 Facebook JS SDK 前端取 token，不走重定向；但配置完整来源可避免浏览器拦截。

### 2.3 配置站点域名（Settings → Basic）
1. 左侧 **Settings（设置）** → **Basic（基本）**
2. 填写：
   - **App Domains（应用域名）**：`dev.pallastrade.cn`、`pallastrade.cn`
   - **Privacy Policy URL（隐私政策 URL）**：你的政策页地址（Facebook 必填才能对外可用；开发期可先用占位，上线前补真）
   - **Category（类别）**：选择 Business 等
3. 保存

### 2.4 获取凭证
1. 仍在 **Settings → Basic** 页：
   - **App ID**（公开值，形如 `1234567890123456`）
   - **App Secret**（点击 **Show**，需输入 Facebook 密码；形如 `abcd1234...`）
2. **注意**：App Secret 是机密，**只能放后端环境变量**，绝不能暴露在前端代码或 NEXT_PUBLIC_ 变量中！

---

## 3. 配置到项目

### 3.1 后端（`backend/.env`，生产环境为服务器环境变量）
```bash
# Google OAuth（Client ID 公开）
GOOGLE_CLIENT_ID=123456789012-xxxxxxxx.apps.googleusercontent.com

# Facebook OAuth
FACEBOOK_APP_ID=1234567890123456
FACEBOOK_APP_SECRET=abcd1234...   # 机密，仅后端
```

### 3.2 Storefront（`storefront/.env.local`；生产环境为 CI/服务器环境变量）
```bash
# 仅公开值可进前端
NEXT_PUBLIC_GOOGLE_CLIENT_ID=123456789012-xxxxxxxx.apps.googleusercontent.com
NEXT_PUBLIC_FACEBOOK_APP_ID=1234567890123456
```

### 3.3 配置位置对照表
| 变量 | 值 | 前端可用? | 说明 |
|---|---|---|---|
| `GOOGLE_CLIENT_ID` | Client ID | ✅（公开） | GIS 前端 + 后端 audience 校验 |
| `FACEBOOK_APP_ID` | App ID | ✅（公开） | FB JS SDK 初始化 |
| `FACEBOOK_APP_SECRET` | App Secret | ❌（机密） | 后端生成 app token 校验用户 token |

---

## 4. 验证清单（申请完成后自查）

- [ ] Google Client ID 已添加到 Authorized JavaScript origins（含 localhost:3001 + dev + prod 域名）
- [ ] Google 测试用户已包含你自己的账号（Testing 状态）
- [ ] Facebook App ID + App Secret 已拿到（App Secret 未外泄）
- [ ] Facebook 已添加 Facebook Login 产品 + Valid OAuth Redirect URIs
- [ ] 后端 `.env` 已配置 3 个变量
- [ ] Storefront `.env.local` 已配置 2 个 NEXT_PUBLIC_ 变量

---

## 5. 常见问题（FAQ）

| 问题 | 原因 | 解决 |
|---|---|---|
| Google 弹窗报 "Error 403: access_denied" | 你的 Google 账号不在 Test users 里 | 1.2 步骤把账号加入 Test users |
| Google 登录后提示 "redirect_uri_mismatch" | 前端来源未加进 Authorized JavaScript origins | 1.3 补全 localhost/dev/prod 来源 |
| Facebook 按钮点了没反应 | 域名未加 App Domains / 未配置 Site URL | 2.3 补全 App Domains |
| Facebook 登录报 "URL Blocked" | Valid OAuth Redirect URIs 缺 localhost | 2.2 补全 redirect URIs |
| 生产环境按钮不显示 | NEXT_PUBLIC_ 变量未注入构建 | 确认 CI/服务器环境变量在构建时已注入（放 Variables 而非 Secrets，避免构建期为空） |
| Facebook App Secret 误入前端 | 泄漏风险 | 立即到 Facebook 后台 **重置 App Secret**，并确保只放后端 env |
