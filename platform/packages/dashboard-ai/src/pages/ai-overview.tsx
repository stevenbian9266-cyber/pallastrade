import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Card, CardContent, CardHeader, CardTitle } from '@pallastrade/dashboard-ui'
import { PageHeader } from '@pallastrade/dashboard-core'
import { ResourceLayout } from '@pallastrade/dashboard-ui'
import { aiClient } from '../client'
import type { AiUsageResponse } from '../types'

/**
 * AI Overview page — master switch, system status, provider count,
 * enabled models, capabilities, today's usage, and recent failures.
 */
export function AiOverviewPage() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()

  const { data: settings, isLoading: settingsLoading } = useQuery({
    queryKey: ['ai', 'settings'],
    queryFn: async () => {
      const res = await aiClient.getSettings()
      return res.data
    },
  })

  const { data: providers, isLoading: providersLoading } = useQuery({
    queryKey: ['ai', 'providers'],
    queryFn: async () => {
      const res = await aiClient.getProviders()
      return res.data
    },
  })

  const { data: capabilities, isLoading: capsLoading } = useQuery({
    queryKey: ['ai', 'capabilities'],
    queryFn: async () => {
      const res = await aiClient.getCapabilities()
      return res.data
    },
  })

  const { data: usage } = useQuery({
    queryKey: ['ai', 'usage'],
    queryFn: async () => {
      const res = await aiClient.getUsage()
      return res.data as AiUsageResponse
    },
  })

  const toggleMutation = useMutation({
    mutationFn: (active: boolean) =>
      aiClient.updateSettings({ setting: { active } }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'settings'] }),
  })

  const isLoading = settingsLoading || providersLoading || capsLoading

  if (isLoading) {
    return <div className="p-6 text-muted-foreground">Loading…</div>
  }

  const activeCaps = capabilities?.filter((c: { active: boolean }) => c.active) ?? []

  return (
    <ResourceLayout
      header={
        <PageHeader
          title={t('admin.ai.overview.title')}
          actions={
            <label className="flex items-center gap-3">
              <span className="text-sm font-medium">{t('admin.ai.overview.store_switch')}</span>
              <input
                type="checkbox"
                checked={settings?.active ?? false}
                onChange={(e) => toggleMutation.mutate(e.target.checked)}
                className="toggle"
              />
            </label>
          }
        />
      }
      main={
        <>
          {!settings?.active && (
            <Card className="border-warning bg-warning/5">
              <CardContent className="py-4">
                <p className="text-sm text-warning-foreground">
                  {t('admin.ai.overview.system_disabled')}
                </p>
              </CardContent>
            </Card>
          )}

          <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-4">
            <Card>
              <CardHeader>
                <CardTitle className="text-sm">{t('admin.ai.overview.providers_configured')}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">{providers?.length ?? 0}</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-sm">{t('admin.ai.overview.models_enabled')}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">
                  {providers?.reduce(
                    (acc: number, p: { active_model_count: number }) => acc + (p.active_model_count ?? 0),
                    0,
                  ) ?? 0}
                </p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-sm">{t('admin.ai.overview.capabilities_enabled')}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">{activeCaps.length}</p>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle className="text-sm">{t('admin.ai.overview.today_usage')}</CardTitle>
              </CardHeader>
              <CardContent>
                <p className="text-2xl font-bold">{usage?.summary?.total_runs ?? 0}</p>
                <p className="text-xs text-muted-foreground">
                  {t('admin.ai.usage.succeeded')}: {usage?.summary?.succeeded ?? 0} |{' '}
                  {t('admin.ai.usage.failed')}: {usage?.summary?.failed ?? 0}
                </p>
              </CardContent>
            </Card>
          </div>

          {usage?.summary && (
            <Card>
              <CardHeader>
                <CardTitle>{t('admin.ai.usage.title')}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
                  <div>
                    <span className="text-xs text-muted-foreground">{t('admin.ai.usage.tokens')}</span>
                    <p className="font-mono text-sm tabular-nums">
                      {(usage.summary.total_input_tokens ?? 0) + (usage.summary.total_output_tokens ?? 0)}
                    </p>
                  </div>
                  <div>
                    <span className="text-xs text-muted-foreground">{t('admin.ai.usage.estimated_cost')}</span>
                    <p className="font-mono text-sm tabular-nums">
                      ${Number(usage.summary.total_estimated_cost ?? 0).toFixed(4)}
                    </p>
                  </div>
                  <div>
                    <span className="text-xs text-muted-foreground">{t('admin.ai.usage.avg_latency')}</span>
                    <p className="font-mono text-sm tabular-nums">
                      {usage.summary.avg_latency_ms ?? '—'}ms
                    </p>
                  </div>
                </div>
              </CardContent>
            </Card>
          )}
        </>
      }
    />
  )
}
