// harness.config.mjs — PallasTrade 项目配置（唯一项目特定配置入口）
// 引擎通用机制见独立包 pallastrade-harness（npx harness）；本文件声明 PallasTrade 自身结构。
// Schema 说明：docs/standards/harness-standalone-roadmap.md §6
export default {
  schemaVersion: '1.0',
  name: 'pallastrade',

  // ① 层定义：gate 跨层搜索（id 需与既有 gate check id 一致）
  layers: [
    { id: 'backend-app', path: 'backend/app', label: 'App (your code)' },
    { id: 'core',        path: 'backend/pallastrade_gems/pallastrade_core/app', label: 'Core framework models' },
    { id: 'api',         path: 'backend/pallastrade_gems/pallastrade_api/app', label: 'API framework endpoints' },
    { id: 'admin',       path: 'backend/pallastrade_gems/pallastrade_admin/app', label: 'Admin framework UI' },
    { id: 'storefront',  path: 'storefront/src', label: 'Storefront' },
    { id: 'platform',    path: 'platform/packages', label: 'Platform' },
  ],

  // ② gate 配置：项目追加的 check（PRD 工作流专属）
  gates: {
    expiryHours: { feature: 48, bugfix: 24, style: 8, audit: 24, research: 24, docs: 24, refactor: 24, security: 24, test: 24 },
    checkDefs: {
      feature: [
        { id: 'read-skill-prd',          label: 'Read Skill: pallastrade-prd/SKILL.md (PRD workflow)' },
        { id: 'create-prd-doc',          label: 'Create PRD doc: docs/prd/{category}/PRD-*.md' },
        { id: 'create-req-doc',          label: 'Create requirements doc: harness/requirements/REQ-*.md' },
        { id: 'req-doc-has-skill-table', label: 'REQ doc includes Skill consultation evidence table' },
        { id: 'user-confirmed',          label: 'User confirmed requirements doc (WAIT — do not proceed)' },
      ],
    },
  },

  // ③ 知识同步规则（doc-impact）— 镜像 AGENTS.md §7
  docImpact: {
    base: 'origin/dev',
    rules: [
      { codeGlob: /^backend\/app\/models\/.*\.rb$/, docs: ['ai/skills/pallastrade-catalog/SKILL.md', 'ai/skills/pallastrade-data-model/SKILL.md'], anyOf: true, label: 'Model change' },
      { codeGlob: /^backend\/app\/controllers\/.*\/api\/v3\/.*\.rb$/, docs: ['backend/public/api-docs/store.yaml', 'backend/public/api-docs/admin.yaml', 'platform/docs/api-reference/store.yaml', 'platform/docs/api-reference/admin.yaml'], anyOf: true, label: 'API endpoint change → API docs sync' },
      { codeGlob: /^backend\/app\/decorators\/.*\.rb$/, docs: ['ai/skills/pallastrade-decorators/SKILL.md'], label: 'Decorator change' },
      { codeGlob: /^backend\/app\/subscribers\/.*\.rb$/, docs: ['ai/skills/pallastrade-events-webhooks/SKILL.md'], label: 'Subscriber change' },
      { codeGlob: /^storefront\/src\/components\/.*\.tsx$/, docs: ['ai/skills/pallastrade-storefront/SKILL.md'], label: 'Storefront component change' },
      { codeGlob: /^storefront\/src\/app\/.*\.tsx$/, docs: ['ai/skills/pallastrade-storefront/SKILL.md'], label: 'Storefront page change' },
      { codeGlob: /\.(css|scss)$|tailwind\.config\./, docs: ['ai/skills/pallastrade-storefront/SKILL.md', 'ai/skills/pallastrade-admin/SKILL.md'], anyOf: true, label: 'Style change' },
      { codeGlob: /^ai\/skills\/.*\/SKILL\.md$/, docs: ['harness/scenarios/scenarios.json'], label: 'Skill file change' },
      { codeGlob: /^harness\/policies\/(anti-patterns|task-rules)\.json$/, docs: ['AGENTS.md', '.github/copilot-instructions.md'], anyOf: true, label: 'Policy change → agent docs sync' },
      { codeGlob: /^harness\/policies\/prd-categories\.json$/, docs: ['ai/skills/pallastrade-prd/SKILL.md', 'docs/prd/README.md'], anyOf: true, label: 'PRD category change' },
      { codeGlob: /^docs\/standards\//, docs: ['AGENTS.md'], label: 'Standards index change → navigation map sync' },
      { codeGlob: /^docs\/prd\/_TEMPLATE\.md$/, docs: ['ai/skills/pallastrade-prd/SKILL.md'], label: 'PRD template change' },
      { codeGlob: /^ai\/commands\/|^ai\/agents\//, docs: ['ai/README.md'], label: 'AI command/agent change → ai README sync' },
      { codeGlob: /^platform\/packages\/(cli|sdk|create-pallastrade-app)\//, docs: ['platform/README.md', 'platform/packages/README.md'], anyOf: true, label: 'Platform package change → README sync' },
      { codeGlob: /^(harness\.config\.mjs|package\.json|lefthook\.yml)$/, docs: ['AGENTS.md', 'ai/skills/pallastrade-prd/SKILL.md', 'harness/scenarios/scenarios.json'], anyOf: true, label: 'Harness config/deps change → workflow docs sync' },
    ],
  },

  // ④ 覆盖率
  coverage: {
    thresholds: {
      backend: { line: 80, branch: 60 },
      storefront: { lines: 10 },
      platform: { lines: 8 },
    },
    targets: [
      { id: 'backend', path: 'backend', testCmd: 'rspec' },
      { id: 'storefront', path: 'storefront', testCmd: 'vitest' },
      { id: 'platform', path: 'platform/packages', testCmd: 'vitest' },
    ],
  },

  // ⑤ 扫描器规则文件
  scanners: {
    antiPatterns: 'harness/policies/anti-patterns.json',
  },

  // ⑥ 项目级规范注册表与开发监督器（通用规则由独立包内置）
  standards: {
    includeBundled: true,
    sources: ['harness/standards/**/*.json'],
  },

  supervisor: {
    mode: 'guard',
    plansDir: '.harness-cache/plans',
    generatedFiles: [
      'backend/db/schema.rb',
      'backend/Gemfile.lock',
    ],
    protectedFiles: [],
    dependencyFiles: [
      'package.json',
      'backend/Gemfile',
      'storefront/package.json',
      'platform/**/package.json',
    ],
    testFiles: ['**/*.test.*', '**/*.spec.*', '**/test/**', '**/tests/**', '**/spec/**', '**/fixtures/**'],
    ruleDefinitionFiles: ['**/risk-engine.*', '**/domain-supervisors.*', '**/scan-*', '**/policies/**', '**/rules/**'],
    maxFiles: 20000,
    shardSize: 500,
    complexity: {
      maxDecisionPoints: 12,
      duplicateBlockLines: 6,
    },
    boundaries: [
      {
        id: 'storefront-does-not-import-backend',
        from: 'storefront/src/**/*.{js,jsx,ts,tsx}',
        denyImports: ['backend/**', '../backend/**', '../../backend/**'],
      },
      {
        id: 'platform-does-not-import-backend',
        from: 'platform/packages/**/*.{js,jsx,ts,tsx}',
        denyImports: ['backend/**', '../backend/**', '../../backend/**'],
      },
    ],
  },

  // ⑦ Project Brain / Risk / Evidence（1.0 生命周期治理）
  brain: {
    sources: [
      'AGENTS.md',
      '.github/copilot-instructions.md',
      '{backend,platform,storefront}/CLAUDE.md',
      'README.md',
      'docs/**/*.{md,mdx,json,yaml,yml}',
      'ai/skills/**/SKILL.md',
      'harness/**/*.{md,json,yaml,yml}',
    ],
    exclude: [
      '**/node_modules/**',
      '**/.git/**',
      '**/.env*',
      '**/*secret*',
      '**/artifacts/**',
      'harness/gates/**',
      '.harness-state/**',
      '.harness-cache/**',
    ],
    maxAssetBytes: 262144,
    maxContextAssets: 10,
    maxAssets: 20000,
    shardSize: 500,
  },
  risk: {
    criticalPaths: [
      'backend/db/migrate/**',
      '**/*payment*',
      '**/*auth*',
      '**/*permission*',
      '**/*secret*',
      '**/*deploy*',
      '.github/workflows/**',
      '**/Dockerfile*',
    ],
    standardPaths: ['backend/**/api/**', 'storefront/src/**', 'platform/packages/**', '**/package.json', '**/Gemfile', '**/*config*', '**/*schema*'],
  },
  evidence: {
    autoVerify: true,
    maxOutputBytes: 65536,
    // HTH-005: 已注册验证器（证据必须来自注册 verifier 才满足 Gate 的 test 类型）。
    // 按需运行：`npx harness verify <id> --task <TASK-ID>`。
    verifiers: {
      'backend-rspec': {
        description: 'Backend RSpec suite (PallasTrade core/api/app)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec'],
      },
      // 管理后台会话（登出跳转回归）：admin/user_sessions_spec
      'admin-sessions-rspec': {
        description: 'Admin session specs (sign-in guard + sign-out redirect back to the admin sign-in page)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/user_sessions_spec.rb'],
      },
      // 管理后台页面防缓存（退出后“后退”不还原已登录页）：no-store 响应头 + bfcache 兜底
      'admin-page-caching-rspec': {
        description: 'Admin page caching specs (no-store headers + back-forward-cache reload guard)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/page_caching_spec.rb'],
      },
      // AI 供应商适配器与模型目录（PRD-20260918-api-deepseek-structured-output）：
      // DeepSeek 结构化输出改用 json_object（不再发不受支持的 json_schema）+ 恢复被丢弃的
      // system_instructions + test_connection 由响应派生 status 且 5xx/网络失败返回结构化失败；
      // 目录与 provider registry 两处模型 ID 同步为 deepseek-flash。
      'ai-provider-rspec': {
        description: 'AI provider adapter + catalogue specs (DeepSeek json_object structured output, system instructions, connection test, model ids)',
        command: ['docker', 'exec', '-e', 'DISABLE_SIMPLECOV_MINIMUM=1', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && bundle exec rspec spec/services/pallastrade/ai/providers/deep_seek_spec.rb spec/services/pallastrade/ai/catalogs/deep_seek_spec.rb'],
      },
      // AI 输出校验与后端接线（PRD-20260918-admin-ai-output-validation）：
      // 声明了 output schema 却拿不到结构化输出 → 同步/异步两路径都判失败且报 ai_output_invalid；
      // 五个助手容器走 data: 前缀 + 单一 JSON 文案属性（此前裸属性名使 Stimulus 从未挂载）。
      'ai-output-validation-rspec': {
        description: 'AI output validation + admin assist wiring specs (gateway/job/adapter error codes, assistant data attributes and labels)',
        command: ['docker', 'exec', '-e', 'DISABLE_SIMPLECOV_MINIMUM=1', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && bundle exec rspec spec/services/pallastrade/ai/gateway_output_validation_spec.rb spec/jobs/pallastrade/ai/execute_run_job_spec.rb spec/services/pallastrade/ai/providers/normalize_error_spec.rb spec/requests/pallastrade/admin/ai_assist_wiring_spec.rb'],
      },
      // 仓库级回归守卫（2026-09-14）：部署脚本前滚检测 + 回滚演练 crontab 恢复 + PRD 状态同步
      // 台账收口 TASK-20260913113813-6b5a2a47 / TASK-20260913103421-bd645649 的证据来源。
      // 2026-09-18 扩入 AI 部署模板契约（PRD-20260918-api-deepseek-structured-output）：
      // PALLASTRADE_AI_ENABLED 与 ACTIVE_RECORD_ENCRYPTION_* 必须在模板登记且不得内置真实密钥。
      // 2026-09-18 再扩入 AI 助手接线契约（PRD-20260918-admin-ai-output-validation）：
      // 五处容器必须走共享 helper（data: 前缀），控制器必须保留兜底文案分支。
      // 第三次扩入 Docker 健康守卫（本地 Docker Desktop `docker exec` 卡死的自愈工具）：
      // 探测分类 / 自愈动作序列 / 进程解析 / 僵尸筛选（绝不误伤 compose up、logs -f）。
      'repo-guards-test': {
        description: 'Repo-level node:test guards (pull-deploy forward roll + drill crontab restore + PRD status sync + AI env template + AI assist wiring + docker health guard + deploy paths filter)',
        command: ['node', '--test', 'tests/pull-deploy-forward-roll.test.mjs', 'tests/drill-rollback-crontab.test.mjs', 'tests/prd-status-sync.test.mjs', 'tests/ai-env-template.test.mjs', 'tests/ai-assist-wiring.test.mjs', 'tests/docker-health.test.mjs', 'tests/deploy-paths-filter.test.mjs'],
      },
      // 管理后台店铺表单（2026-09-09 bugfix 回归集）：logo/mailer_logo 直传失败提示 + 多店 CRUD
      'admin-stores-rspec': {
        description: 'Admin store form specs (direct-upload attachment validation + multi-store CRUD)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/stores_attachment_upload_spec.rb spec/requests/pallastrade/admin/stores_multi_spec.rb'],
      },
      // 管理后台设计 token（B6-1）：品牌色阶/语义 token/密度双档 + 组件零直引 + WCAG AA 对比度契约
      'admin-theme-rspec': {
        description: 'Admin design-token contract specs (brand scales, semantic + density tokens, no direct palette usage, WCAG AA contrast)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/design/admin_theme_tokens_spec.rb'],
      },
      // 管理后台支付方式选项化（D1 切片3，PRD-20260915-admin）：页签渲染/保存归一 + Test connection +
      // 凭证脱敏；含切片1/2 回归（optionized 门控 + Start 入口级同源校验）
      // PRD-20260915-admin-管理后台支付配置选项化-支付商-支付方式-前台入口 AC-008
      'admin-payment-methods-rspec': {
        description: 'Admin payment-method option-config specs (options tab render/save + test connection + credential masking + optionized/start regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/payment_methods_spec.rb spec/services/pallastrade/payment_methods/test_connection_spec.rb spec/models/pallastrade/payment_method_options_spec.rb spec/services/pallastrade/payment_sessions/start_spec.rb'],
      },
      // D8 支付适用范围引擎（PRD-20260915-payments-d8）：入口/支付商按 market/country/zone/currency
      // PRD-20260915-payments-d8-支付适用范围引擎-支付商-支付方式-市场-国家-zone-币种-前台入口过滤 AC-009
      // 求值 + 前台/后台收集过滤 + Start 入口级校验 + 后台范围编辑与序列化投影
      'd8-availability-rspec': {
        description: 'Payment availability engine specs (rule-set normalize/evaluate + order frontend filtering + start option gate + admin scope editing/serializer)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/payments/availability/resolver_spec.rb spec/models/pallastrade/payment_method_options_spec.rb spec/services/pallastrade/payment_sessions/start_spec.rb spec/requests/pallastrade/admin/payment_methods_spec.rb'],
      },
      // D9 支付凭据与环境（PRD-20260915-payments-d9）：环境隔离（test 不进前台 + test_mode 标记）+
      // 凭据分级/env 引用 + 轮换到期巡检 + reveal 权限审计 + 后台环境/凭据/Webhook 卡（含 D1/D8 支付回归）
      // PRD-20260915-payments-d9-支付凭据与环境 AC-008
      'd9-credentials-rspec': {
        description: 'Payment credential & environment specs (env isolation + credential levels/env refs + expiry job + reveal audit + admin cards + D1/D8 regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d9_payment_method_environment_spec.rb spec/jobs/pallastrade/payment_methods/credential_expiry_check_job_spec.rb spec/requests/pallastrade/admin/payment_method_credentials_spec.rb spec/requests/pallastrade/admin/payment_methods_spec.rb spec/services/pallastrade/payment_methods/test_connection_spec.rb spec/models/pallastrade/payment_method_options_spec.rb spec/services/pallastrade/payment_sessions/start_spec.rb spec/services/pallastrade/payments/availability/resolver_spec.rb'],
      },
      // 管理后台商品批量运营 2.0（PRD-20260915-admin-bulk-operations-2）：批量价格/库存/渠道
      // + 预览零写入与计数一致性 + 逐条权限跳过 + i18n + 模态接线
      'admin-products-bulk-rspec': {
        description: 'Admin products bulk operations specs (preview-first price/inventory/channel batches + warnings + modal wiring)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/products_bulk_operations_spec.rb'],
      },
      // 管理后台 Catalog Health V1（PRD-20260915-admin-catalog-health-v1）：7 类 issue 口径
      // + 计数与过滤列表同源一致性 + 筛选横幅 + 导航子项（含 navigation_consistency 回归）
      // 2026-09-17 扩入覆盖率与健康分（PRD-20260917-catalog-health-{coverage-ratios,score}）：
      // 这两项直接建在 7 类计数之上，口径漂了会同时弄错页面上的比率与总分。
      // 2026-09-18 补入服务层（spec/services/pallastrade/catalog_health）：此前只跑请求级
      // 规格 → 覆盖面清单（metrics 的 7 键与顺序、每类必有分母）在服务层漂移时 CI 才报，
      // 而**注册验证器看不到**（dev Backend CI 因此白了 4 个提交）。
      'admin-catalog-health-rspec': {
        description: 'Admin catalog health specs (service layer: metric surface + denominators; issue semantics + filtered products list + banner + coverage ratios + health score + navigation consistency)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/catalog_health spec/requests/pallastrade/admin/catalog_health_spec.rb spec/requests/pallastrade/admin/catalog_health_coverage_spec.rb spec/requests/pallastrade/admin/catalog_health_score_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // 商品事件回流（PRD-20260917-catalog-product-events）：曝光/点击/加购/搜索落自有库。
      // 覆盖幂等 event_id、事件名白名单、批量上限整批拒收、跨店隔离、零 PII 摘要、CTR 口径与保留策略。
      'catalog-events-rspec': {
        description: 'Catalog events side channel (idempotency + event-name whitelist + store scoping + zero-PII digest + CTR caliber + retention)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/catalog_event_spec.rb spec/requests/api/v3/store/catalog_events_spec.rb spec/services/pallastrade/catalog_events/prune_spec.rb'],
      },
      // 批量移除媒体（PRD-20260917-catalog-bulk-media）：预览零写入 + 商品级/变体级媒体清空 +
      // primary_media 指针清理 + 权限逐项跳过 + 按 current_store 收窄 + bulk 审计。
      'bulk-media-rspec': {
        description: 'Admin bulk media removal (preview zero-write + gallery & variant images cleared + primary_media pointers nulled + no dangling VariantMedia + permission skip + store scoping + bulk audit)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/products/bulk_media_removal_spec.rb spec/requests/pallastrade/admin/bulk_media_removal_spec.rb'],
      },
      // 管理后台 i18n 覆盖率（2026-09-17 起）：en ↔ zh-CN 按功能域**双向**键集相等 +
      // 顶级键批次 + 已修缺陷回归。i18n 工作的产物是 locale YAML 与断言，
      // 不落在任何后端域验证器的覆盖范围里；后续还有约 1109 个键要分批补齐，
      // 每次都需要这条命令作为可校验证据来源。
      'admin-i18n-rspec': {
        description: 'Admin i18n locale coverage specs (bidirectional en/zh-CN key-set parity per domain + top-level key batch + regression pins)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/i18n/admin_catalog_locale_coverage_spec.rb'],
      },
      // SKU 级到货订阅（PRD-20260915-catalog-batch-c2-sku-back-in-stock）：variant_id 唯一约束
      // + 双通道通知（variant.back_in_stock → 该 SKU 订阅者；product.back_in_stock → 历史商品级）+ 后台 SKU 列
      'back-in-stock-rspec': {
        description: 'Back-in-stock subscription specs (SKU-level subscriptions, split notification channels, admin SKU column)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/back_in_stock_subscription_spec.rb spec/jobs/pallastrade/back_in_stock_subscriber_spec.rb spec/requests/api/v3/store/back_in_stock_subscriptions_spec.rb spec/requests/pallastrade/admin/back_in_stock_subscriptions_spec.rb spec/mailers/pallastrade/back_in_stock_mailer_spec.rb'],
      },
      // 商品级 Product History 时间线（PRD-20260915-catalog-batch-d1-product-history）：
      // 审计表即时间线（零迁移）+ 只记变化字段 + 批量每商品一条含计数 + 与 PriceHistory 合并倒序 + 后台侧栏渲染
      'product-history-rspec': {
        description: 'Product history specs (diff-only recorder writes, batch attribution, merged audit+price timeline, admin sidebar)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/product_history/recorder_spec.rb spec/services/pallastrade/product_history/timeline_spec.rb spec/requests/pallastrade/admin/product_history_spec.rb'],
      },
      // 重复商品检测（PRD-20260915-catalog-batch-d2-duplicate-detection）：三类信号（条码/SKU/名称）
      // + 计数与列表同源 + 店铺/软删除作用域 + 只读工作台与对比视图 + 导航子项一致性
      'duplicate-products-rspec': {
        description: 'Duplicate detection specs (three signals, count/list consistency, store + soft-delete scoping, admin worklist and compare view, navigation)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/duplicate_products_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // AI Product Copilot（PRD-20260915-catalog-batch-e1-ai-copilot）：两个能力注册 + schema 校验
      // + 业务服务（商品事实 → Gateway → Run 审计）+ 两个 admin 端点 + 降级/权限 + 「接受前不落库」
      'ai-copilot-rspec': {
        description: 'AI product copilot specs (capability registration, schemas, gateway service with run audit, admin draft endpoints, degradation, permissions, no-write guarantee)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/ai/catalog/product_copy_spec.rb spec/requests/pallastrade/admin/products_ai_copilot_spec.rb'],
      },
      // AI Translate Missing（PRD-20260915-catalog-batch-e2-ai-translate-missing）：能力注册 + schema
      // + 缺失字段口径（fallback:false，排除 slug）+ 无缺失零 Run + 端点 + 降级/权限 + 抽屉渲染
      'ai-translate-rspec': {
        description: 'AI translate-missing specs (capability registration, schemas, missing-field detection, gateway service, nothing-to-translate guard, admin endpoint, degradation, permissions, drawer rendering)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/ai/catalog/product_translation_spec.rb spec/requests/pallastrade/admin/products_ai_translation_spec.rb'],
      },
      // Catalog Health AI 修复建议（PRD-20260916-catalog-batch-e3-ai-fix-suggestion）：能力注册（read 授权）
      // + schema + 采样范围/字段最小化 + 计数 0/未知 issue 零 Run + 入口白名单 + 两种粒度端点 + 零写库 + 渲染
      'ai-health-suggestion-rspec': {
        description: 'Catalog health AI suggestion specs (read authorization, schemas, scoped and minimal sampling, nothing-to-fix guard, entry whitelist, worklist and product endpoints, no-write guarantee, worklist and product-card rendering)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/ai/catalog/health_fix_suggestion_spec.rb spec/requests/pallastrade/admin/catalog_health_ai_suggestion_spec.rb'],
      },
      // AI 采纳审计（PRD-20260916-catalog-ai-acceptance-audit）：Accept/Discard 留痕 ——
      // Run 采纳状态（幂等/改判）+ 端点（跨店 404 / 非法 state 422）+ 未处理不误报 + Runs 列表列
      'ai-acceptance-rspec': {
        description: 'AI acceptance audit specs (run acceptance state and timestamps, idempotent repeat, change of mind, undecided runs stay undecided, store-scoped endpoint, cross-store 404, invalid state 422, runs list column)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/ai/run_acceptance_spec.rb spec/requests/pallastrade/admin/ai_acceptances_spec.rb'],
      },
      // 评论系统升级一期（PRD-20260916-catalog-batch-f1-reviews）：评分分布与分页同源
      // + 图片直传（presign/归属/上限/类型）+ 审核页图片列
      'reviews-f1-rspec': {
        description: 'Review upgrade specs (paginated list with rating_distribution, load-more pages, image ownership/limit/signed-id errors, model photo limits, admin photo column)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/api/v3/store/reviews_spec.rb spec/requests/api/v3/store/reviews_pagination_spec.rb spec/requests/api/v3/store/reviews_images_spec.rb spec/models/pallastrade/review_spec.rb spec/requests/pallastrade/admin/reviews_spec.rb'],
      },
      // 评论列表排序（PRD-20260916-catalog-batch-f4-review-sorting）：白名单 sort + 稳定 tie-break
      // + meta.sort 回显 + 非法值回退（分布与排序正交）
      'f4-review-sorting-rspec': {
        description: 'Store review sorting specs (whitelist + fallback, stable id tie-break across pages, meta.sort echo with F-1 keys kept, distribution independent of ordering)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/api/v3/store/reviews_sorting_spec.rb spec/requests/api/v3/store/reviews_pagination_spec.rb'],
      },
      // 评论「有用」投票（PRD-20260916-catalog-batch-f5-helpful-vote）：一人一票（唯一索引）
      // + 幂等投票/撤销 + 读模型（计数公开、本人状态仅登录）+ most_helpful 排序 + 后台列
      'f5-helpful-vote-rspec': {
        description: 'Review helpful vote specs (one vote per customer with a unique index, idempotent POST/DELETE, own-review 422, non-approved 404, guest 401, cross-store 404, count + helpful_voted read model without voter identity, most_helpful ordering with stable tie-break, admin column)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/review_vote_spec.rb spec/requests/api/v3/store/review_votes_spec.rb spec/requests/api/v3/store/reviews_helpful_sorting_spec.rb spec/requests/pallastrade/admin/reviews_spec.rb'],
      },
      // 商品合并（PRD-20260916-catalog-d3-product-merge）：预检零写入 + 迁移守恒 + 冲突跳过 + 历史
      // 交易零改写 + 归档软删留痕 + 台账/审计 + 撤销逐项还原与阻塞拒绝 + 后台预览/执行/撤销
      'd3-product-merge-rspec': {
        description: 'Product merge specs (read-only preview with move/skip accounting, SKU & review conflicts kept where they were, archived + soft-deleted with merged_into, historical line items/orders untouched, idempotent merge, ledger + audit rows, undo restores every recorded item and refuses on blockers, admin preview / merge / undo)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/products/merge_preview_spec.rb spec/services/pallastrade/products/merge_spec.rb spec/services/pallastrade/products/undo_merge_spec.rb spec/requests/pallastrade/admin/product_merges_spec.rb'],
      },
      // 评论审核工作台批量通过/拒绝（PRD-20260916-catalog-batch-f3-review-bulk-moderation）：
      // 逐条鉴权 + 逐条走状态机（禁 update_all）+ 空选/超限守卫 + 四计数报告
      'f3-review-bulk-rspec': {
        description: 'Admin review bulk moderation specs (per-row state machine, empty/oversized guards, explainable report, bulk actions registered, approved-only contract kept)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/reviews_bulk_spec.rb'],
      },
      // 库存阈值化与配送信息（PRD-20260916-catalog-batch-f2-stock-shipping）：
      // 分桶口径（与 Variant#in_stock? 同源、tracking off 不制造稀缺）+ 阈值归一 +
      // 配送时效/免运费读模型 + 只增字段的序列化契约 + 列表不随条数放大查询
      'f2-stock-shipping-rspec': {
        description: 'Stock bucket + shipping estimate specs (buckets agree with in_stock?, threshold normalization, no exact quantity in any response, transit/free-shipping matrix, list query count constant)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/catalog/stock_status_spec.rb spec/services/pallastrade/shipping/estimate_spec.rb spec/requests/api/v3/store/stock_status_and_shipping_spec.rb'],
      },
      // 前台密钥下发（PRD-20260915-payments-d10-client-config）：client_config 组装（仅 publishable）
      // + env: 引用解析 + Checkout 契约下发 + Stripe publishable 声明（secret 不泄漏）
      'd10-client-config-rspec': {
        description: 'Frontend key delivery specs (client_config envelope, publishable-only projection, env: references, checkout payload, Stripe public preference declaration)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/payment_methods/client_config_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/serializers/pallastrade/api/v3/cart_serializer_spec.rb pallastrade_gems/pallastrade_stripe/spec/models/gateway_spec.rb'],
      },
      // Webhook 治理（PRD-20260915-payments-d12-webhook-governance）：入站事件流 + 隔离/人工标记
      // + 健康聚合 + 订阅核对清单 + 后台页面与导航
      'd12-webhook-governance-rspec': {
        description: 'Webhook governance specs (quarantine state machine + filters, event ops services with audits, health aggregation, subscription checklist, admin console + navigation)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d12_webhook_event_quarantine_spec.rb spec/services/pallastrade/payments/d12_webhook_event_ops_spec.rb spec/services/pallastrade/payments/d12_webhook_health_spec.rb spec/services/pallastrade/payments/d12_webhook_subscription_checklist_spec.rb spec/requests/pallastrade/admin/d12_webhook_events_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // 支付入口展示元数据（PRD-20260916-payments-d16-payment-method-presentation D16 切片1）：
      // option_id/method_key/display_name 读模型 + Checkout/支付方式序列化契约 + 选项化回归
      'd16-payment-presentation-rspec': {
        description: 'Payment entry presentation specs (effective option read model, option_id/method_key/display_name serialization, optionized regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d16_payment_option_presentation_spec.rb spec/models/pallastrade/payment_method_options_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/serializers/pallastrade/api/v3/cart_serializer_spec.rb'],
      },
      // 支付熔断与健康（PRD-20260916-payments-d11-circuit-breaker-health 切片1）：软置灰状态机
      // + 窗口健康指标 + 自动判定/到期恢复 + 巡检作业 + 前台可用性门禁 + 后台动作与卡面
      'd11-circuit-breaker-rspec': {
        description: 'Payment circuit breaker specs (soft-disable state machine + health metrics + evaluate/auto-recover + sweep job + resolver gating + admin actions/card)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d11_soft_disable_spec.rb spec/services/pallastrade/payments/d11_health_metrics_spec.rb spec/services/pallastrade/payments/d11_circuit_breaker_spec.rb spec/jobs/pallastrade/payments/d11_circuit_breaker_sweep_job_spec.rb spec/services/pallastrade/payments/availability/d11_breaker_gating_spec.rb spec/services/pallastrade/payments/availability/resolver_spec.rb spec/requests/pallastrade/admin/d11_payment_method_soft_disable_spec.rb'],
      },
      // 对账差异队列（PRD-20260916-payments-d13-reconciliation-cases 切片1）：案例模型口径
      // + SyncCases 幂等/自动销案/签名取代/零资金副作用 + sweeper 接入 + 后台工作台（筛选/动作/CSV/权限）
      'd13-reconciliation-cases-rspec': {
        description: 'Reconciliation case queue specs (model mapping/state machine + sync idempotency/auto-close/supersede + sweeper integration + admin workbench filters/actions/CSV/permissions)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d13_reconciliation_case_spec.rb spec/services/pallastrade/reconciliations/d13_sync_cases_spec.rb spec/jobs/pallastrade/reconciliations/reconcile_sweeper_job_spec.rb spec/requests/pallastrade/admin/d13_reconciliation_cases_spec.rb'],
      },
      // 结算台账（PRD-20260916-payments-d13b-payout-ledger 切片2）：payout/payout_line 口径
      // + CSV 导入幂等与拒绝 + 匹配锚点/容差 + 差异行入队/销案 + 后台台账（筛选/汇总/详情/导入/重匹配/权限）
      'd13b-payouts-rspec': {
        description: 'Payout settlement ledger specs (status synthesis/totals/uniqueness + CSV import idempotency/errors + match anchors/tolerance + case sync/auto-close/supersede + admin ledger filters/detail/import/match/permissions)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d13b_payout_spec.rb spec/services/pallastrade/reconciliations/payouts/d13b_import_csv_spec.rb spec/services/pallastrade/reconciliations/payouts/d13b_match_spec.rb spec/services/pallastrade/reconciliations/payouts/d13b_sync_cases_spec.rb spec/requests/pallastrade/admin/d13b_payouts_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // 退款审批（PRD-20260916-payments-d14-refund-approval 切片1）：策略阈值（≤ 自动 / > 需审批）
      // + 双人复核（不能自批）+ 请求级幂等键 + 审批工作台/策略卡 + Admin API 策略门与契约字段
      'd14-refund-approval-rspec': {
        description: 'Refund approval specs (policy normalization matrix + auto/pending branches + request_key idempotency + two-person approve/reject with SoD + admin workbench/policy card/permissions + admin API gate & contract field)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d14_refund_approval_spec.rb spec/services/pallastrade/refunds/d14_policy_spec.rb spec/services/pallastrade/refunds/d14_submit_spec.rb spec/services/pallastrade/refunds/d14_approval_decision_spec.rb spec/requests/pallastrade/admin/d14_refund_approvals_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb spec/requests/api/v3/admin/orders/refunds_approval_spec.rb spec/requests/api/v3/admin/orders/refunds_controller_spec.rb'],
      },
      // 争议期限分档（PRD-20260916-payments-d14b-dispute-deadlines 切片2）：T-3/T-1 分档幂等告警
      // + 跳档补齐 + 超期策略化自动 lost（默认关闭/单轮上限）+ sweeper/订阅者 + 后台看板（含 DSP-P7-5 回归）
      'd14b-dispute-deadlines-rspec': {
        description: 'Dispute deadline tier specs (policy normalization + tier ledger idempotency/backfill + tier events + policy-gated auto-lose + sweeper metrics + subscriber tiers + admin board/filter/history + DSP-P7-5 regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/disputes/d14b_deadline_policy_spec.rb spec/services/pallastrade/disputes/d14b_alert_deadlines_spec.rb spec/jobs/pallastrade/disputes/d14b_deadline_sweeper_spec.rb spec/subscribers/pallastrade/disputes/d14b_deadline_subscriber_spec.rb spec/requests/pallastrade/admin/d14b_disputes_ops_deadline_spec.rb spec/services/pallastrade/disputes/scan_deadlines_spec.rb spec/jobs/pallastrade/disputes/deadline_sweeper_job_spec.rb spec/subscribers/pallastrade/disputes/deadline_alert_subscriber_spec.rb'],
      },
      // 风控名单（PRD-20260916-payments-d15-risk-lists 切片1）：名单台账/归一化 + 批量导入导出 + 维护审计
      // + 名单驱动评估留痕（白名单短路/黑名单默认 review）+ 订阅者接线 + 后台工作台/订单页决策卡（含导航一致性回归）
      'd15-risk-lists-rspec': {
        description: 'Risk list specs (normalization/uniqueness/active scope + CSV import/export round-trip + upsert/revoke audit + assessment decision matrix & idempotency & store isolation & zero money side effects + order.submitted wiring + admin workbench/order card + navigation regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d15_payment_risk_list_spec.rb spec/services/pallastrade/risk/d15_upsert_import_export_spec.rb spec/services/pallastrade/risk/d15_assess_spec.rb spec/subscribers/pallastrade/risk/d15_order_submitted_spec.rb spec/requests/pallastrade/admin/d15_risk_lists_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // 费率模型与支付成本报表（PRD-20260916-payments-d13c-fee-cost-report 切片3）：费率策略归一化/优先级/条件
      // + 单笔计算（分量/保底封顶/跨境与转换的不猜口径）+ 只读成本报表（自洽/按入口排名/可下钻/实际 vs 模型/
      // 跨店隔离/零资金副作用/查询数不随行数增长）+ 后台费率维护与报表页（计数同源/审计/权限/CSV 无卡号）
      'd13c-cost-report-rspec': {
        description: 'Fee policy & payment cost report specs (normalization/priority/conditions + per-payment calculation with min/max clamp and never-guess cross-border/conversion + read-only report self-consistency/entry ranking & drill-down/actual vs modelled variance/store isolation/zero money side effects/flat query count + admin fee policy maintenance & cost report pages with audit/permissions/CSV without card data)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d13c_payment_fee_policy_spec.rb spec/services/pallastrade/payments/fees/d13c_resolver_spec.rb spec/services/pallastrade/payments/fees/d13c_calculate_spec.rb spec/services/pallastrade/payments/costs/d13c_report_spec.rb spec/requests/pallastrade/admin/d13c_payment_fee_policies_spec.rb spec/requests/pallastrade/admin/d13c_payment_costs_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // 汇率快照与结算汇率对比（PRD-20260916-payments-d13d-fx-snapshot 切片4）：多源汇率解析/幂等维护
      // + 下单锁汇（加点后有效汇率）+ 结算汇率对比（显式/推导/不可判定 + bips 容差）+ 差异入队 kind=fx 与自动销案
      // + 订阅者/巡检作业 + 后台汇率表与快照页（计数同源/权限/CSV）+ 结算导入可选 fx_rate 列回归
      'd13d-fx-snapshot-rspec': {
        description: 'FX snapshot specs (rate normalization/identity/priority & store-over-global resolution + upsert idempotency/revoke/audit + fx policy normalization + order-submitted locking with up-charge and never-guess branches + settlement comparison provider-reported/implied/undetermined with bips tolerance + fx case queueing/auto-close/human protection/event + store isolation & period + zero money side effects & flat read queries + subscriber wiring + compare sweeper metrics/schedule + admin rate table & snapshot workbench & CSV + d13b import fx_rate regression + navigation regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d13d_currency_rate_spec.rb spec/models/pallastrade/d13d_fx_snapshot_spec.rb spec/services/pallastrade/currencies spec/subscribers/pallastrade/currencies spec/jobs/pallastrade/currencies spec/requests/pallastrade/admin/d13d_currency_rates_spec.rb spec/requests/pallastrade/admin/d13d_fx_snapshots_spec.rb spec/services/pallastrade/reconciliations/payouts/d13b_import_csv_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
      },
      // D14 切片3（拒付率看板 + 卡组织阈值预警）：只读统计 + 预警台账，零资金副作用
    'd14c-dispute-rates-rspec': {
      description: 'Dispute rate specs (rate policy normalization/classify dual thresholds & unconfigured never judged + rate report caliber numerator=window disputes denominator=window completed card payments of that network + brand alias normalization + unknown bucket excluded from judgement + cross-currency exclusion counters + nil ratio on empty denominator + out-of-window dispute attribution + drill-down four dimensions with bucket sums equal to totals + segment returning customers + network filter + read-only with flat query count + degraded envelope + window override; alert ledger idempotency by store/network/evaluated_on + tier escalation with escalated_at & single event + same-day no-downgrade with relaxed_at + unknown network skip + disabled policy + audit + zero money side effects; sweeper multi-store loop with failure isolation & structured metrics & window override & zero provider; admin board cards/drill-down/ledger/policy save/normalize/apply-suggested/reevaluate/denylist masked-resolution & ambiguity refusal/CSV masked with audit/permission; navigation regression)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d14c_dispute_rate_alert_spec.rb spec/services/pallastrade/disputes/d14c_rate_policy_spec.rb spec/services/pallastrade/disputes/d14c_rate_report_spec.rb spec/services/pallastrade/disputes/d14c_rate_alert_spec.rb spec/jobs/pallastrade/disputes/d14c_rate_alert_sweeper_spec.rb spec/requests/pallastrade/admin/d14c_dispute_rates_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
    },
    // D15 切片2（风控规则引擎版本化/灰度/回滚）：数据驱动规则 + 不可变版本 + 确定性灰度分桶
    // + 与名单的「最严者胜」决策合并 + 后台工作台（发布/金丝雀/回滚/试算），零 provider、零资金副作用
    'd15b-risk-rules-rspec': {
      description: 'Risk rule engine specs (rule set/version model with per-scope unique codes & immutable published versions; condition vocabulary per key with boundary matches and never-guess skips; schema validation rejecting unknown keys/invalid types/duplicate codes/oversized payloads without storing; evaluator priority first-match & store-over-global precedence & consulted-version-on-no-match; canary bucketing stable per order, 0/100 boundaries, bucket==percent goes stable; versioning draft/publish/canary/deactivate with archived predecessors & audit; rollback creating a new version from historical content with source_version/reason and no history rewrite + required reason; events risk.rule_version_published/rolled_back with PII-free payloads; assess integration strictest-action merge & allowlist short-circuit & rule_engine trail in signals/metadata & zero money side effects; admin workspace counts/list same source, detail version history, create/draft/publish/canary/rollback/toggle actions, read-only preview with bucket/version/rule, permission denial; preflight + slice-1 assess/lists regression; navigation regression)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d15b_risk_rule_set_spec.rb spec/services/pallastrade/risk/d15b_rules_condition_spec.rb spec/services/pallastrade/risk/d15b_rules_evaluate_spec.rb spec/services/pallastrade/risk/d15b_versioning_spec.rb spec/services/pallastrade/risk/d15b_assess_integration_spec.rb spec/requests/pallastrade/admin/d15b_risk_rules_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb spec/services/pallastrade/checkout/preflight_spec.rb spec/services/pallastrade/risk/d15_assess_spec.rb spec/requests/pallastrade/admin/d15_risk_lists_spec.rb'],
    },
    // D15 切片3（3DS/SCA 策略与 provider 下发）：门店策略可配置 + 订单级认证需求判定（唯一入口、只读）
    // + 规则动作 force_3ds（严重度 allow<review<force_3ds<block）+ 入口闸门（高风险只给能认证的入口，
    // 与 Start 同源、建会话前拒绝）+ 已声明能力才下发（不支持就诚实不下发），零 provider I/O。
    'd15c-three-d-secure-rspec': {
      description: '3DS/SCA specs (store policy normalize with fail-safe reads & storable writes, unknown mode/negative threshold/invalid country refused without storing, audit on save, unconfigured store returns defaults; order-level requirement resolution across always/risk_based/off with risk strictness precedence and policy_off_overridden_by, exemptions low_amount/country/option narrowing only the challenge never the block, threshold only compared inside the store currency; force_3ds action accepted by the publish gate while illegal actions still refused, severity order allow<review<force_3ds<block, strictest-merge keeps block and allowlist still short-circuits, assessment accepts force_3ds and flags it with rule_engine trail; capability catalog declaring three_d_secure supported/unsupported with undeclared treated as unsupported; availability resolver gating capable entries only + three_d_secure reason dimension + flat query count; session start refusing non-capable entries with 422 payment_option_not_available reason=authentication_required before any session row; checkout projection exposing requires_authentication with hidden=absent; provider hint sending request_three_d_secure=any only for declared-capable Stripe card and reporting none otherwise; admin store policy block save/validate/audit + entry capability column; D8 availability/D11 breaker/D16 presentation/checkout serializer/slice-1+2 risk regression; navigation regression)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/payments/three_d_secure/d15c_policy_spec.rb spec/services/pallastrade/payments/three_d_secure/d15c_required_spec.rb spec/services/pallastrade/risk/d15c_force_3ds_action_spec.rb spec/services/pallastrade/payments/availability/d15c_authentication_gate_spec.rb spec/services/pallastrade/payment_sessions/d15c_start_gate_spec.rb spec/services/pallastrade_stripe/d15c_three_d_secure_hint_spec.rb spec/requests/api/v3/store/d15c_checkout_authentication_spec.rb spec/requests/pallastrade/admin/d15c_three_d_secure_policy_spec.rb spec/services/pallastrade/payments/availability/resolver_spec.rb spec/services/pallastrade/payment_sessions/start_spec.rb spec/services/pallastrade/payments/d11_circuit_breaker_spec.rb spec/models/pallastrade/d16_payment_option_presentation_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/services/pallastrade/risk/d15_assess_spec.rb spec/services/pallastrade/risk/d15b_rules_evaluate_spec.rb spec/services/pallastrade/checkout/preflight_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
    },
    // D7（支付区收尾：入口级支付列表 + 钱包快付 + 三页共用支付区）：
    //   入口级投影（一入口一行，集合来自 Availability::Resolver，与 Start 同源）
    //   + `option_kind` 全链路（cart legacy / orders payment_sessions / durable transactions）
    //   + 不可用入口在建会话前被拒且零 session 行 + 旧响应回退单入口（零回归）。
    //   前端侧（PaymentSection/WalletPaymentButtons/三页接线）由 `storefront-test` 覆盖。
    'd7-payment-section-rspec': {
      description: 'D7 payment-section specs (entry projection: optionized provider expands one entry per enabled option in position order with option_id/method_key/display_name/frontend_kind/group, non-optionized provider keeps a single implicit entry, disabled entries dropped, provider-level group/position follow the first effective entry, entry availability filtered through the Availability resolver; checkout projection: entries array mirrors the resolver kinds for the order context, string-keyed entry fields, legacy fallback for providers without options; request channels: orders payment_sessions and durable orders.transactions accept option_kind and start a session for a declared entry, an undeclared entry is refused with 422 payment_option_not_available (orders/transactions) or the legacy validation_error code (carts) and creates zero session rows; D8 availability + D16 presentation + checkout serializer + transaction/payment-session regressions)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/d7_payment_option_entries_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/d7_entries_spec.rb spec/requests/api/v3/store/d7_payment_option_kind_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/services/pallastrade/transactions spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb'],
    },
    // D2（交易排障台人工复核裁决）：通过并捕获 / 拒绝并释放 —— manual_review 的唯一出口，
    // 幂等 + 原因必填 + 审计留痕 + 人工专用（job/sweeper/subscriber 永不调用），零退款、零历史改写。
    'd2-manual-review-rspec': {
      description: 'D2 manual review specs (service: capture branch validating a pending authorization then capturing + approve_after_review + existing Finalize to completed, release branch voiding the authorization + Orders::Cancel with the enum reason + release_after_review to canceled with zero refunds, refusals for reason_required/invalid_decision/transaction_not_reviewable/no_pending_authorization/paid_payment_present with the transaction unchanged, (transaction, decision) audit-key idempotency returning already_applied with a single audit row, before/after + decision + reason + actor audit trail, human-only call-site assertion proving the controller is the only caller and no job touches the review events; admin request: 302 + flash for approve_and_capture/release_and_cancel, reason and pending-authorization guards via flash errors, show page rendering both verdict forms for manual_review and no verdict action for other states, review history rendering; state machine + admin transactions + recover/finalize regressions)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/transactions/d2_review_spec.rb spec/requests/pallastrade/admin/d2_transaction_review_spec.rb spec/requests/pallastrade/admin/transactions_spec.rb spec/models/pallastrade/commerce_transaction_spec.rb spec/models/pallastrade/commerce_transaction_recovery_spec.rb spec/services/pallastrade/transactions'],
    },
    // D3（风控看板与阈值告警）：5 水位读模型（risky 单 / 3DS 挑战率 / 拒付率 / 退款率 / 审核队列时长）
    // + 阈值策略归一化 + 双档判定（ok/approaching/breached/unconfigured/unavailable）+ 同日留痕幂等且不降档。
    // 铁律：零写库（除审计留痕）/ 零 provider I/O / 不可判定不猜（nil + 结构化 reason）/ 不重算 D14c 口径。
    'd3-risk-dashboard-rspec': {
      description: 'D3 risk dashboard specs (policy: metric whitelist 5, window bounds, threshold normalization with warning<critical enforcement and out-of-range/invalid-type refusal codes, fail-safe read of garbage payloads returning defaults with reasons, configured? requiring both thresholds; threshold classifier: five statuses ok/approaching/breached/unconfigured/unavailable with unconfigured as first-class, alerting only on approaching/breached and severity ordering; report: risky_orders ratio from assessments over submitted orders, three_ds_challenge_rate from payment session external_data hints, dispute_rate delegated to Disputes::RateReport (injected seam for failure/degradation), refund_rate from refunds over completed payments, review_queue_duration from the D2 audit trail with oldest pending + handled p90, every metric returning nil+structured reason instead of guessing, store scoping, degraded envelope for nil store, flat query count; alert: one audit + one PII-free event on tier entry, no record when the metric is disabled, duplicate suppression, no_downgrade_same_day, cross-store isolation, degraded report skipped, zero payment/refund side effects; sweeper job: per-store isolation, single-store mode, idempotent runs, garbage policy and unknown store never raising, transaction state untouched; admin request: index rendering five metric rows with status attributes + policy form + alert history scoped by data-testid, valid policy save with audit, invalid policy refused without persisting, on-demand reevaluation recording the breach, permission denial writing nothing; navigation regression; D14c rate report/policy/alert/sweeper + availability resolver + D2 review regressions)',
      command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/risk/d3_dashboard_policy_spec.rb spec/services/pallastrade/risk/d3_dashboard_threshold_spec.rb spec/services/pallastrade/risk/d3_dashboard_report_spec.rb spec/services/pallastrade/risk/d3_dashboard_alert_spec.rb spec/jobs/pallastrade/risk/d3_dashboard_alert_sweeper_job_spec.rb spec/requests/pallastrade/admin/d3_payment_risk_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb spec/services/pallastrade/disputes/d14c_rate_report_spec.rb spec/services/pallastrade/disputes/d14c_rate_policy_spec.rb spec/services/pallastrade/disputes/d14c_rate_alert_spec.rb spec/jobs/pallastrade/disputes/d14c_rate_alert_sweeper_spec.rb spec/services/pallastrade/payments/availability/resolver_spec.rb spec/services/pallastrade/transactions/d2_review_spec.rb'],
    },
    // 财务对账线（FIN-P4-6/7 + DSP-P7-3 + REV-P6-7）：只读对账（source/transaction/dispute）+ 扫措作业
    'finance-reconciliation-rspec': {        description: 'Finance reconciliation specs (source/transaction/payment/refund/dispute reconcilers + sweeper job)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/reconciliations spec/jobs/pallastrade/reconciliations/reconcile_sweeper_job_spec.rb'],
      },
      // P1 订单流程改造：本次变更相关 spec（新购物车/提交订单/回归）
      // 2026-09-14（PRD-20260914-checkout-cart-gift-cards-canonical）：补 cart_ canonical 端点规格
      'p1-order-flow-rspec': {
        description: 'P1 order-flow specs (cart/submit/request + canonical cart gift cards / store credits + regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/cart_spec.rb spec/services/pallastrade/carts/submit_spec.rb spec/services/pallastrade/carts/apply_gift_card_spec.rb spec/services/pallastrade/carts/store_credit_spec.rb spec/requests/api/v3/store/carts_controller_spec.rb spec/requests/api/v3/store/carts/gift_cards_spec.rb spec/requests/api/v3/store/carts/store_credits_spec.rb spec/requests/api/v3/store/carts/discount_codes_spec.rb spec/models/pallastrade/order_parent_child_spec.rb spec/requests/api/v3/store/payment_combinations_controller_spec.rb spec/services/pallastrade/carts/auto_split_spec.rb'],
      },
      // P1 订单流程改造（前端）：storefront vitest 全量套件
      'storefront-test': {
        description: 'Storefront vitest suite (unit + component)',
        command: ['node', 'storefront/node_modules/vitest/vitest.mjs', 'run', '--root', 'storefront'],
      },
      // 订单模块（PRD-20260829-checkout 订单模块）：收货地址更新 + 组合支付 + 购物车回归
      'order-module-rspec': {
        description: 'Order-module specs (shipping address + combined payment + cart regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/api/v3/store/customer_order_shipping_address_spec.rb spec/requests/api/v3/store/payment_combinations_controller_spec.rb spec/requests/api/v3/store/carts_controller_spec.rb'],
      },
      // P0 支付加固（PRD-20260902-payments P0-0..P0-7）：全 P0 相关 spec（幂等/Webhook/FK/金额权威/加密/审计/guardrail）
      'p0-payment-rspec': {
        description: 'P0 payment hardening specs (P0-0..P0-7 regression set)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/payment_sessions/start_spec.rb spec/services/pallastrade/payments/handle_webhook_spec.rb spec/services/pallastrade/payments/handle_webhook_combination_spec.rb spec/services/pallastrade/carts/complete_spec.rb spec/models/pallastrade/payment_session_payment_association_spec.rb spec/services/pallastrade_stripe/create_payment_session_association_spec.rb spec/models/pallastrade/payment_webhook_event_spec.rb spec/services/pallastrade/payments/webhook_event_store_spec.rb spec/services/pallastrade/payments/replay_webhook_event_spec.rb spec/jobs/pallastrade/payments/handle_webhook_job_spec.rb spec/serializers/pallastrade/api/v3/cart_serializer_spec.rb spec/models/pallastrade/gateway_preferences_encryption_spec.rb spec/services/pallastrade/payments/error_codes_spec.rb spec/services/pallastrade/audit_spec.rb spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/pallastrade/api/middleware/request_id_spec.rb'],
      },
      // CHK-P1-1A（PRD-20260903-checkout-chk-p1-1a）：只读 CheckoutView 新增 + Order 域回归
      'chk-p1-1a-rspec': {
        description: 'CHK-P1-1A checkout-view specs (service/serializer/request + order regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/order_checkout/view_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/requests/api/v3/store/orders/checkout_controller_spec.rb spec/requests/api/v3/store/customer_orders_controller_spec.rb spec/requests/api/v3/store/customer_order_shipping_address_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/order_serializer_parent_child_spec.rb'],
      },
      // CHK-P1-1B（PRD-20260903-checkout-chk-p1-1 §12）：Mutation Facade + 1A + Order 域回归
      'chk-p1-1b-rspec': {
        description: 'CHK-P1-1B mutation-facade specs + 1A checkout-view + order regression',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/order_checkout/mutation_facade_spec.rb spec/services/pallastrade/order_checkout/view_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/requests/api/v3/store/orders/checkout_controller_spec.rb spec/requests/api/v3/store/customer_orders_controller_spec.rb spec/requests/api/v3/store/customer_order_shipping_address_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/order_serializer_parent_child_spec.rb'],
      },
      // CHK-P1-2（PRD-20260903-checkout-chk-p1-1 §12）：Version/Expiration/Recalculate/Refresh + 1A/1B + 回归
      'chk-p1-2-rspec': {
        description: 'CHK-P1-2 versioning specs + checkout-view + mutation + order regression',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/order_checkout/versioning_spec.rb spec/services/pallastrade/order_checkout/view_spec.rb spec/services/pallastrade/order_checkout/mutation_facade_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/requests/api/v3/store/orders/checkout_controller_spec.rb spec/requests/api/v3/store/customer_orders_controller_spec.rb spec/requests/api/v3/store/customer_order_shipping_address_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/order_serializer_parent_child_spec.rb spec/services/pallastrade/carts/submit_spec.rb'],
      },
      // CHK-P1-3（PRD-20260903-checkout-chk-p1-1 §12）：Readiness/Snapshot/Payment Start Gate + 1A/1B/P1-2 + 支付回归
      'chk-p1-3-rspec': {
        description: 'CHK-P1-3 readiness/snapshot/start-gate specs + checkout-view + payment regression',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/order_checkout/readiness_spec.rb spec/services/pallastrade/order_checkout/snapshot_spec.rb spec/services/pallastrade/order_checkout/versioning_spec.rb spec/services/pallastrade/order_checkout/view_spec.rb spec/services/pallastrade/order_checkout/mutation_facade_spec.rb spec/services/pallastrade/payment_sessions/start_spec.rb spec/serializers/pallastrade/api/v3/store/checkout/checkout_serializer_spec.rb spec/requests/api/v3/store/orders/checkout_controller_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb spec/requests/api/v3/store/carts_controller_spec.rb'],
      },
      // CHK-P1-4（PRD-20260903-checkout-chk-p1-1 §12）：SDK orders.checkout + storefront CheckoutView 只读消费 + 轻量收编
      'chk-p1-4-storefront': {
        description: 'CHK-P1-4 storefront checkout tests (OrderPaymentContent view-driven + checkout/data regression)',
        command: ['node', 'storefront/node_modules/vitest/vitest.mjs', 'run', '--root', 'storefront', 'src/components/checkout', 'src/lib/data/__tests__/shopping-cart.test.ts', 'src/lib/data/__tests__/checkout.test.ts'],
      },
      // CHK-P1-5（PRD-20260903-checkout-chk-p1-1 §12）：Quote-Conflict 409（expected_version/price_version）+ quote 语义回归
      'chk-p1-5-rspec': {
        description: 'CHK-P1-5 quote-conflict 409 specs + quote/checkout/payment regression',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/services/pallastrade/payment_sessions/start_spec.rb spec/requests/api/v3/store/order_payment_sessions_controller_spec.rb spec/requests/api/v3/store/cart_payment_sessions_controller_spec.rb spec/requests/api/v3/store/orders/checkout_controller_spec.rb spec/services/pallastrade/order_checkout/versioning_spec.rb'],
      },
      // CHK-P1-4B（PRD-20260903-checkout-chk-p1-1 §12）：Storefront mutation 消费（checkout.update + 编辑 UI + 409）
      'chk-p1-4b-storefront': {
        description: 'CHK-P1-4B storefront mutation/409 UI tests (OrderPaymentContent + checkout regression)',
        command: ['node', 'storefront/node_modules/vitest/vitest.mjs', 'run', '--root', 'storefront', 'src/components/checkout/__tests__/OrderPaymentContent.test.tsx', 'src/components/checkout/__tests__/PaymentCheckoutModal.test.tsx', 'src/components/checkout/__tests__/UnifiedCheckout.test.tsx'],
      },
      // CHK-P1-4C（PRD-20260903-checkout-chk-p1-1 §12）：孤儿页移除 + 死代码清理回归
      'chk-p1-4c-storefront': {
        description: 'CHK-P1-4C storefront cleanup regression (modal/payment-result/account tests)',
        command: ['node', 'storefront/node_modules/vitest/vitest.mjs', 'run', '--root', 'storefront', 'src/components/checkout/__tests__/PaymentCheckoutModal.test.tsx', 'src/app/[country]/[locale]/(checkout)/payment-result/[id]/__tests__/page.test.tsx', 'src/components/account/__tests__/OrderCombinedPay.test.tsx', 'src/components/account/__tests__/OrderPayButton.test.tsx'],
      },
      // CHK-P1-4C4（PRD-20260903-checkout-chk-p1-1 §12）：legacy 一页式退役回归（checkout 组件 + data + confirm-payment）
      'chk-p1-4c4-storefront': {
        description: 'CHK-P1-4C4 legacy one-page retirement regression (checkout components + data + confirm-payment)',
        command: ['node', 'storefront/node_modules/vitest/vitest.mjs', 'run', '--root', 'storefront', 'src/components/checkout/__tests__', 'src/lib/data/__tests__/checkout.test.ts', 'src/lib/data/__tests__/payment.test.ts', 'src/app/[country]/[locale]/(checkout)/confirm-payment/__tests__'],
      },
      // R1（PRD-20260904-r1-contract-generation-infra）：契约生成基建（OpenAPI schema 幂等 + paths $ref 校验 + SDK 类型）
      'chk-r1-contracts': {
        description: 'R1 contract generation checks (api-docs idempotency + validate + rubocop)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-lc', 'cd /rails && bundle exec rubocop lib/tasks/api_docs.rake && bundle exec rake api:docs:schemas:check && bundle exec rake api:docs:validate'],
      },
    },
  },
  plugins: {
    apiVersion: '1.0',
    strict: false,
  },

  // ── token 优化（2026-08-31，见 docs/research/RESEARCH-20260831-harness-token-optimization.md §4.1）──
  // 关闭设计阶段强制产物：非 UI 重构任务不强制 4 设计文档。
  // 约束不受影响：gate 6 层搜索 + PRD + 反模式 + 证据 + 知识同步仍全部保留。
  designStage: { enabled: false },

  // ⑧ eval / scenarios
  scenarios: 'harness/scenarios/scenarios.json',

  // ⑨ check profiles（原 harness/config.json 搬入）
  profiles: {
    quick: {
      timeout: 300,
      checks: ['lint', 'typecheck', 'monorepo-contract', 'api-contract', 'affected-tests', 'anti-patterns', 'degraded-loop', 'nav-validate'],
    },
    full: {
      timeout: 2700,
      checks: ['quick', 'backend-rspec', 'platform-test', 'e2e-dashboard', 'e2e-storefront', 'sdk-integration', 'security', 'coverage', 'ai-scenarios', 'generated-check', 'doc-impact', 'ai-freshness'],
    },
    nightly: {
      checks: ['full', 'payment-matrix', 'browser-matrix', 'flaky-rerun', 'performance', 'ai-scenarios', 'upgrade-matrix'],
    },
    release: {
      checks: ['full', 'sandbox', 'sbom', 'provenance', 'sign', 'manifest'],
    },
  },

  // ⑩ doctor 检查项
  doctor: {
    requiredDirs: ['backend', 'platform', 'storefront', 'ai'],
    requiredFiles: ['AGENTS.md'],
    composeCandidates: ['backend/docker-compose.dev.yml', 'backend/docker-compose.yml', 'docker-compose.yml'],
  },

  // ⑪ 状态/产物路径
  paths: {
    gates: 'harness/gates',
    requirements: 'harness/requirements',
    evidence: 'artifacts/harness-evidence',
    prd: 'docs/prd',
    state: '.harness-state',
  },

  // ⑫ sync-check 知识同步矩阵（原 cli.mjs 硬编码 RULES 搬入）
  syncCheck: {
    rules: [
      { label: 'Model / DB 变更', re: /^(backend\/app\/models|backend\/db\/migrate|backend\/pallastrade_gems\/.*\/db\/migrate)/, assets: ['领域 Skill', 'pallastrade-data-model Skill', '测试', '场景库'] },
      { label: 'API 端点变更', re: /(controllers\/.*\/api\/v3|config\/routes)/, assets: ['backend/public/api-docs/{store,admin}.yaml', 'pallastrade-api-v3 Skill', 'SDK 类型(generated:check)', '场景库'] },
      { label: 'UI 组件 / 页面', re: /storefront\/src\/(components|app)\/.*\.tsx/, assets: ['pallastrade-storefront Skill', '组件测试', '场景库'] },
      { label: '样式 / 设计 token', re: /\.(css|scss)$|tailwind\.config/, assets: ['样式规范(CLAUDE.md / Skill Style Guide 章节)', 'AP-006 检查', 'E2E 截图证据'] },
      { label: '事件 / 订阅者', re: /(app\/subscribers|subscribers)/, assets: ['pallastrade-events-webhooks Skill'] },
      { label: '反模式 / 任务规则', re: /harness\/policies\/(anti-patterns|task-rules)/, assets: ['AGENTS.md §5', '.github/copilot-instructions.md'] },
      { label: 'CLI / 命令能力', re: /(platform\/packages\/cli|ai\/commands)/, assets: ['pallastrade-cli Skill', 'CLI README', 'ai/commands/'] },
      { label: '包 / SDK 能力', re: /platform\/packages\/(sdk|create-pallastrade-app)/, assets: ['pallastrade-typescript-sdk Skill', 'platform/packages/README.md', '根 README'] },
      { label: '技术选型 / 架构', re: /(package\.json|biome\.json|Gemfile|tsconfig|next\.config|pnpm-workspace)/, assets: ['根 AGENTS.md', '各层 CLAUDE.md/AGENTS.md', '技术规范', 'README'] },
      { label: '安全策略', re: /(security|credential|api_key|auth|secret)/, assets: ['pallastrade-security Skill', 'AGENTS.md §8 危险操作'] },
      { label: '部署 / 配置', re: /(Dockerfile|docker-compose|\.env\.example|Procfile|deploy|render\.yaml)/, assets: ['pallastrade-deployment Skill', '.env.example', '部署 README'] },
      { label: 'Skill / PRD 机制', re: /(ai\/skills|harness\/requirements|docs\/prd|scripts\/harness)/, assets: ['pallastrade-prd Skill', 'AGENTS.md', 'copilot-instructions.md', 'scenarios.json'] },
    ],
  },

  // ⑬ generated:check 生成命令（R1 2026-09-04：单一契约管线 = typelizer SDK 类型 + api-docs OpenAPI schema + platform 副本同步）
  // contracts.sh 在无 docker/linux 时 SKIP（CI node-only runner 保持 pass），有容器时真实生成（幂等）→ 漂移可被检出。
  generatedCheck: {
    checks: [
      { name: 'Contracts (SDK types + OpenAPI schemas)', cwd: '.', cmd: 'bash scripts/ci/contracts.sh || echo "SKIP: contracts.sh requires docker+linux (run scripts/ci/contracts.sh on linux or sync manually on Windows)"' },
    ],
  },
};
