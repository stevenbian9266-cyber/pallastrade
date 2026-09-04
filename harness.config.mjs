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
    base: 'origin/main',
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
      // P1 订单流程改造：本次变更相关 spec（新购物车/提交订单/回归）
      'p1-order-flow-rspec': {
        description: 'P1 order-flow specs (cart/submit/request + regression)',
        command: ['docker', 'exec', 'pallastrade-web-1', 'bash', '-c', 'cd /rails && DISABLE_SIMPLECOV_MINIMUM=1 bundle exec rspec spec/models/pallastrade/cart_spec.rb spec/services/pallastrade/carts/submit_spec.rb spec/requests/api/v3/store/carts_controller_spec.rb spec/models/pallastrade/order_parent_child_spec.rb spec/requests/api/v3/store/payment_combinations_controller_spec.rb spec/services/pallastrade/carts/auto_split_spec.rb'],
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
