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
      // 仓库级回归守卫（2026-09-14）：部署脚本前滚检测 + 回滚演练 crontab 恢复 + PRD 状态同步
      // 台账收口 TASK-20260913113813-6b5a2a47 / TASK-20260913103421-bd645649 的证据来源。
      'repo-guards-test': {
        description: 'Repo-level node:test guards (pull-deploy forward roll + drill crontab restore + PRD status sync)',
        command: ['node', '--test', 'tests/pull-deploy-forward-roll.test.mjs', 'tests/drill-rollback-crontab.test.mjs', 'tests/prd-status-sync.test.mjs'],
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
      'admin-catalog-health-rspec': {
        description: 'Admin catalog health specs (issue semantics + filtered products list + banner + navigation consistency)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/pallastrade/admin/catalog_health_spec.rb spec/requests/pallastrade/admin/navigation_consistency_spec.rb'],
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
      // 评论系统升级一期（PRD-20260916-catalog-batch-f1-reviews）：评分分布与分页同源
      // + 图片直传（presign/归属/上限/类型）+ 审核页图片列
      'reviews-f1-rspec': {
        description: 'Review upgrade specs (paginated list with rating_distribution, load-more pages, image ownership/limit/signed-id errors, model photo limits, admin photo column)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/requests/api/v3/store/reviews_spec.rb spec/requests/api/v3/store/reviews_pagination_spec.rb spec/requests/api/v3/store/reviews_images_spec.rb spec/models/pallastrade/review_spec.rb spec/requests/pallastrade/admin/reviews_spec.rb'],
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
      // 财务对账线（FIN-P4-6/7 + DSP-P7-3 + REV-P6-7）：只读对账（source/transaction/dispute）+ 扫措作业
      'finance-reconciliation-rspec': {
        description: 'Finance reconciliation specs (source/transaction/payment/refund/dispute reconcilers + sweeper job)',
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
