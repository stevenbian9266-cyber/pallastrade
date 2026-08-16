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
    maxAssetBytes: 524288,
    maxContextAssets: 24,
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
    maxOutputBytes: 262144,
  },
  plugins: {
    apiVersion: '1.0',
    strict: false,
  },

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

  // ⑬ generated:check 生成命令（SDK 类型 / CLI spec）
  generatedCheck: {
    checks: [
      { name: 'SDK Types', cwd: 'platform', cmd: 'pnpm --filter @pallastrade/sdk generate:types 2>/dev/null || echo "SKIP: sdk types generation not configured"' },
      { name: 'CLI Admin Spec', cwd: 'platform', cmd: 'pnpm --filter @pallastrade/cli generate:admin-spec 2>/dev/null || echo "SKIP: cli spec generation not configured"' },
    ],
  },
};
