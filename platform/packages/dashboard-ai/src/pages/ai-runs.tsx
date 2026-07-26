import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, Badge } from '@pallastrade/dashboard-ui'
import { PageHeader } from '@pallastrade/dashboard-core'
import { ResourceLayout } from '@pallastrade/dashboard-ui'
import { aiClient } from '../client'
import type { AiRun } from '../types'

const STATUS_COLORS: Record<string, 'success' | 'destructive' | 'secondary' | 'outline'> = {
  succeeded: 'success',
  failed: 'destructive',
  queued: 'secondary',
  running: 'outline',
  cancelled: 'secondary',
  skipped: 'secondary',
}

/**
 * AI Runs page — view call history with filters for status, capability, provider, and dates.
 */
export function AiRunsPage() {
  const { t } = useTranslation()
  const [filters, setFilters] = useState<Record<string, string>>({})

  const { data: runs, isLoading } = useQuery({
    queryKey: ['ai', 'runs', filters],
    queryFn: async () => {
      const res = await aiClient.getRuns(filters)
      return res.data as AiRun[]
    },
  })

  if (isLoading) {
    return <div className="p-6 text-muted-foreground">Loading…</div>
  }

  return (
    <ResourceLayout
      header={<PageHeader title={t('admin.ai.run.title')} />}
      main={
        <>
          {/* Filters */}
          <div className="flex gap-3">
            <select
              className="rounded border p-2 text-sm"
              value={filters.status ?? ''}
              onChange={(e) =>
                setFilters((prev) => ({ ...prev, status: e.target.value || '' }))
              }
            >
              <option value="">All Statuses</option>
              <option value="succeeded">Succeeded</option>
              <option value="failed">Failed</option>
              <option value="skipped">Skipped</option>
              <option value="running">Running</option>
              <option value="queued">Queued</option>
            </select>

            <select
              className="rounded border p-2 text-sm"
              value={filters.mode ?? ''}
              onChange={(e) =>
                setFilters((prev) => ({ ...prev, mode: e.target.value || '' }))
              }
            >
              <option value="">All Modes</option>
              <option value="sync">Sync</option>
              <option value="async">Async</option>
            </select>
          </div>

          {(!runs || runs.length === 0) && (
            <Card>
              <CardContent className="py-12 text-center text-muted-foreground">
                {t('admin.ai.run.no_data')}
              </CardContent>
            </Card>
          )}

          <div className="space-y-2">
            {(runs ?? []).map((run: AiRun) => (
              <Card key={run.id}>
                <CardHeader className="flex flex-row items-center justify-between pb-2">
                  <div>
                    <CardTitle className="text-sm font-mono">
                      {run.capability_key ?? 'Unknown capability'}
                    </CardTitle>
                    <p className="text-xs text-muted-foreground font-mono">{run.id}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    <Badge variant={run.mode === 'sync' ? 'outline' : 'secondary'}>
                      {run.mode}
                    </Badge>
                    <Badge variant={STATUS_COLORS[run.status] ?? 'secondary'}>
                      {t(`admin.ai.run.status.${run.status}`)}
                    </Badge>
                  </div>
                </CardHeader>
                <CardContent>
                  <div className="grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
                    <div>
                      <span className="text-muted-foreground">Model:</span>{' '}
                      {run.provider_model_id || '—'}
                    </div>
                    <div>
                      <span className="text-muted-foreground">Tokens:</span>{' '}
                      {(run.input_tokens ?? 0) + (run.output_tokens ?? 0)}
                    </div>
                    <div>
                      <span className="text-muted-foreground">Latency:</span>{' '}
                      {run.latency_ms ? `${run.latency_ms}ms` : '—'}
                    </div>
                    <div>
                      <span className="text-muted-foreground">Cost:</span>{' '}
                      {run.estimated_cost ? `$${Number(run.estimated_cost).toFixed(4)}` : '—'}
                    </div>
                    {run.error_code && (
                      <div className="col-span-full text-destructive">
                        {run.error_code}: {run.error_message}
                      </div>
                    )}
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </>
      }
    />
  )
}
