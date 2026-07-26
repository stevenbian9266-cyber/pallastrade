import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Card, CardContent, CardHeader, CardTitle, Badge } from '@pallastrade/dashboard-ui'
import { PageHeader } from '@pallastrade/dashboard-core'
import { ResourceLayout } from '@pallastrade/dashboard-ui'
import { aiClient } from '../client'
import type { AiCapability } from '../types'

/**
 * AI Capabilities page — view registered capabilities and their store-level configuration.
 * Capabilities are code-registered; this page is driven by the backend Registry.
 */
export function AiCapabilitiesPage() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()

  const { data: capabilities, isLoading } = useQuery({
    queryKey: ['ai', 'capabilities'],
    queryFn: async () => {
      const res = await aiClient.getCapabilities()
      return res.data as AiCapability[]
    },
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) =>
      aiClient.updateCapabilitySetting(id, { capability_setting: { active } }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'capabilities'] }),
  })

  if (isLoading) {
    return <div className="p-6 text-muted-foreground">Loading…</div>
  }

  if (!capabilities || capabilities.length === 0) {
    return (
      <ResourceLayout
        header={<PageHeader title={t('admin.ai.capability.title')} />}
        main={
          <Card>
            <CardContent className="py-12 text-center text-muted-foreground">
              <p className="text-lg">{t('admin.ai.capability.empty')}</p>
            </CardContent>
          </Card>
        }
      />
    )
  }

  return (
    <ResourceLayout
      header={<PageHeader title={t('admin.ai.capability.title')} />}
      main={
        <div className="space-y-3">
          {capabilities.map((cap: AiCapability) => (
            <Card key={cap.key}>
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <div>
                  <CardTitle className="text-base">{cap.display_name}</CardTitle>
                  <p className="text-xs text-muted-foreground font-mono">{cap.key}</p>
                </div>
                <div className="flex items-center gap-3">
                  <Badge variant={cap.configured ? 'success' : 'secondary'}>
                    {cap.configured ? (cap.active ? 'Active' : 'Configured') : t('admin.ai.capability.not_configured')}
                  </Badge>
                  {cap.setting_id && (
                    <label className="flex items-center gap-2">
                      <input
                        type="checkbox"
                        checked={cap.active}
                        onChange={(e) =>
                          toggleMutation.mutate({ id: cap.setting_id!, active: e.target.checked })
                        }
                        className="toggle"
                      />
                    </label>
                  )}
                </div>
              </CardHeader>
              <CardContent>
                <div className="space-y-2 text-sm">
                  <p>{cap.description}</p>
                  <div className="flex gap-4 text-muted-foreground">
                    <span>v{cap.version}</span>
                    <span>Mode: {cap.execution_mode}</span>
                    <span>Classification: {cap.data_classification}</span>
                  </div>
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      }
    />
  )
}
