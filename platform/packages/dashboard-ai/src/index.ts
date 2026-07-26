/**
 * @pallastrade/dashboard-ai — AI Tools dashboard plugin.
 *
 * Adds complete AI management to the PallasTrade admin dashboard:
 *
 *   - **Nav entry** "AI Tools" in the main sidebar with sub-items.
 *   - **Routes** for overview, providers, models, capabilities, and runs.
 *   - **Pages** with full CRUD for AI configuration.
 *   - **Table definitions** for runs and usage.
 *   - **Translations** under `admin.ai.*`, deep-merged into i18next.
 *
 * Activation is automatic via the `pallastrade.dashboard.plugin` marker
 * in package.json.
 */
import { defineDashboardPlugin, defineTable, i18n } from '@pallastrade/dashboard-core'
import { RelativeTime } from '@pallastrade/dashboard-ui'
import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { aiClient } from './client'
import en from './locales/en.json'
import zhCN from './locales/zh-CN.json'
import type { AiRun } from './types'

// ---------------------------------------------------------------------------
// 1. Register translations
// ---------------------------------------------------------------------------
i18n.addResourceBundle('en', 'translation', en, true, true)
i18n.addResourceBundle('zh-CN', 'translation', zhCN, true, true)

// ---------------------------------------------------------------------------
// 2. Declare the AI Runs table
// ---------------------------------------------------------------------------
defineTable<AiRun>('ai_runs', {
  title: i18n.t('admin.ai.run.title'),
  searchParam: 'search',
  searchPlaceholder: 'Search runs...',
  defaultSort: { field: 'created_at', direction: 'desc' },
  emptyMessage: i18n.t('admin.ai.run.no_data'),
  columns: [
    {
      key: 'id',
      header: 'ID',
      width: '120px',
      render: (run) => <code className="text-xs">{run.id?.slice(0, 12)}...</code>,
    },
    {
      key: 'capability_key',
      header: 'Capability',
      width: '180px',
      render: (run) => <span className="font-medium">{run.capability_key || '—'}</span>,
    },
    {
      key: 'status',
      header: 'Status',
      width: '100px',
      render: (run) => <StatusBadge status={run.status} />,
    },
    {
      key: 'provider_model_id',
      header: 'Model',
      width: '180px',
      render: (run) => <span className="text-sm">{run.provider_model_id || '—'}</span>,
    },
    {
      key: 'estimated_cost',
      header: 'Cost',
      width: '100px',
      render: (run) =>
        run.estimated_cost ? (
          <span className="tabular-nums">${Number(run.estimated_cost).toFixed(4)}</span>
        ) : (
          '—'
        ),
    },
    {
      key: 'input_tokens',
      header: 'Tokens',
      width: '120px',
      render: (run) => (
        <span className="text-sm tabular-nums">
          {(run.input_tokens ?? 0) + (run.output_tokens ?? 0)}
        </span>
      ),
    },
    {
      key: 'latency_ms',
      header: 'Latency',
      width: '100px',
      render: (run) =>
        run.latency_ms ? <span className="tabular-nums">{run.latency_ms}ms</span> : '—',
    },
    {
      key: 'created_at',
      header: 'Time',
      width: '160px',
      render: (run) =>
        run.created_at ? <RelativeTime date={run.created_at} /> : '—',
    },
  ],
})

// ---------------------------------------------------------------------------
// 3. Register the dashboard plugin
// ---------------------------------------------------------------------------
defineDashboardPlugin({
  id: 'pallastrade-ai-tools',
  name: 'AI Tools',

  // Navigation entries
  nav: [
    {
      id: 'ai',
      label: i18n.t('admin.ai.menu.title'),
      icon: 'sparkles',
      permission: 'ai_usage_display',
      children: [
        {
          id: 'ai-overview',
          label: i18n.t('admin.ai.menu.overview'),
          to: '/$storeId/ai',
          permission: 'ai_usage_display',
        },
        {
          id: 'ai-providers',
          label: i18n.t('admin.ai.menu.providers'),
          to: '/$storeId/ai/providers',
          permission: 'ai_configuration_management',
        },
        {
          id: 'ai-models',
          label: i18n.t('admin.ai.menu.models'),
          to: '/$storeId/ai/models',
          permission: 'ai_configuration_management',
        },
        {
          id: 'ai-capabilities',
          label: i18n.t('admin.ai.menu.capabilities'),
          to: '/$storeId/ai/capabilities',
          permission: 'ai_configuration_management',
        },
        {
          id: 'ai-runs',
          label: i18n.t('admin.ai.menu.runs'),
          to: '/$storeId/ai/runs',
          permission: 'ai_usage_display',
        },
      ],
    },
  ],

  // Route definitions
  routes: [
    { path: '/$storeId/ai', component: () => import('./routes/ai.index') },
    { path: '/$storeId/ai/providers', component: () => import('./routes/ai.providers') },
    { path: '/$storeId/ai/models', component: () => import('./routes/ai.models') },
    { path: '/$storeId/ai/capabilities', component: () => import('./routes/ai.capabilities') },
    { path: '/$storeId/ai/runs', component: () => import('./routes/ai.runs') },
  ],
})

// ---------------------------------------------------------------------------
// 4. Re-export for consumers
// ---------------------------------------------------------------------------
export { aiClient } from './client'
export type * from './types'
